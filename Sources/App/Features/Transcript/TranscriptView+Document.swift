/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import Foundation

/** The document itself: the lines the transcript holds, the characters they
 drew, and every edit that adds, removes or redraws one. `lineStarts` is what
 makes an edit local — it names where each line begins, so a reaction or a
 delivery receipt rewrites one line rather than the whole conversation. */
extension TranscriptView {
	func replaceLines(_ newLines: [TranscriptRow]) {
		performEditingBatch {
			clear()
			scrollbackAllowance = 0
			followsBottom = true
			lines = Array(newLines.suffix(bufferLimit))
			rebuild(preservingScrollPosition: false)
			scrollToBottom()
		}
	}

	func appendLines(_ newLines: [TranscriptRow]) {
		performEditingBatch {
			/* A reload that is retried re-sends lines the document already shows,
			 and a line drawn twice is a line the reader reads twice. */
			let accepted = acceptingNewIdentifiers(newLines)
			guard accepted.isEmpty == false else { return }
			let followsBottom = followsBottom
			let anchor = selectionAnchor()
			insert(accepted, at: lines.count)
			trimToBufferLimit()
			updateLayoutAfterEdit()
			restoreSelection(anchor)
			if followsBottom {
				scrollToBottom()
			}
		}
	}

	/** Adds older lines above what is already drawn.

	 Nothing is dropped from the end: the newest lines are the ones the reader
	 comes back to, and the controller still names them. The window's top edge
	 grows instead, up to the largest scrollback the preference allows, which is
	 what keeps a reader who holds the scroll wheel from growing the document
	 without bound. */
	@discardableResult
	func prependLines(_ newLines: [TranscriptRow]) -> [String] {
		performEditingBatch {
			guard newLines.isEmpty == false else { return [] }
			let room = TranscriptBufferPolicy.validLimits.upperBound - lines.count
			guard room > 0 else { return [] }
			/* The tail of the fetched block is the part adjacent to what is on
			 screen, so a block that does not fit keeps its newest lines. */
			let accepted = Array(acceptingNewIdentifiers(newLines).suffix(room))
			let anchor = selectionAnchor()
			preservingVisibleText {
				insert(accepted, at: 0)
				scrollbackAllowance += accepted.count
				updateLayoutAfterEdit()
			}
			restoreSelection(anchor)
			return accepted.map(\.lineNumber)
		}
	}

	/// The lines of `newLines` the document does not already hold, in order and
	/// without repeats within the batch itself.
	private func acceptingNewIdentifiers(_ newLines: [TranscriptRow]) -> [TranscriptRow] {
		var batch = Set<String>()
		return newLines.filter {
			lineOrdinals[$0.lineNumber] == nil && batch.insert($0.lineNumber).inserted
		}
	}

	/// The index of the line `identifier` names, under either identifier a
	/// restored row answers to.
	func index(ofLine identifier: String) -> Int? {
		guard let ordinal = lineOrdinals[identifier] else { return nil }
		let index = ordinal - firstLineOrdinal
		return lines.indices.contains(index) ? index : nil
	}

	func clearLines() {
		performEditingBatch { clear() }
	}

	private func clear() {
		closeMemberInformation()
		lines.removeAll()
		lineStarts = [0]
		highlightedLineCount = 0
		forgetLineIndex()
		inlineImages.removeAll()
		beginNicknameColorBatch()
		scrollbackAllowance = 0
		textView.textStorage?.setAttributedString(NSAttributedString())
		inlineImageLoader.cancelLoads(forView: viewIdentifier)
		updateLayoutAfterEdit()
	}

	func updateDelivery(_ update: TranscriptDeliveryUpdate) {
		performEditingBatch {
			guard let index = index(ofLine: update.lineNumber) else { return }
			if let messageIdentifier = update.messageIdentifier, messageIdentifier != lines[index].messageIdentifier {
				unindexMessage(of: lines[index], ordinal: firstLineOrdinal + index)
				lines[index].messageIdentifier = messageIdentifier
				indexMessage(of: lines[index], ordinal: firstLineOrdinal + index)
			}
			lines[index].deliveryState = update.state
			lines[index].deliveryFailureReason = update.reason
			refresh(at: index)
		}
	}

