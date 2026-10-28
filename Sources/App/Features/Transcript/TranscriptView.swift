// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import SwiftUI

/** The transcript one conversation or server console owns: the text view, the scroll
 view and the topic bar, plus the editing, selection and scrolling that keep
 them in step.

 The controller and the main window speak to this type, and nothing outside
 this feature holds anything smaller. One type, split by the job each part
 does: this file owns the view's state, its construction and the transcript
 API the feature calls; `TranscriptView+Document` owns the lines and every edit to
 them, `TranscriptView+Selection` the selection and the editing batches,
 `TranscriptView+Scrolling` where the reader is looking, `TranscriptTopicBar` the topic
 bar, `TranscriptView+Pointer` what a point in the text names, `TranscriptView+Printing`
 paper, and `TranscriptView+Rendering` turning a row into attributed text. */
@MainActor
final class TranscriptView: NSView, NSTextViewDelegate, NSTextLayoutManagerDelegate {
	weak var viewController: TranscriptController?
	var contextMenuTarget = TranscriptContextTarget()
	var selection: String?

	let inlineImageLoader: InlineImageLoader
	let viewIdentifier: String
	let commands: TranscriptCommands
	/// The profile popover a click on a nickname opened, while it is open.
	var memberInformationPopover: NSPopover?
	/// The reaction picker, while it is open, anchored to the message it
	/// answers.
	var reactionPicker: ReactionPopover?

	let topicBar = TranscriptTopicBar()
	let scrollView = NSScrollView()
	/* SwiftUI owns controls; this adapter only hosts them. */
	let jumpToLatest = NSHostingView(rootView: TranscriptJumpToLatestButton(action: {}))
	var jumpToLatestBottomConstraint: NSLayoutConstraint?
	let textView: TranscriptTextView
	var scrollViewTopWithTopicConstraint: NSLayoutConstraint?
	var scrollViewTopWithoutTopicConstraint: NSLayoutConstraint?
	let notifications = NotificationSubscriptions()
	/// The lines, the indexes over them and the trim. A value: the storage edits
	/// are this view's, and everything that decides which line an edit reaches
	/// is the document's.
	var document = TranscriptDocument()
	var editDepth = 0
	var batchSelection: SelectionAnchor?
	var batchViewport: (endpoint: SelectionAnchor.Endpoint, offset: CGFloat)?
	var textScale: CGFloat = 1
	/** Whether the reader is following the end of the transcript. Scrolling,
	 find and jump commands set it; appends, document growth and a return
	 to the window all scroll to the end while it holds.

	 Returning to the end is also what lets the scrollback go: the older lines
	 are off screen from then on, and the next trim brings the buffer back to
	 the limit the reader chose. */
	var followsBottom = true {
		didSet {
			if followsBottom, oldValue == false {
				document.scrollbackAllowance = 0
			}
			updateJumpToLatestVisibility()
		}
	}

	var scrollsToBottomOnLayout = false
	/// The clip view's last observed top, so a bounds change can say whether
	/// the reader moved towards the start of the transcript.
	var lastVisibleTop: CGFloat = 0
	/// Resolved nickname colours for the batch being rendered. Each lookup costs
	/// a read of the defaults store, and one batch asks for the same handful of
	/// names over and over.
	var nicknameColors: [String: NSColor] = [:]
	/// The pinned colours the batch resolves against, read on the first miss and
	/// kept for the rest of the batch so a name the cache has not seen does not
	/// build another handle on the defaults suite.
	var nicknameColorOverrides: NicknameColorOverrides?
	/// Set while the view re-selects text it moved itself, so the delegate does
	/// not mistake bookkeeping for something the reader did.
	var isAdjustingSelection = false
	/// Guards the scroll a growing document triggers: `scrollToBottom()` resizes
	/// the document itself, and that resize must not come back through here.
	var isFollowingDocumentGrowth = false
	/// While a printed copy is being laid out, every theme role resolves to its
	/// light half: paper is white, and a dark transcript prints as ink.
	private(set) var rendersForPrint = false

