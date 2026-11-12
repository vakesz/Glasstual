// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/** A completed mouse click on the transcript, as the adapter needs to judge it:
 the text view has already placed the caret, followed a link and settled the
 selection by the time one of these is handed over. */
struct TranscriptClick {
	let point: NSPoint
	let clickCount: Int
	let modifiers: NSEvent.ModifierFlags
	/// Whether the pointer moved between press and release, which is what a
	/// selection drag over a name looks like.
	let dragged: Bool
}

@MainActor
final class TranscriptTextView: NSTextView {
	weak var owner: TranscriptView?
	private var bottomAlignmentOffset: CGFloat = 0

	/// Told synchronously when the document's height changes, so a transcript
	/// that follows its end can stay there in the same pass that grew it.
	var onHeightChange: (@MainActor () -> Void)?

	/** Told about a click once the text view has had it. A gesture recognizer
	 cannot stand in for this: one that claims the primary button delays every
	 mouse-down and swallows the events it recognizes, so the caret stops
	 moving, the selection stops clearing and links stop opening. */
	var onClick: (@MainActor (TranscriptClick) -> Void)?

	/// Where the click that is currently down began, in view coordinates.
	private var clickOrigin: NSPoint?

	override func mouseDown(with event: NSEvent) {
		clickOrigin = convert(event.locationInWindow, from: nil)
		super.mouseDown(with: event)
		/* `NSTextView` tracks the drag selection in an event loop of its own and
		 usually consumes the mouse up that ends it, so the click finishes here;
		 `mouseUp(with:)` covers the case where it is delivered normally, and
		 whichever runs first clears the origin. */
		let ending = NSApp.currentEvent
		finishClick(endedBy: ending?.type == .leftMouseUp ? ending : nil, startedBy: event)
	}

	override func mouseUp(with event: NSEvent) {
		super.mouseUp(with: event)
		finishClick(endedBy: event, startedBy: event)
	}

	private func finishClick(endedBy ending: NSEvent?, startedBy start: NSEvent) {
		guard let origin = clickOrigin else { return }
		clickOrigin = nil
		/* Either way it is a left mouse event, which is what makes `clickCount`
		 meaningful. */
		let release = ending ?? start
		let point = convert(release.locationInWindow, from: nil)
		onClick?(TranscriptClick(
			point: origin,
			clickCount: release.clickCount,
			modifiers: release.modifierFlags.intersection(.deviceIndependentFlagsMask),
			dragged: abs(point.x - origin.x) > 2 || abs(point.y - origin.y) > 2
		))
	}

	override func setFrameSize(_ newSize: NSSize) {
		let previousHeight = frame.height
		super.setFrameSize(newSize)
		if frame.height != previousHeight {
			onHeightChange?()
		}
	}

	override var textContainerOrigin: NSPoint {
		var origin = super.textContainerOrigin
		origin.y += bottomAlignmentOffset
		return origin
	}

	/// Keeps a short conversation beside the input bar. Once the laid-out text
	/// is taller than the viewport, TextKit returns to its normal top origin and
	/// the scroll view behaves like an ordinary transcript.
	func updateBottomAlignment() {
		guard let layoutManager = textLayoutManager,
		      let clipView = enclosingScrollView?.contentView
		else {
			bottomAlignmentOffset = 0
			return
		}

		let previousOffset = bottomAlignmentOffset
		bottomAlignmentOffset = 0
		let origin = super.textContainerOrigin
		let insets = enclosingScrollView?.contentInsets ?? NSEdgeInsets()
		let availableHeight = clipView.bounds.height - insets.top - insets.bottom
		/* Once the text is taller than the viewport the offset is zero, so the
		 question is only whether the text fills the viewport. The usage bounds
		 cover what TextKit has laid out, which in a long transcript can be a
		 short stretch near the viewport; laying out the whole document to be
		 sure cost a pass over every line for every batch the view received.
		 Layout from the top stops as soon as the text is tall enough. */
		var contentHeight = layoutManager.usageBoundsForTextContainer.height
		if contentHeight < availableHeight {
			contentHeight = 0
			layoutManager.enumerateTextLayoutFragments(
				from: layoutManager.documentRange.location,
				options: [.ensuresLayout]
			) { fragment in
				contentHeight = max(contentHeight, fragment.layoutFragmentFrame.maxY)
				return contentHeight < availableHeight
			}
		}
		let offset = max(0, availableHeight - contentHeight - origin.y - textContainerInset.height)
		bottomAlignmentOffset = offset
		guard abs(offset - previousOffset) > 0.5 else { return }
		needsDisplay = true
	}