	func updateReactions(_ reactions: [String: [String]], messageIdentifier: String) {
		performEditingBatch {
			for ordinal in messageLineOrdinals[messageIdentifier] ?? [] {
				let index = ordinal - firstLineOrdinal
				guard lines.indices.contains(index) else { continue }
				lines[index].mergeReactions(reactions)
				refresh(at: index)
			}
		}
	}

	func setUnreadMarker(_ mark: TranscriptScrollbackMark) {
		performEditingBatch { applyUnreadMarker(mark) }
	}

	private func applyUnreadMarker(_ mark: TranscriptScrollbackMark) {
		var changed: [Int] = []
		for index in lines.indices where lines[index].markers.contains(where: \.isUnread) {
			lines[index].markers.removeAll(where: \.isUnread)
			changed.append(index)
		}
		let target: Int? = switch mark {
		case .none: nil
		case .latest: lines.indices.last
		/* A line the buffer no longer holds is one it has already trimmed, and
		 it only ever trims the oldest: everything on screen arrived after the
		 line the reader stopped at, so the boundary belongs above all of it.
		 A conversation opened unseen carries its marker the same way. */
		case let .line(identifier): index(ofLine: identifier) ?? lines.indices.first
		case let .after(date): lines.firstIndex { $0.receivedAt >= date && $0.lineType.isConversation }
		}
		if let target {
			lines[target].markers.insert(.unread(MainWindowStrings.Conversation.unreadMessages), at: 0)
			if changed.contains(target) == false {
				changed.append(target)
			}
		}
		for index in changed.sorted() {
			refresh(at: index)
		}
	}

	/// A download outlives the line that asked for it, so an image whose line
	/// has already scrolled out of the buffer is dropped rather than kept.
	@discardableResult
	func addInlineImage(_ image: TranscriptInlineImage) -> Bool {
		performEditingBatch { insertInlineImage(image) }
	}

	private func insertInlineImage(_ image: TranscriptInlineImage) -> Bool {
		guard let index = index(ofLine: image.lineNumber), lines[index].lineNumber == image.lineNumber
		else { return false }
		var images = inlineImages[image.lineNumber] ?? []
		guard !images.contains(where: { $0.linkIdentifier == image.linkIdentifier }),
		      let decoded = NSImage(data: image.imageData), decoded.size.width > 0,
		      decoded.size.height > 0 else { return false }
		let attachment = NSTextAttachment()
		attachment.image = decoded
		images.append(CachedTranscriptImage(
			linkIdentifier: image.linkIdentifier,
			sourceURL: image.sourceURL,
			image: decoded,
			originalSize: decoded.size,
			attachment: attachment
		))
		inlineImages[image.lineNumber] = images
		refresh(at: index)
		return true
	}

	/** The ceiling the buffer is trimmed to.

	 While the reader follows the end it is what they asked for, widened by any
	 scrollback pulled in since. While they are reading back it is the largest
	 scrollback the preference allows: every line trimmed from the top then is
	 one the reader may be looking at, and trimming it moved the text under them
	 and pulled the viewport into the range that fetches more history — so a
	 busy channel dropped what the reader had loaded and fetched it again, once
	 per message. The scrollback comes back down when they return to the end. */
	private var effectiveBufferLimit: Int {
		let ceiling = TranscriptBufferPolicy.validLimits.upperBound
		return followsBottom ? min(bufferLimit + scrollbackAllowance, ceiling) : ceiling
	}

	/// Drops the oldest lines that no longer fit. Only the oldest: the end of
	/// the transcript is what the controller, the jump commands and the reader
	/// all address.
	func trimToBufferLimit(force: Bool = false) {
		guard editDepth == 0 || force else { return }
		let limit = effectiveBufferLimit
		guard lines.count > limit else { return }
		let count = lines.count - limit
		preservingVisibleText {
			remove(lines.startIndex ..< count)
		}
	}

	/// Where a line begins in the text storage. `lines.count` names the end of
	/// the document, which is where an append starts writing.
	private func documentLocation(ofLineAt index: Int) -> Int {
		lineStarts[index]
	}

	/// How many characters a line drew.
	private func documentLength(ofLineAt index: Int) -> Int {
		lineStarts[index + 1] - lineStarts[index]
	}

