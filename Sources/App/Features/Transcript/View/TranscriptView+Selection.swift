// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/** Selection and the editing batches that have to survive it. A character
 offset means nothing across an edit, so a selection and the viewport are both
 anchored to the line and segment they name and resolved again afterwards. */
extension TranscriptView {
	func textViewDidChangeSelection(_: Notification) {
		guard isAdjustingSelection == false else { return }
		let range = textView.selectedRange()
		/* `textView.string` is the whole transcript; the storage reads only the
		 selected characters. */
		selection = range.length > 0 ? textView.textStorage?.attributedSubstring(from: range).string : nil
		/* The caret moving onto or off an image placeholder moves the focus
		 ring the text view draws around it. */
		textView.noteFocusRingMaskChanged()
		/* Stepping through find results selects each match in turn; that is the
		 find bar moving the reader, not the reader selecting text, so it must
		 not overwrite the pasteboard. */
		guard scrollView.isFindBarVisible == false else { return }
		if SettingsKeys.Messages.copyOnSelect.value, hasSelection {
			copySelection()
		}
	}

	/** The selection expressed against its two semantic endpoints.

	 A character offset into the document is only meaningful until the document
	 changes: trimming the oldest lines or inserting older ones shifts every
	 offset after them, and a selection restored by number then covers text the
	 reader never selected — which `copyOnSelect` would put on the pasteboard. */
	func selectionAnchor() -> SelectionAnchor? {
		guard editDepth == 0 else { return nil }
		let selection = textView.selectedRange()
		guard selection.length > 0, let start = selectionEndpoint(at: selection.location),
		      let end = selectionEndpoint(at: NSMaxRange(selection), isEnd: true) else { return nil }
		return SelectionAnchor(start: start, end: end)
	}

	private func selectionEndpoint(at position: Int, isEnd: Bool = false) -> SelectionAnchor.Endpoint? {
		guard let index = lineIndex(containing: position, isEnd: isEnd) else { return nil }
		let location = document.location(ofLineAt: index)
		let next = location + document.length(ofLineAt: index)
		var segmentRange = NSRange()
		let segment = textView.textStorage?.attribute(
			.transcriptSelectionSegment, at: max(location, position - (isEnd ? 1 : 0)),
			longestEffectiveRange: &segmentRange,
			in: NSRange(location: location, length: next - location)
		) as? String
		return SelectionAnchor.Endpoint(
			lineNumber: document[index].lineNumber,
			segment: segment,
			offset: position - (segment == nil ? location : segmentRange.location)
		)
	}

	/** The line a character position falls in, found by bisecting the line
	 starts rather than walking every line before it.

	 The first line whose end lies past `position`; an end endpoint also belongs
	 to a line it sits exactly at the end of, so a selection that stops at a
	 line break names that line rather than the next. */
	func lineIndex(containing position: Int, isEnd: Bool = false) -> Int? {
		var lower = 0
		var upper = document.count
		while lower < upper {
			let middle = lower + (upper - lower) / 2
			let end = document.location(ofLineAt: middle + 1)
			if position < end || isEnd && position == end {
				upper = middle
			} else {
				lower = middle + 1
			}
		}
		return lower < document.count ? lower : nil
	}

	func restoreSelection(_ anchor: SelectionAnchor?) {
		guard editDepth == 0, let anchor else { return }
		/* Both endpoints have to survive the edit. Standing an unresolved one at
		 zero stretches the selection to the top of the document, and
		 copy-on-select would then put text the reader never selected on the
		 pasteboard; a selection whose text is gone is simply gone. */
		guard let start = position(anchor.start), let end = position(anchor.end) else {
			isAdjustingSelection = true
			textView.setSelectedRange(NSRange(location: 0, length: 0))
			isAdjustingSelection = false
			selection = nil
			return
		}
		let restored = NSRange(location: min(start, end), length: max(0, end - start))
		isAdjustingSelection = true
		textView.setSelectedRange(restored)
		isAdjustingSelection = false
		/* `textView.string` is the whole transcript; the storage reads only the
		 selected characters. */
		selection = restored.length > 0
			? textView.textStorage?.attributedSubstring(from: restored).string
			: nil
	}

	private func position(_ endpoint: SelectionAnchor.Endpoint) -> Int? {
		guard let range = range(ofLine: endpoint.lineNumber), let storage = textView.textStorage else { return nil }
		guard let segment = endpoint.segment else {
			return range.location + min(endpoint.offset, range.length)
		}
		var resolved: Int?
		storage.enumerateAttribute(.transcriptSelectionSegment, in: range) { value, segmentRange, stop in
			guard value as? String == segment else { return }
			resolved = segmentRange.location + min(endpoint.offset, segmentRange.length)
			stop.pointee = true
		}
		return resolved
	}

	func viewportAnchor() -> (endpoint: SelectionAnchor.Endpoint, offset: CGFloat)? {
		guard !followsBottom, editDepth == 0, window != nil, !isHiddenOrHasHiddenAncestor else { return nil }
		let top = scrollView.contentView.bounds.minY
		/* A reader at the very top has the container's inset at the top of the
		 viewport, and a point above the first line names the end of the
		 document, not its start. The first line is what they are looking at. */
		let probe = NSPoint(x: textView.textContainerOrigin.x, y: max(top, textView.textContainerOrigin.y))
		let index = indexBelowDateMarker(at: textView.characterIndexForInsertion(at: probe))
		guard let endpoint = selectionEndpoint(at: index),
		      let verticalPosition = verticalPosition(at: index) else { return nil }
		return (endpoint, verticalPosition - top)
	}

