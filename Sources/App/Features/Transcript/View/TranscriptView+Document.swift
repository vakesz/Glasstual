// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
import os

/** Every edit to the transcript's text: what it draws, where it draws it, and
 what the document has to be told afterwards. The bookkeeping itself lives in
 ``TranscriptDocument``; this is the half that renders characters, splices them
 into the text storage and keeps the selection and the viewport in step. */
extension TranscriptView {
	func replaceLines(_ newLines: [TranscriptRow]) {
		performEditingBatch {
			clear()
			followsBottom = true
			insert(Array(newLines.suffix(document.bufferLimit)), at: 0)
			updateLayoutAfterEdit()
			scrollToBottom()
		}
	}

	func appendLines(_ newLines: [TranscriptRow]) {
		performEditingBatch {
			/* A reload that is retried re-sends lines the document already shows,
			 and a line drawn twice is a line the reader reads twice. */
			let accepted = document.accepting(newLines)
			guard accepted.isEmpty == false else { return }
			let followsBottom = followsBottom
			insert(accepted, at: document.count)
			updateLayoutAfterEdit()
			if followsBottom {
				scrollToBottom()
			}
		}
	}

	/** Adds older lines above what is already drawn.

	 Nothing is dropped from the end: the newest lines are the ones the reader
	 comes back to, and the controller still names them. The window's top edge
	 grows instead, up to the largest scrollback the setting allows, which is
	 what keeps a reader who holds the scroll wheel from growing the document
	 without bound. */
	@discardableResult
	func prependLines(_ newLines: [TranscriptRow]) -> [String] {
		performEditingBatch {
			guard newLines.isEmpty == false else { return [] }
			let room = document.roomBeforeCeiling
			guard room > 0 else { return [] }
			/* The tail of the fetched block is the part adjacent to what is on
			 screen, so a block that does not fit keeps its newest lines. */
			let accepted = Array(document.accepting(newLines).suffix(room))
			insert(accepted, at: 0)
			document.scrollbackAllowance += accepted.count
			updateLayoutAfterEdit()
			return accepted.map(\.lineNumber)
		}
	}

	/** Adds lines recovered from the server between the lines they fall
	 between, by the time each carries.

	 A message the document already draws is not drawn again, whether it is
	 named by its line or by its message identifier. Lines older than
	 everything drawn are left out and reported, for the controller to load
	 with the rest of the older history.

	 The batch keeps the reader where they are: one following the end is
	 scrolled to it, and one reading back keeps the line at the top of the
	 viewport in place while the lines go in above or below it. */
	@discardableResult
	func insertRecoveredLines(_ newLines: [TranscriptRow]) -> (accepted: [String], heldBack: [String]) {
		performEditingBatch {
			let candidates = document.accepting(newLines).filter { line in
				line.messageIdentifier.map { document.ordinals(ofMessage: $0) == nil } ?? true
			}
			let placement = TranscriptRecoveredPlacement(
				drawn: document.lines.map(\.receivedAt),
				recovered: candidates.map(\.receivedAt),
				room: document.roomBeforeCeiling
			)
			/* From the end, so an insertion does not move the index the next
			 one names. */
			for run in placement.runs.reversed() {
				insert(run.members.map { candidates[$0] }, at: run.index)
			}
			updateLayoutAfterEdit()
			return (
				placement.runs.flatMap(\.members).map { candidates[$0].lineNumber },
				placement.heldBack.map { candidates[$0].lineNumber }
			)
		}
	}

	func clearLines() {
		performEditingBatch { clear() }
	}

	private func clear() {
		closeMemberInformation()
		closeReactionPicker()
		document.removeAll()
		beginNicknameColorBatch()
		textView.textStorage?.setAttributedString(NSAttributedString())
		inlineImageLoader.cancelLoads(forView: viewIdentifier)
		updateLayoutAfterEdit()
	}

	func updateDelivery(_ update: TranscriptDeliveryUpdate) {
		performEditingBatch {
			guard let index = document.updateDelivery(update) else { return }
			if update.replacement != nil {
				inlineImageLoader.cancelLoads(forView: viewIdentifier, lineNumber: update.lineNumber)
			}
			refresh(at: index)
		}
	}

	func redactMessage(withIdentifier messageIdentifier: String, placeholder: String) {
		performEditingBatch {
			for index in document.redactMessage(messageIdentifier: messageIdentifier, placeholder: placeholder) {
				inlineImageLoader.cancelLoads(forView: viewIdentifier, lineNumber: document[index].lineNumber)
				refresh(at: index)
			}
		}
	}

	func updateReactions(_ reactions: [String: [String]], messageIdentifier: String) {
		performEditingBatch {
			for index in document.mergeReactions(reactions, messageIdentifier: messageIdentifier) {
				refresh(at: index)
			}
		}
	}

	func setUnreadMarker(_ mark: UnreadMarker) {
		performEditingBatch {
			let caption = String(localized: .Transcript.unreadMessages)
			let changed = document.setUnreadMarker(mark, caption: caption)
			refreshFolding()
			for index in changed {
				refresh(at: index)
			}
		}
	}

	/// A download outlives the line that asked for it, so an image whose line
	/// has already scrolled out of the buffer is dropped rather than kept.
	@discardableResult
	func addInlineImage(_ image: TranscriptInlineImage) -> Bool {
		performEditingBatch { insertInlineImage(image) }
	}

	private func insertInlineImage(_ image: TranscriptInlineImage) -> Bool {
		guard let decoded = NSImage(data: image.imageData), decoded.size.width > 0, decoded.size.height > 0
		else { return false }
		let attachment = NSTextAttachment()
		attachment.image = decoded
		let cached = CachedTranscriptImage(
			linkIdentifier: image.linkIdentifier,
			sourceURL: image.sourceURL,
			image: decoded,
			originalSize: decoded.size,
			attachment: attachment
		)
		guard let index = document.addInlineImage(cached, to: image.lineNumber) else { return false }
		refresh(at: index)
		return true
	}