	/// Moves every line after `index` by `delta`, which is what an edit that
	/// changed the length of one line leaves to do.
	private func shiftLineStarts(after index: Int, by delta: Int) {
		guard delta != 0 else { return }
		for position in (index + 1) ..< lineStarts.count {
			lineStarts[position] += delta
		}
	}

	func range(ofLine lineNumber: String) -> NSRange? {
		guard let index = index(ofLine: lineNumber) else { return nil }
		return NSRange(location: documentLocation(ofLineAt: index), length: documentLength(ofLineAt: index))
	}

	/// Renders `newLines` and splices them into the document at `index`.
	private func insert(_ newLines: [TranscriptRow], at index: Int) {
		guard let storage = textView.textStorage, newLines.isEmpty == false else { return }
		beginNicknameColorBatch()
		let origin = documentLocation(ofLineAt: index)
		var starts: [Int] = []
		starts.reserveCapacity(newLines.count)
		var location = origin
		/* Lines arrive at either end: in front of the first ordinal, or after
		 the last. */
		precondition(index == 0 || index == lines.count)
		if index == 0 {
			firstLineOrdinal -= newLines.count
		}
		let firstOrdinal = firstLineOrdinal + index
		storage.beginEditing()
		defer { storage.endEditing() }
		for start in stride(from: 0, to: newLines.count, by: 32) {
			let rendered = NSMutableAttributedString()
			for line in newLines[start ..< min(start + 32, newLines.count)] {
				starts.append(location + rendered.length)
				rendered.append(render(line))
			}
			storage.replaceCharacters(in: NSRange(location: location, length: 0), with: rendered)
			location += rendered.length
		}
		lines.insert(contentsOf: newLines, at: index)
		lineStarts.insert(contentsOf: starts, at: index)
		shiftLineStarts(after: index + newLines.count - 1, by: location - origin)
		/* In front, the new lines' message ordinals come before the ones already
		 held, so they are indexed newest first to keep each list ascending. */
		let ordinals = Array(zip(newLines.indices, newLines))
		for (offset, line) in index == 0 ? ordinals.reversed() : ordinals {
			let ordinal = firstOrdinal + offset
			for identifier in line.identifiers where lineOrdinals[identifier] == nil {
				lineOrdinals[identifier] = ordinal
			}
			indexMessage(of: line, ordinal: ordinal, inFront: index == 0)
		}
		highlightedLineCount += newLines.filter(\.body.isHighlight).count
	}

	private func indexMessage(of line: TranscriptRow, ordinal: Int, inFront: Bool = false) {
		guard let identifier = line.messageIdentifier else { return }
		if inFront {
			messageLineOrdinals[identifier, default: []].insert(ordinal, at: 0)
		} else {
			messageLineOrdinals[identifier, default: []].append(ordinal)
		}
	}

	private func unindexMessage(of line: TranscriptRow, ordinal: Int) {
		guard let identifier = line.messageIdentifier else { return }
		messageLineOrdinals[identifier]?.removeAll { $0 == ordinal }
		if messageLineOrdinals[identifier]?.isEmpty == true {
			messageLineOrdinals.removeValue(forKey: identifier)
		}
	}

	private func forgetLineIndex() {
		lineOrdinals.removeAll()
		messageLineOrdinals.removeAll()
		firstLineOrdinal = 0
	}