	/** Where the line's own text begins, if `index` is in its date marker.

	 The marker belongs to whichever line is first of its day, and moves off
	 this one when an older line of the same day goes in above. The line's
	 text stays, so that is what a viewport is anchored to. A row that draws
	 nothing but its markers keeps the index it was given. */
	private func indexBelowDateMarker(at index: Int) -> Int {
		guard let storage = textView.textStorage, index < storage.length,
		      let line = lineIndex(containing: index) else { return index }
		let lineRange = NSRange(location: document.location(ofLineAt: line), length: document.length(ofLineAt: line))
		var marker = NSRange()
		let segment = storage.attribute(
			.transcriptSelectionSegment, at: index, longestEffectiveRange: &marker, in: lineRange
		) as? String
		guard segment == TranscriptMarker.date("").selectionSegment, NSMaxRange(marker) < NSMaxRange(lineRange)
		else { return index }
		return NSMaxRange(marker)
	}

	/// The top of the line holding `index`, in the text view's coordinates.
	private func verticalPosition(at index: Int) -> CGFloat? {
		guard let layoutManager = textView.textLayoutManager,
		      let contentManager = layoutManager.textContentManager,
		      let location = contentManager.location(contentManager.documentRange.location, offsetBy: index)
		else { return nil }
		let range = NSTextRange(location: location)
		layoutManager.ensureLayout(for: range)
		var top: CGFloat?
		layoutManager.enumerateTextSegments(
			in: range,
			type: .standard,
			options: [.rangeNotRequired]
		) { _, frame, _, _ in
			top = frame.minY
			return false
		}
		guard let top else { return nil }
		return top + textView.textContainerOrigin.y
	}

	func restoreViewport(_ anchor: (endpoint: SelectionAnchor.Endpoint, offset: CGFloat)) {
		/* The line the viewport was anchored to may not have survived the edit.
		 Keeping the reader where they are beats jumping them to the top of a
		 transcript they had scrolled away from.

		 A date marker is the exception: it moves to another line when a line
		 of the same day goes in above its own, and the line it stood on is
		 still where the reader was. */
		guard window != nil, !isHiddenOrHasHiddenAncestor,
		      let index = position(anchor.endpoint) ?? range(ofLine: anchor.endpoint.lineNumber)?.location
		else { return }
		/* Until the viewport is laid out again, TextKit 2 answers with where
		 the line was before the edit: text that went in above it has not
		 moved it yet. Scrolling to that place leaves the viewport where it
		 was, and the line slides out from under the reader on the next
		 layout.

		 One pass is not always enough. The lines between the old viewport and
		 the line are measured by estimate until they are laid out, so when
		 more than a viewport of text went in above, the scroll lands near the
		 line and laying that place out moves it again. Each pass lays out
		 where the last one scrolled to, and the measurements settle. */
		for _ in 0 ..< 4 {
			textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
			guard let verticalPosition = verticalPosition(at: index) else { return }
			var origin = scrollView.contentView.bounds.origin
			let target = max(0, verticalPosition - anchor.offset)
			guard abs(target - origin.y) >= 0.5 else { break }
			origin.y = target
			scrollView.contentView.scroll(to: origin)
		}
		scrollView.reflectScrolledClipView(scrollView.contentView)
		noteViewportMovedByView()
	}

	/// Opens a batch. The outermost one records the selection and, for a reader
	/// who is not following the bottom, the viewport, as semantic anchors.
	func beginEditing() {
		if editDepth == 0 {
			batchSelection = selectionAnchor()
			batchViewport = viewportAnchor()
			textView.textStorage?.beginEditing()
			isAdjustingSelection = true
		}
		editDepth += 1
	}

	/** Closes the outermost batch. Everything the batch's edits left to settle is
	 settled here, once: the overflow is trimmed, then the selection and the
	 viewport taken at `beginEditing` are put back against the new text, and a
	 reader who follows the bottom is scrolled to it. The edits inside a batch
	 therefore leave all of that alone.

	 The trim is its own storage edit, after the batch's. TextKit processes one
	 edit as the span from its first changed character to its last, so a trim
	 at the top in the same edit as lines appended at the bottom made every
	 batch fix attributes over, and invalidate the layout of, the whole
	 document. */
	func endEditing() {
		precondition(editDepth > 0)
		if editDepth > 1 {
			editDepth -= 1
			return
		}
		textView.textStorage?.endEditing()
		trimOverflow()
		editDepth = 0
		isAdjustingSelection = false
		restoreSelection(batchSelection)
		batchSelection = nil
		updateLayoutAfterEdit()
		if let batchViewport {
			restoreViewport(batchViewport)
		}
		batchViewport = nil
		if followsBottom {
			scrollToBottom()
		}
	}

	func updateLayoutAfterEdit() {
		updateJumpToLatestVisibility()
		guard editDepth == 0, window != nil, !isHiddenOrHasHiddenAncestor else {
			needsLayout = true
			return
		}
		textView.updateBottomAlignment()
	}
}