	override func keyDown(with event: NSEvent) {
		if owner?.keyDown(event, in: self) == true {
			return
		}
		let previousOrigin = enclosingScrollView?.contentView.bounds.origin
		super.keyDown(with: event)
		if enclosingScrollView?.contentView.bounds.origin != previousOrigin {
			/* Keyboard navigation does not post live-scroll notifications. Once
			 the reader pages away, incoming messages must leave that page in place. */
			owner?.scrollsToBottomOnLayout = false
			owner?.followsBottom = owner?.isNearBottom == true
		}
	}

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		owner?.draggingEntered(sender) ?? []
	}

	override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
		owner?.draggingUpdated(sender) ?? []
	}

	override func draggingExited(_ sender: NSDraggingInfo?) {
		owner?.draggingExited(sender)
	}

	override func draggingEnded(_ sender: NSDraggingInfo) {
		owner?.draggingEnded(sender)
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		owner?.performDragOperation(sender) ?? false
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		owner?.prepareContextTarget(at: convert(event.locationInWindow, from: nil))
		return owner?.contextMenu(defaultItems: super.menu(for: event)?.items ?? [])
	}

	/// AppKit routes both keyboard context menus and VoiceOver Show Menu here.
	/// Keep NSTextView's native text accessibility and anchor actions to its selection.
	override func showContextMenuForSelection(_: Any?) {
		guard owner != nil, let window else { return }
		let menu = selectionContextMenu()
		let screenRect = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
		let anchor = convert(window.convertFromScreen(screenRect), from: nil)
		menu?.popUp(positioning: nil, at: NSPoint(x: anchor.minX, y: anchor.maxY), in: self)
	}

	// MARK: - Focus ring

	/** The system focus ring, drawn around the image placeholder the caret is
	 on and nowhere else: the transcript is a document, not a control, and its
	 scroll view is not ringed, but a placeholder is a button the keyboard can
	 press. The text view's `focusRingType` is `.exterior` for this. */
	override var focusRingMaskBounds: NSRect {
		owner?.focusedInlineImagePlaceholderRect() ?? .zero
	}

	override func drawFocusRingMask() {
		guard let rect = owner?.focusedInlineImagePlaceholderRect() else { return }
		rect.fill()
	}

	/// The native text actions, plus joining the channel or opening the nickname
	/// the selection sits on: the runs are not links, so a screen reader that
	/// moves the cursor through the text has no other way to activate them.
	override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
		let native = super.accessibilityCustomActions() ?? []
		guard let owner else { return native.isEmpty ? nil : native }
		let actions = native + owner.nameAccessibilityActions()
		return actions.isEmpty ? nil : actions
	}

	/// The native text and its links, plus a button for each image placeholder
	/// on screen, which the text alone would read as a picture.
	override func accessibilityChildren() -> [Any]? {
		let native = super.accessibilityChildren() ?? []
		let placeholders = owner?.inlineImagePlaceholderAccessibilityElements() ?? []
		let children = native + placeholders
		return children.isEmpty ? nil : children
	}

	func selectionContextMenu() -> NSMenu? {
		guard let owner else { return nil }
		owner.contextMenuTarget = owner.selectedContextTarget()
		let event = NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
			windowNumber: window?.windowNumber ?? 0, context: nil,
			characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 0
		)
		let defaults = event.flatMap { super.menu(for: $0)?.items } ?? []
		return owner.contextMenu(defaultItems: defaults)
	}

	/** Writes the selection as text a person can paste somewhere.

	 The plain-text flavour `NSTextView` writes is the storage's characters, and
	 the transcript's characters include attachments -- a delivery receipt, an
	 inline image -- which copy as U+FFFC, plus the characters it draws for its
	 own layout. Each attachment is replaced by the words the renderer attached
	 for an assistive reader, which is what it says out loud, and the layout's
	 own characters are left out. Only those: a thin space somebody typed is
	 part of what they wrote. */
	override func writeSelection(to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
		guard type == .string else {
			return super.writeSelection(to: pasteboard, type: type)
		}
		pasteboard.setString(copyableText(in: selectedRange()), forType: .string)
		return true
	}

	private func copyableText(in range: NSRange) -> String {
		guard let storage = textStorage else { return "" }
		let text = NSMutableString()
		storage.enumerateAttributes(in: range, options: []) { attributes, runRange, _ in
			guard attributes[.transcriptPadding] == nil else { return }
			guard attributes[.attachment] != nil else {
				text.append(storage.attributedSubstring(from: runRange).string)
				return
			}
			let spoken = (attributes[.accessibilityCustomText] as? [String])?.joined(separator: " ") ?? ""
			text.append(spoken)
		}
		return text as String
	}
}