	init(viewController: TranscriptController) {
		self.viewController = viewController
		commands = TranscriptCommands(sink: viewController.commandSink)
		inlineImageLoader = viewController.inlineImageLoader
		viewIdentifier = viewController.uniqueIdentifier
		textView = TranscriptTextView(usingTextLayoutManager: true)
		super.init(frame: .zero)
		configure()
		/* No theme observers here. The main window owns the fan-out: it answers
		 the theme notifications once and calls `reloadTheme()` on every
		 controller, and a transcript that also listened re-rendered twice. */
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// MARK: - The feature-facing transcript

	var hasSelection: Bool {
		selection?.isEmpty == false
	}

	func takeContextMenuTarget() -> TranscriptContextTarget {
		defer { contextMenuTarget = TranscriptContextTarget() }
		return contextMenuTarget
	}

	func clearSelection() {
		textView.setSelectedRange(NSRange(location: 0, length: 0))
	}

	func focusText() {
		window?.makeFirstResponder(textView)
	}

	func copySelection() {
		textView.copy(nil)
	}

	var displayedLines: [TranscriptRow] {
		document.lines
	}

	/// Whether the document already draws the line `identifier` names, under
	/// either of the identifiers a restored row answers to.
	func containsLine(identifier: String) -> Bool {
		document.contains(identifier: identifier)
	}

	var displayedBounds: TranscriptDisplayedBounds {
		TranscriptDisplayedBounds(
			oldest: document.lines.first?.lineNumber, newest: document.lines.last?.lineNumber,
			count: document.count,
			remainingCapacity: max(0, document.roomBeforeCeiling)
		)
	}

	/// Whether any line on screen is a highlight, which is what the Next and
	/// Previous Highlight commands are validated against. A count the document
	/// keeps as it is edited, rather than a walk of the whole buffer per menu
	/// update.
	var hasHighlightedLines: Bool {
		document.highlightedLineCount > 0
	}

	/** Sends what the reader typed to the input field, and nothing else.

	 Focusing the transcript is how someone reads back through it, so the keys
	 that move a document have to reach the text view: redirecting every
	 unmodified key sent Page Up and the arrows to the input field, which took
	 the focus back and left the transcript unable to scroll at all. */
	func keyDown(_ event: NSEvent, in _: NSView) -> Bool {
		let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		if modifiers.isEmpty, [" ", "\r", "\n"].contains(event.charactersIgnoringModifiers ?? ""),
		   activateSelectedFold()
		{
			return true
		}
		guard modifiers.isDisjoint(with: [.command, .option, .control]),
		      Self.isTextInput(event.charactersIgnoringModifiers)
		else { return false }
		viewController?.transcriptViewKeyDown(event)
		return true
	}

	/** Whether a key stroke is text meant for the input field rather than a
	 command to the transcript.

	 AppKit spells the arrows, the paging keys, Home, End and the function keys
	 as code points in the Unicode private use area, and the space bar is the
	 page-down every document view has; all of them stay with the text view. */
	nonisolated static func isTextInput(_ characters: String?) -> Bool { // nonisolated: pure
		guard let scalar = characters?.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F, scalar != " " else { return false }
		return (0xF700 ... 0xF8FF).contains(scalar.value) == false
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		guard let fileURL = NSURL(from: sender.draggingPasteboard) as URL?, fileURL.isFileURL else {
			return false
		}
		viewController?.transcriptViewReceivedDrop(withFile: fileURL.path)
		return true
	}

	func prepareContextTarget(at point: NSPoint) {
		contextMenuTarget = contextTarget(at: point)
	}

	func contextMenu(defaultItems: [NSMenuItem]) -> NSMenu {
		commands.contextMenu(for: self, defaultMenuItems: defaultItems)
	}

	func performEditingBatch<Output>(_ edits: () -> Output) -> Output {
		closeMemberInformation()
		beginEditing()
		defer { endEditing() }
		return edits()
	}

	func beginNicknameColorBatch() {
		nicknameColors.removeAll(keepingCapacity: true)
		nicknameColorOverrides = nil
	}

	func setBufferLimit(_ limit: Int) {
		performEditingBatch {
			document.bufferLimit = max(1, limit)
			let anchor = selectionAnchor()
			trimToBufferLimit()
			restoreSelection(anchor)
		}
	}

	func setTextScale(_ scale: CGFloat) {
		performEditingBatch {
			textScale = max(0.5, min(scale, 3))
			/* The topic is drawn by a label rather than by the document, so the
			 rebuild below does not reach it. */
			topicBar.setTextScale(textScale)
			showTopicBarIfDrawn()
			needsLayout = true
			rebuild()
		}
	}

	/// Renders `body` with every theme role resolved to its light half, which is
	/// what paper is. The flag is the renderer's only input for it.
	func renderingForPrint<Output>(_ body: () -> Output) -> Output {
		rendersForPrint = true
		defer { rendersForPrint = false }
		return body()
	}

	func applyTheme() {
		performEditingBatch {
			applyThemeNow()
		}
	}

	private func applyThemeNow() {
		let controller = AppServices.theme
		layer?.backgroundColor = controller.backgroundColor.cgColor
		textView.insertionPointColor = controller.resolved(controller.theme.palette.primaryText)
		refreshTopicBar()
		rebuild()
	}

	func textView(_ textView: NSTextView, clickedOnLink link: Any, at index: Int) -> Bool {
		if let storage = textView.textStorage, index >= 0, index < storage.length,
		   let lineNumber = storage.attribute(.transcriptFoldLineNumber, at: index, effectiveRange: nil) as? String
		{
			toggleFoldedGroup(lineNumber)
			return true
		}
		guard let url = link as? URL else { return false }
		commands.openWebpage(url)
		return true
	}
}