	/// Removes the oldest `indices` lines and the characters they drew. Only the
	/// oldest: that is the one end lines ever leave from.
	private func remove(_ indices: Range<Int>) {
		guard let storage = textView.textStorage, indices.isEmpty == false else { return }
		precondition(indices.lowerBound == 0)
		/* The profile popover is anchored to characters; a line appended under
		 the name leaves them where they are, but a trim or a clear moves or
		 removes them, and a popover pointing at whatever took their place is
		 worse than none. */
		closeMemberInformation()
		let location = documentLocation(ofLineAt: indices.lowerBound)
		let length = documentLocation(ofLineAt: indices.upperBound) - location
		var retiredMarkers: [String: TranscriptMarker] = [:]
		let retiredLineNumbers = lines[indices].map(\.lineNumber)
		var retiredMessageIdentifiers: [String] = []
		for (offset, line) in zip(indices, lines[indices]) {
			let ordinal = firstLineOrdinal + offset
			for identifier in line.identifiers where lineOrdinals[identifier] == ordinal {
				lineOrdinals.removeValue(forKey: identifier)
			}
			unindexMessage(of: line, ordinal: ordinal)
			if let messageIdentifier = line.messageIdentifier, messageLineOrdinals[messageIdentifier] == nil {
				retiredMessageIdentifiers.append(messageIdentifier)
			}
			inlineImages.removeValue(forKey: line.lineNumber)
			for marker in line.markers {
				retiredMarkers[marker.selectionSegment] = marker
			}
		}
		storage.deleteCharacters(in: NSRange(location: location, length: length))
		highlightedLineCount -= lines[indices].filter(\.body.isHighlight).count
		lines.removeSubrange(indices)
		lineStarts.removeSubrange(indices)
		firstLineOrdinal += indices.count
		shiftLineStarts(after: indices.lowerBound - 1, by: -length)
		if retiredMessageIdentifiers.isEmpty == false {
			viewController?.transcriptDidRetireMessages(retiredMessageIdentifiers)
		}
		for identifier in retiredLineNumbers {
			inlineImageLoader.cancelLoads(forView: viewIdentifier, lineNumber: identifier)
		}
		if indices.lowerBound == 0, !lines.isEmpty {
			let existing = Set(lines[0].markers.map(\.selectionSegment))
			let carried = retiredMarkers.values.filter { !existing.contains($0.selectionSegment) }
			if !carried.isEmpty {
				lines[0].markers.insert(contentsOf: carried.sorted { $0.selectionSegment < $1.selectionSegment }, at: 0)
				refresh(at: 0)
			}
		}
	}

	/// Redraws one line in place. A delivery receipt, a reaction, an unread
	/// boundary or a decoded image changes that line and nothing else.
	private func refresh(at index: Int) {
		guard let storage = textView.textStorage, lines.indices.contains(index) else { return }
		beginNicknameColorBatch()
		let anchor = selectionAnchor()
		let rendered = render(lines[index])
		let previousLength = documentLength(ofLineAt: index)
		storage.replaceCharacters(
			in: NSRange(location: documentLocation(ofLineAt: index), length: previousLength),
			with: rendered
		)
		shiftLineStarts(after: index, by: rendered.length - previousLength)
		updateLayoutAfterEdit()
		restoreSelection(anchor)
	}

	/** Rewrites the whole document.

	 Only a change that alters how every line draws needs one: the theme and the
	 text scale. Ordinary traffic edits the storage in place, which is what keeps
	 a busy channel from re-rendering its whole scrollback per message. */
	func rebuild(preservingScrollPosition: Bool = true) {
		let oldOrigin = scrollView.contentView.bounds.origin
		let viewport = viewportAnchor()
		let anchor = selectionAnchor()
		beginNicknameColorBatch()
		let retainedLines = lines
		lines.removeAll(keepingCapacity: true)
		lineStarts = [0]
		highlightedLineCount = 0
		forgetLineIndex()
		textView.textStorage?.beginEditing()
		textView.textStorage?.setAttributedString(NSAttributedString())
		insert(retainedLines, at: 0)
		textView.textStorage?.endEditing()
		updateLayoutAfterEdit()
		restoreSelection(anchor)
		guard preservingScrollPosition, window != nil, !isHiddenOrHasHiddenAncestor, editDepth == 0 else { return }
		if let viewport {
			restoreViewport(viewport)
			return
		}
		textView.layoutSubtreeIfNeeded()
		scrollView.contentView.scroll(to: oldOrigin)
		scrollView.reflectScrolledClipView(scrollView.contentView)
		noteViewportMovedByView()
	}

	/// Runs an edit that changes what sits above the viewport and keeps the
	/// text the reader is looking at where it was.
	private func preservingVisibleText(_ edit: () -> Void) {
		guard window != nil, !isHiddenOrHasHiddenAncestor, editDepth == 0 else {
			edit()
			return
		}
		let oldHeight = textView.bounds.height
		let origin = scrollView.contentView.bounds.origin
		edit()
		textView.layoutSubtreeIfNeeded()
		var adjusted = origin
		adjusted.y += textView.bounds.height - oldHeight
		scrollView.contentView.scroll(to: adjusted)
		scrollView.reflectScrolledClipView(scrollView.contentView)
		noteViewportMovedByView()
	}
}
