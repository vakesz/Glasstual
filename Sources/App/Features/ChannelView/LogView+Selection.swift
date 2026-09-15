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

/** Selection and the editing batches that have to survive it. A character
 offset means nothing across an edit, so a selection and the viewport are both
 anchored to the line and segment they name and resolved again afterwards. */
extension LogView {
	public func textViewDidChangeSelection(_: Notification) {
		guard isAdjustingSelection == false else { return }
		let range = textView.selectedRange()
		selection = range.length > 0 ? (textView.string as NSString).substring(with: range) : nil
		/* Stepping through find results selects each match in turn; that is the
		 find bar moving the reader, not the reader selecting text, so it must
		 not overwrite the pasteboard. */
		guard scrollView.isFindBarVisible == false else { return }
		if Preferences.Messages.copyOnSelect.value, hasSelection {
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
		guard selection.length > 0, lineStarts.count == lines.count + 1 else { return nil }
		guard let start = selectionEndpoint(at: selection.location),
		      let end = selectionEndpoint(at: NSMaxRange(selection), isEnd: true) else { return nil }
		return SelectionAnchor(start: start, end: end)
	}

	private func selectionEndpoint(at position: Int, isEnd: Bool = false) -> SelectionAnchor.Endpoint? {
		guard let index = lineIndex(containing: position, isEnd: isEnd) else { return nil }
		let location = lineStarts[index]
		let next = lineStarts[index + 1]
		var segmentRange = NSRange()
		let segment = textView.textStorage?.attribute(
			.transcriptSelectionSegment, at: max(location, position - (isEnd ? 1 : 0)),
			longestEffectiveRange: &segmentRange,
			in: NSRange(location: location, length: next - location)
		) as? String
		return SelectionAnchor.Endpoint(
			lineNumber: lines[index].lineNumber,
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
		var upper = lines.count
		while lower < upper {
			let middle = lower + (upper - lower) / 2
			let end = lineStarts[middle + 1]
			if position < end || isEnd && position == end {
				upper = middle
			} else {
				lower = middle + 1
			}
		}
		return lower < lines.count ? lower : nil
	}

	func restoreSelection(_ anchor: SelectionAnchor?) {
		guard editDepth == 0, let anchor else { return }
		/* Both endpoints have to survive the edit. Standing an unresolved one at
		 zero stretches the selection to the top of the document, and
		 copy-on-select would then put text the reader never selected on the
		 pasteboard; a selection whose text is gone is simply gone. */
		guard let start = position(anchor.start), let end = position(anchor.end) else { return }
		let restored = NSRange(location: min(start, end), length: max(0, end - start))
		isAdjustingSelection = true
		textView.setSelectedRange(restored)
		isAdjustingSelection = false
		selection = restored.length > 0
			? (textView.string as NSString).substring(with: restored)
			: nil
	}

	private func position(_ endpoint: SelectionAnchor.Endpoint) -> Int? {
		guard let range = range(ofLine: endpoint.lineNumber), let storage = textView.textStorage else { return nil }
		var resolved = range.location + min(endpoint.offset, range.length)
		if let segment = endpoint.segment {
			storage.enumerateAttribute(.transcriptSelectionSegment, in: range) { value, segmentRange, stop in
				guard value as? String == segment else { return }
				resolved = segmentRange.location + min(endpoint.offset, segmentRange.length)
				stop.pointee = true
			}
		}
		return resolved
	}

	func viewportAnchor() -> (endpoint: SelectionAnchor.Endpoint, offset: CGFloat)? {
		guard !followsBottom, editDepth == 0, window != nil, !isHiddenOrHasHiddenAncestor,
		      lineStarts.count == lines.count + 1 else { return nil }
		let top = scrollView.contentView.bounds.minY
		let index = textView.characterIndexForInsertion(at: NSPoint(x: textView.textContainerOrigin.x, y: top))
		guard let endpoint = selectionEndpoint(at: index),
		      let verticalPosition = verticalPosition(at: index) else { return nil }
		return (endpoint, verticalPosition - top)
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
		 transcript they had scrolled away from. */
		guard window != nil, !isHiddenOrHasHiddenAncestor,
		      let index = position(anchor.endpoint),
		      let verticalPosition = verticalPosition(at: index) else { return }
		var origin = scrollView.contentView.bounds.origin
		origin.y = max(0, verticalPosition - anchor.offset)
		scrollView.contentView.scroll(to: origin)
		scrollView.reflectScrolledClipView(scrollView.contentView)
		noteViewportMovedByView()
	}

	func beginEditing() {
		if editDepth == 0 {
			batchSelection = selectionAnchor()
			batchViewport = viewportAnchor()
			textView.textStorage?.beginEditing()
			isAdjustingSelection = true
		}
		editDepth += 1
	}

	func endEditing() {
		precondition(editDepth > 0)
		if editDepth > 1 {
			editDepth -= 1
			return
		}
		trimToBufferLimit(force: true)
		textView.textStorage?.endEditing()
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
