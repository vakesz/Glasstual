// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

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
			let anchor = selectionAnchor()
			insert(accepted, at: document.count)
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
			let room = document.roomBeforeCeiling
			guard room > 0 else { return [] }
			/* The tail of the fetched block is the part adjacent to what is on
			 screen, so a block that does not fit keeps its newest lines. */
			let accepted = Array(document.accepting(newLines).suffix(room))
			let anchor = selectionAnchor()
			preservingVisibleText {
				insert(accepted, at: 0)
				document.scrollbackAllowance += accepted.count
				updateLayoutAfterEdit()
			}
			restoreSelection(anchor)
			return accepted.map(\.lineNumber)
		}
	}

	/// The index of the line `identifier` names, under either identifier a
	/// restored row answers to.
	func index(ofLine identifier: String) -> Int? {
		document.index(ofLine: identifier)
	}

	func clearLines() {
		performEditingBatch { clear() }
	}

	private func clear() {
		closeMemberInformation()
		document.removeAll()
		beginNicknameColorBatch()
		textView.textStorage?.setAttributedString(NSAttributedString())
		inlineImageLoader.cancelLoads(forView: viewIdentifier)
		updateLayoutAfterEdit()
	}

	func updateDelivery(_ update: TranscriptDeliveryUpdate) {
		performEditingBatch {
			guard let index = document.updateDelivery(update) else { return }
			refresh(at: index)
		}
	}

	func updateReactions(_ reactions: [String: [String]], messageIdentifier: String) {
		performEditingBatch {
			for index in document.mergeReactions(reactions, messageIdentifier: messageIdentifier) {
				refresh(at: index)
			}
		}
	}

	func setUnreadMarker(_ mark: TranscriptScrollbackMark) {
		performEditingBatch {
			let caption = String(localized: .MainWindow.unreadMessages)
			for index in document.setUnreadMarker(mark, caption: caption) {
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
	/// all address.
	func trimToBufferLimit(force: Bool = false) {
		guard editDepth == 0 || force else { return }
		let overflow = document.overflow(followsBottom: followsBottom)
		guard overflow > 0 else { return }
		preservingVisibleText {
			remove(0 ..< overflow)
		}
	}

	func range(ofLine lineNumber: String) -> NSRange? {
		document.range(ofLine: lineNumber)
	}

	/// Renders `newLines` and splices them into the document at `index`.
	private func insert(_ newLines: [TranscriptRow], at index: Int) {
		guard let storage = textView.textStorage, newLines.isEmpty == false else { return }
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
				rendered.append(render(line))
			}
			storage.replaceCharacters(in: NSRange(location: location, length: 0), with: rendered)
			location += rendered.length
		}
		document.insert(newLines, at: index, starts: starts, totalLength: location - origin)
	}

	/// Removes the oldest `indices` lines and the characters they drew. Only the
	/// oldest: that is the one end lines ever leave from.
	private func remove(_ indices: Range<Int>) {
		guard let storage = textView.textStorage, indices.isEmpty == false else { return }
		/* The profile popover is anchored to characters; a line appended under
		 the name leaves them where they are, but a trim or a clear moves or
		 removes them, and a popover pointing at whatever took their place is
		 worse than none. */
		closeMemberInformation()
		let retirement = document.remove(indices)
		storage.deleteCharacters(in: retirement.characterRange)
		if retirement.messageIdentifiers.isEmpty == false {
			viewController?.transcriptDidRetireMessages(retirement.messageIdentifiers)
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
	private func refresh(at index: Int) {
		guard let storage = textView.textStorage, document.indices.contains(index) else { return }
		beginNicknameColorBatch()
		let anchor = selectionAnchor()
		let rendered = render(document[index])
		storage.replaceCharacters(
			in: NSRange(location: document.location(ofLineAt: index), length: document.length(ofLineAt: index)),
			with: rendered
		)
		document.noteLineRedrawn(at: index, newLength: rendered.length)
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
		let retainedLines = document.takeLinesForRebuild()
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