	/// Drops the oldest lines that no longer fit. Only the oldest: the end of
	/// the transcript is what the controller, the jump commands and the reader
	/// all address. The batch's `endEditing` calls it once, after the batch's
	/// edits and before the selection and the viewport are put back.
	func trimOverflow() {
		let overflow = document.overflow(followsBottom: followsBottom)
		guard overflow > 0, let storage = textView.textStorage else { return }
		storage.beginEditing()
		defer { storage.endEditing() }
		remove(0 ..< overflow)
	}

	func range(ofLine lineNumber: String) -> NSRange? {
		document.range(ofLine: lineNumber)
	}

	/** Renders `newLines` and splices them into the document at `index`.

	 Which of them begins a day depends on the line each one lands under, so
	 the date markers are settled here rather than taken from the rows: the
	 new lines are marked against the line above the run, and the line below
	 the run against the last of them. That line is the only old one whose
	 marker can change, and it is redrawn when it does. */
	private func insert(_ rows: [TranscriptRow], at index: Int) {
		guard let storage = textView.textStorage, rows.isEmpty == false else { return }
		let signposter = PerformanceSignposts.signposter
		let interval = signposter.beginInterval("TranscriptInsert")
		defer { signposter.endInterval("TranscriptInsert", interval) }
		let dayMarkers = dayMarkers
		let newLines = TranscriptDayMarkers.marking(
			rows, after: index > 0 ? document[index - 1].receivedAt : nil, using: dayMarkers
		)
		var followingLine: String?
		if index < document.count, let last = newLines.last,
		   document.setDateMarker(dayMarkers?.caption(for: document[index].receivedAt, after: last.receivedAt), at: index)
		{
			followingLine = document[index].lineNumber
		}
		var changed = foldInsertedLines(newLines, at: index, regroups: followingLine != nil)
		beginNicknameColorBatch()
		let origin = document.location(ofLineAt: index)
		var starts: [Int] = []
		starts.reserveCapacity(newLines.count)
		var location = origin
		storage.beginEditing()
		defer { storage.endEditing() }
		for start in stride(from: 0, to: newLines.count, by: 32) {
			let rendered = NSMutableAttributedString()
			for line in newLines[start ..< min(start + 32, newLines.count)] {
				starts.append(location + rendered.length)
				rendered.append(renderVisibleLine(line))
			}
			storage.replaceCharacters(in: NSRange(location: location, length: 0), with: rendered)
			location += rendered.length
		}
		document.insert(newLines, at: index, starts: starts, totalLength: location - origin)
		changed.subtract(newLines.map(\.lineNumber))
		if let followingLine {
			changed.insert(followingLine)
		}
		redrawFoldedLines(changed)
	}

	/// Removes the oldest `indices` lines and the characters they drew. Only the
	/// oldest: that is the one end lines ever leave from.
	private func remove(_ indices: Range<Int>) {
		guard let storage = textView.textStorage, indices.isEmpty == false else { return }
		/* The profile popover is anchored to characters; a line appended under
		 the name leaves them where they are, but a trim or a clear moves or
		 removes them, and a popover pointing at whatever took their place is
		 worse than none. The reaction picker is anchored the same way, and the
		 message it answers can be one of the rows leaving here. */
		closeMemberInformation()
		closeReactionPicker()
		let removedRows = Array(document.lines[indices])
		let retirement = document.remove(indices)
		storage.deleteCharacters(in: retirement.characterRange)
		redrawFoldedLines(document.folding.retire(rows: removedRows, firstRetainedRow: document.lines.first))
		if retirement.messageIdentifiers.isEmpty == false {
			viewController?.transcriptDidRetireMessages(retirement.messageIdentifiers)
		}
		/* The reader's highlight cursor names a line that was on screen, so the
		 rows leaving the document here are the only ones that can retire it. */
		if retirement.lineNumbers.isEmpty == false {
			viewController?.notifyLinesWereRemoved(retirement.lineNumbers)
		}
		for identifier in retirement.lineNumbers {
			inlineImageLoader.cancelLoads(forView: viewIdentifier, lineNumber: identifier)
		}
		if retirement.carriedMarkers.isEmpty == false {
			refresh(at: 0)
		}
	}

	/// Redraws one line in place. A delivery receipt, a reaction, an unread
	/// boundary or a decoded image changes that line and nothing else.
	func refresh(at index: Int) {
		guard let storage = textView.textStorage, document.indices.contains(index) else { return }
		beginNicknameColorBatch()
		let rendered = renderVisibleLine(document[index])
		storage.replaceCharacters(
			in: NSRange(location: document.location(ofLineAt: index), length: document.length(ofLineAt: index)),
			with: rendered
		)
		document.noteLineRedrawn(at: index, newLength: rendered.length)
		updateLayoutAfterEdit()
	}

	/** Rewrites the whole document.

	 Only a change that alters how every line draws needs one: the theme and the
	 text scale. Ordinary traffic edits the storage in place, which is what keeps
	 a busy conversation from re-rendering its whole scrollback per message.

	 A caller runs it inside ``performEditingBatch(_:)``, which puts the
	 selection and the viewport back once the batch ends. */
	func rebuild() {
		beginNicknameColorBatch()
		let retainedLines = document.takeLinesForRebuild()
		textView.textStorage?.beginEditing()
		textView.textStorage?.setAttributedString(NSAttributedString())
		insert(retainedLines, at: 0)
		textView.textStorage?.endEditing()
		updateLayoutAfterEdit()
	}
}
