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
import CocoaExtensions
import Foundation
import SwiftUI

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
final class LogViewTextView: NSTextView {
	weak var owner: LogView?
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
		/* Once the laid-out text is taller than the viewport the offset is zero
		 and stays zero, so only a transcript that still looks short is worth
		 laying out in full: the alternative is a whole-document layout pass for
		 every line the view receives. */
		var contentHeight = layoutManager.usageBoundsForTextContainer.height
		if contentHeight < availableHeight {
			layoutManager.ensureLayout(for: layoutManager.documentRange)
			contentHeight = layoutManager.usageBoundsForTextContainer.height
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
		super.keyDown(with: event)
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		owner?.performDragOperation(sender) ?? false
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		owner?.prepareContextTarget(at: convert(event.locationInWindow, from: nil))
		return owner?.contextMenu(defaultItems: super.menu(for: event)?.items ?? [])
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

/** The transcript one channel or server view owns: the text view, the scroll
 view and the topic bar, plus the editing, selection and scrolling that keep
 them in step.

 The controller and the main window speak to this type, and nothing outside
 this feature holds anything smaller. One type, split by the job each part
 does: this file owns the view's state, its construction and the transcript
 API the feature calls; `LogView+Document` owns the lines and every edit to
 them, `LogView+Selection` the selection and the editing batches,
 `LogView+Scrolling` where the reader is looking, `LogView+Topic` the topic
 bar, `LogView+Pointer` what a point in the text names, `LogView+Printing`
 paper, and `LogViewRendering` turning a row into attributed text. */
@MainActor
public final class LogView: NSView, NSTextViewDelegate, NSTextLayoutManagerDelegate {
	public weak var viewController: LogController?
	public var contextMenuTarget = LogPolicyTarget()
	public var selection: String?

	let inlineImageLoader: NativeInlineImageLoader
	let viewIdentifier: String
	let policy = LogPolicy()
	/// The profile popover a click on a nickname opened, while it is open.
	var memberInformationPopover: NSPopover?

	let topicField = TopicLabel(wrappingLabelWithString: "")
	/* SwiftUI owns controls; this adapter only hosts one. */
	let topicDisclosure = NSHostingView(rootView: TopicDisclosureButton(isExpanded: false, action: {}))
	var isTopicExpanded = false
	let scrollView = NSScrollView()
	/* SwiftUI owns controls; this adapter only hosts them. */
	let jumpToLatest = NSHostingView(rootView: TranscriptJumpToLatestButton(action: {}))
	var jumpToLatestBottomConstraint: NSLayoutConstraint?
	let textView: LogViewTextView
	var scrollViewTopWithTopicConstraint: NSLayoutConstraint?
	var scrollViewTopWithoutTopicConstraint: NSLayoutConstraint?
	private let notifications = NotificationSubscriptions()
	var lines: [TranscriptLine] = []
	/** Where each line begins in the text storage, in the order ``lines`` holds
	 them, with the end of the document at the end.

	 It is what lets an edit reach one line's characters without rewriting the
	 document around them, and it is stored rather than summed per lookup:
	 restoring the selection after a single append asks for two of these, and
	 summing the lengths before a line made each answer a walk of the buffer.
	 The invariant is `lineStarts.count == lines.count + 1`. */
	var lineStarts: [Int] = [0]
	/// How many lines on screen are highlights. Counted as the document is
	/// edited because the menu asks on every validation pass, and the answer
	/// used to be a walk of the whole scrollback.
	var highlightedLineCount = 0
	/** Where each identifier the document answers to sits, so an edit, a jump
	 or a duplicate check reaches its line without walking the buffer.

	 A row restored from storage answers to two: the history row it came back
	 from and the line number it was printed with. Both are held, which is what
	 keeps a message the reader has already seen from being drawn again beside
	 its restored self.

	 The values are ordinals rather than indices. Lines only ever arrive at
	 either end and leave from the top, so an ordinal is fixed for as long as
	 its line is held; `firstLineOrdinal` is the ordinal of `lines[0]`, and an
	 index is the difference. Nothing is renumbered when older lines are put in
	 front or the oldest are trimmed. */
	var lineOrdinals: [String: Int] = [:]
	/// The ordinals of the lines that carry each message identifier, oldest
	/// first, for the reactions addressed to a message.
	var messageLineOrdinals: [String: [Int]] = [:]
	var firstLineOrdinal = 0
	var inlineImages: [String: [CachedTranscriptImage]] = [:]
	var editDepth = 0
	var batchSelection: SelectionAnchor?
	var batchViewport: (endpoint: SelectionAnchor.Endpoint, offset: CGFloat)?
	var bufferLimit = LogViewBufferPolicy.defaultHardLimit
	/** Older lines pulled in while the reader follows the end, which raise the
	 buffer's ceiling so the trim after the prepend does not take them straight
	 back out. Scrollback the reader loads by scrolling back needs none: nothing
	 is trimmed from the top while they read. */
	var scrollbackAllowance = 0
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
				scrollbackAllowance = 0
			}
			updateJumpToLatestVisibility()
		}
	}

	var scrollsToBottomOnLayout = false
	/// The clip view's last observed top, so a bounds change can say whether
	/// the reader moved towards the start of the transcript.
	var lastVisibleTop: CGFloat = 0
	var topicLineHeightCache: (font: NSFont, height: CGFloat)?
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
	/** The topic as the wire carries it, control codes and all.

	 The label holds the rendered text, so it is not something the topic can be
	 drawn from a second time: re-rendering from the label dropped every colour
	 and bold the topic carried the moment the theme or the text size moved. */
	var topicText = ""
	/// Guards the scroll a growing document triggers: `scrollToBottom()` resizes
	/// the document itself, and that resize must not come back through here.
	var isFollowingDocumentGrowth = false
	/// While a printed copy is being laid out, every theme role resolves to its
	/// light half: paper is white, and a dark transcript prints as ink.
	private(set) var rendersForPrint = false

	public init(viewController: LogController) {
		self.viewController = viewController
		inlineImageLoader = viewController.inlineImageLoader
		viewIdentifier = viewController.uniqueIdentifier
		textView = LogViewTextView(usingTextLayoutManager: true)
		super.init(frame: .zero)
		configure()
		/* No theme observers here. The main window owns the fan-out: it answers
		 the theme notifications once and calls `reloadTheme()` on every
		 controller, and a transcript that also listened re-rendered twice. */
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// MARK: - The feature-facing transcript

	public var hasSelection: Bool {
		selection?.isEmpty == false
	}

	public func takeContextMenuTarget() -> LogPolicyTarget {
		defer { contextMenuTarget = LogPolicyTarget() }
		return contextMenuTarget
	}

	public func clearSelection() {
		textView.setSelectedRange(NSRange(location: 0, length: 0))
	}

	public func copySelection() {
		textView.copy(nil)
	}

	var displayedLines: [TranscriptLine] {
		lines
	}

	/// Whether the document already draws the line `identifier` names, under
	/// either of the identifiers a restored row answers to.
	func containsLine(identifier: String) -> Bool {
		lineOrdinals[identifier] != nil
	}

	var displayedBounds: TranscriptDisplayedBounds {
		TranscriptDisplayedBounds(
			oldest: lines.first?.lineNumber, newest: lines.last?.lineNumber,
			count: lines.count,
			remainingCapacity: max(0, LogViewBufferPolicy.validLimits.upperBound - lines.count)
		)
	}

	/// Whether any line on screen is a highlight, which is what the Next and
	/// Previous Highlight commands are validated against. A count the document
	/// keeps as it is edited, rather than a walk of the whole buffer per menu
	/// update.
	var hasHighlightedLines: Bool {
		highlightedLineCount > 0
	}

	/** Sends what the reader typed to the input field, and nothing else.

	 Focusing the transcript is how someone reads back through it, so the keys
	 that move a document have to reach the text view: redirecting every
	 unmodified key sent Page Up and the arrows to the input field, which took
	 the focus back and left the transcript unable to scroll at all. */
	public func keyDown(_ event: NSEvent, in _: NSView) -> Bool {
		let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		guard modifiers.isDisjoint(with: [.command, .option, .control]),
		      Self.isTextInput(event.charactersIgnoringModifiers)
		else { return false }
		viewController?.logViewKeyDown(event)
		return true
	}

	/** Whether a key stroke is text meant for the input field rather than a
	 command to the transcript.

	 AppKit spells the arrows, the paging keys, Home, End and the function keys
	 as code points in the Unicode private use area, and the space bar is the
	 page-down every document view has; all of them stay with the text view. */
	nonisolated static func isTextInput(_ characters: String?) -> Bool { // nonisolated: pure
		guard let scalar = characters?.unicodeScalars.first else { return false }
		guard scalar.value >= 0x20, scalar.value != 0x7F, scalar != " " else { return false }
		return (0xF700 ... 0xF8FF).contains(scalar.value) == false
	}

	override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		guard let fileURL = NSURL(from: sender.draggingPasteboard) as URL?, fileURL.isFileURL else {
			return false
		}
		viewController?.logViewReceivedDrop(withFile: fileURL.path)
		return true
	}

	func prepareContextTarget(at point: NSPoint) {
		contextMenuTarget = contextTarget(at: point)
	}

	func contextMenu(defaultItems: [NSMenuItem]) -> NSMenu {
		policy.contextMenu(for: self, defaultMenuItems: defaultItems)
	}

	/** Shows the profile of a nickname the reader clicked in the transcript,
	 anchored to the text that named them. Only someone in the conversation has
	 a profile to show: a name that has since left is left alone. */
	func showMemberInformation(for nickname: String, relativeTo rect: NSRect, of view: NSView) {
		closeMemberInformation()
		guard let member = viewController?.associatedChannel?.findMember(nickname) else { return }
		let content = MemberListUserInfoContent(
			member: member,
			privileges: MemberListPresentation.privilegesDescription(for: member)
		)
		let popover = NSPopover()
		popover.behavior = .transient
		popover.delegate = self
		popover.contentViewController = NSHostingController(rootView: MemberListUserInfoView(content: content))
		memberInformationPopover = popover
		/* The text view is flipped, so `.maxY` is the edge below the name. */
		popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
	}

	func closeMemberInformation() {
		memberInformationPopover?.close()
		memberInformationPopover = nil
	}

	/** Runs one batch of transcript edits.

	 Every mutation goes through here, which is also why the profile popover is
	 dismissed here: appending, trimming, restyling, a reaction, a decoded image
	 or the unread marker can all move or remove the text the popover is
	 anchored to, and an anchor that moves leaves the popover pointing at
	 someone else's message. */
	func performEditingBatch<Output>(_ edits: () -> Output) -> Output {
		closeMemberInformation()
		beginEditing()
		defer { endEditing() }
		return edits()
	}

	private func configure() {
		textView.owner = self
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		configureTopicBar()
		configureTextView()
		configureScrollView()
		configureJumpToLatestButton()
		addSubviewsAndActivateConstraints()
		setTopic(nil)
		applyTheme()
	}

	private func configureTopicBar() {
		topicField.isSelectable = true
		topicField.allowsEditingTextAttributes = true
		topicField.lineBreakMode = .byTruncatingTail
		topicField.translatesAutoresizingMaskIntoConstraints = false
		topicField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		let topicClick = NSClickGestureRecognizer(target: self, action: #selector(topicDoubleClicked(_:)))
		topicClick.numberOfClicksRequired = 2
		topicField.addGestureRecognizer(topicClick)
		topicField.menu = topicMenu()

		/* The topic stays on one line and the chevron unfolds it. A click on the
		 text itself cannot do that: the field is selectable so its links open
		 and its words copy, and a single click there has to keep meaning that. */
		topicDisclosure.sizingOptions = .intrinsicContentSize
		topicDisclosure.translatesAutoresizingMaskIntoConstraints = false
		topicDisclosure.setContentHuggingPriority(.required, for: .horizontal)
		topicDisclosure.setContentCompressionResistancePriority(.required, for: .horizontal)
		applyTopicExpansion()
	}

	private func configureTextView() {
		textView.delegate = self
		/* The separators are layout fragments of their own; see
		 `TranscriptRuleLayoutFragment`. */
		textView.textLayoutManager?.delegate = self
		textView.isEditable = false
		textView.isSelectable = true
		textView.setAccessibilityIdentifier("channel-transcript")
		updateAccessibilityDescription()
		textView.isRichText = true
		textView.importsGraphics = false
		/* The find bar is the transcript's own, inline above the text, which is
		 where macOS puts search in a document window. */
		textView.usesFindBar = true
		textView.isIncrementalSearchingEnabled = true
		textView.isAutomaticLinkDetectionEnabled = false
		textView.isAutomaticDataDetectionEnabled = false
		textView.drawsBackground = false
		textView.textContainerInset = NSSize(width: 0, height: TranscriptMetrics.documentInset)
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.autoresizingMask = [.width]
		textView.minSize = .zero
		textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		textView.textContainer?.widthTracksTextView = true
		textView.textContainer?.heightTracksTextView = false
		textView.registerForDraggedTypes([.fileURL])
		let contentClick = NSClickGestureRecognizer(target: self, action: #selector(contentDoubleClicked(_:)))
		contentClick.numberOfClicksRequired = 2
		textView.addGestureRecognizer(contentClick)
		textView.onClick = { [weak self] click in
			self?.textViewClicked(click)
		}
	}

	private func configureScrollView() {
		scrollView.documentView = textView
		/* The insets are this view's, from the first layout on. The window
		 carries a transparent titlebar over a full-size content view, which is
		 exactly what AppKit's automatic adjustment reaches for -- and the
		 transcript is laid out inside the safe area, so an adjustment for the
		 titlebar is space nothing covers. Turning it off at construction rather
		 than at the first `setBottomContentInset(_:)` is what keeps the view
		 from ever running with both. */
		scrollView.automaticallyAdjustsContentInsets = false
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.contentView.postsBoundsChangedNotifications = true
		scrollView.contentView.postsFrameChangedNotifications = true
		/* TextKit settles the document's real height when the view first lays
		 out for display, and every append grows it. A reader at the end follows
		 that growth; one who scrolled up is left where they are. */
		textView.onHeightChange = { [weak self] in
			self?.documentHeightDidChange()
		}
		notifications.observe(NSView.frameDidChangeNotification, object: scrollView.contentView) { [weak self] _ in
			guard let self else { return }
			/* A reader at the end stays at the end when the viewport changes
			 shape: a window resize, the input bar growing, the view landing in
			 a window for the first time. */
			if scrollsToBottomOnLayout {
				scrollToBottomIfPending()
			} else if followsBottom, window != nil {
				scrollToBottom()
			}
		}
		notifications.observe(NSView.boundsDidChangeNotification, object: scrollView.contentView) { [weak self] _ in
			guard let self else { return }
			/* Only a reader moving towards the top asks for more history. The
			 clip's bounds also change for a scroll this view performed, for the
			 document growing underneath, and for a transcript too short to
			 scroll, which sits at zero forever and would otherwise fetch on
			 every notification it receives. */
			let top = scrollView.contentView.bounds.minY
			let movedUp = top < lastVisibleTop
			lastVisibleTop = top
			guard movedUp, top < TranscriptMetrics.historyFetchTrigger else { return }
			viewController?.loadOlderHistory()
		}
		/* The reader's own scrolling updates whether they follow the end.
		 The live-scroll notifications are posted for wheel, trackpad and
		 scroller input and for nothing else, so a scroll this view performs
		 itself, or the document growing underneath, cannot flip the flag. */
		for name in [NSScrollView.didLiveScrollNotification, NSScrollView.didEndLiveScrollNotification] {
			notifications.observe(name, object: scrollView) { [weak self] _ in
				guard let self, window != nil else { return }
				followsBottom = isNearBottom
			}
		}
	}

	private func configureJumpToLatestButton() {
		/* A reader who has scrolled away has no way back to the end but the
		 menu, and the transcript is where they are looking. */
		jumpToLatest.sizingOptions = .intrinsicContentSize
		jumpToLatest.translatesAutoresizingMaskIntoConstraints = false
		jumpToLatest.isHidden = true
		jumpToLatest.rootView = TranscriptJumpToLatestButton { [weak self] in
			self?.scrollToBottom()
		}
	}

	private func addSubviewsAndActivateConstraints() {
		addSubview(topicField)
		addSubview(topicDisclosure)
		addSubview(scrollView)
		addSubview(jumpToLatest)
		/* No rule under the topic: the change of colour and the gap are the
		 edge, and a hairline there read as a second toolbar. */
		scrollViewTopWithTopicConstraint = scrollView.topAnchor.constraint(
			equalTo: topicField.bottomAnchor,
			constant: TranscriptMetrics.topicGap
		)
		scrollViewTopWithoutTopicConstraint = scrollView.topAnchor.constraint(equalTo: topAnchor)
		NSLayoutConstraint.activate([
			topicField.topAnchor.constraint(equalTo: topAnchor, constant: TranscriptMetrics.topicGap),
			topicField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TranscriptMetrics.topicSideInset),
			topicField.trailingAnchor.constraint(
				equalTo: topicDisclosure.leadingAnchor,
				constant: -TranscriptMetrics.topicGap
			),
			topicDisclosure.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -TranscriptMetrics.topicSideInset
			),
			topicDisclosure.firstBaselineAnchor.constraint(equalTo: topicField.firstBaselineAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
			jumpToLatest.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UISpacing.loose),
		])
		jumpToLatestBottomConstraint = jumpToLatest.bottomAnchor.constraint(
			equalTo: bottomAnchor,
			constant: -UISpacing.wide
		)
		jumpToLatestBottomConstraint?.isActive = true
	}

	override public func layout() {
		super.layout()
		guard window != nil, !isHiddenOrHasHiddenAncestor, editDepth == 0 else { return }
		updateTopicWrappingWidth()
		updateTopicDisclosure()
		textView.updateBottomAlignment()
		if scrollsToBottomOnLayout {
			/* The scroll view tiles in its own pass, after this one; forcing it
			 here gives the clip its height now, so the scroll lands in the same
			 layout instead of a notification later. */
			scrollView.layoutSubtreeIfNeeded()
			scrollToBottomIfPending()
		}
	}

	/// Starts a batch of renders: the colours resolved for the last one, and the
	/// pinned-colour table they were resolved against, both belong to it alone.
	func beginNicknameColorBatch() {
		nicknameColors.removeAll(keepingCapacity: true)
		nicknameColorOverrides = nil
	}

	func setBufferLimit(_ limit: Int) {
		performEditingBatch {
			bufferLimit = max(1, limit)
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
			refreshTopicBar()
			topicField.invalidateIntrinsicContentSize()
			topicLineHeightCache = nil
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
		let controller = SharedApplication.sharedThemeController()
		layer?.backgroundColor = controller.backgroundColor.cgColor
		textView.insertionPointColor = controller.resolved(controller.theme.palette.primaryText)
		refreshTopicBar()
		rebuild()
	}

	public func textView(_: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
		guard let url = link as? URL else { return false }
		policy.openWebpage(url)
		return true
	}
}

public extension LogView {
	/** Hands a marker paragraph the fragment that draws its rule. Pure: the
	 answer comes from the paragraph's own attributes, and nothing of the
	 view is read. */
	nonisolated func textLayoutManager( // nonisolated: pure
		_: NSTextLayoutManager,
		textLayoutFragmentFor _: any NSTextLocation,
		in textElement: NSTextElement
	) -> NSTextLayoutFragment {
		guard let paragraph = textElement as? NSTextParagraph,
		      paragraph.attributedString.length > 0,
		      let color = paragraph.attributedString.attribute(.transcriptRuleColor, at: 0, effectiveRange: nil)
		      as? NSColor
		else {
			return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
		}
		let inset = (paragraph.attributedString.attribute(.transcriptRuleInset, at: 0, effectiveRange: nil)
			as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
		return TranscriptRuleLayoutFragment(
			textElement: textElement,
			range: textElement.elementRange,
			ruleColor: color,
			ruleInset: inset
		)
	}
}

extension LogView: NSMenuItemValidation {
	public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(changeTopicMenuItemClicked(_:)): canModifyTopic
		case #selector(copyTopicMenuItemClicked(_:)): topicField.isHidden == false
		default: true
		}
	}
}

extension LogView: NSPopoverDelegate {
	public func popoverDidClose(_ notification: Notification) {
		if notification.object as? NSPopover === memberInformationPopover {
			memberInformationPopover = nil
		}
	}
}

/** Takes the reader back to the newest line. It is the same command the View
 menu carries, offered where the reader is actually looking. */
struct TranscriptJumpToLatestButton: View {
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Image(systemName: "arrow.down.to.line")
				.font(.system(size: 12, weight: .semibold))
				.frame(width: UIListMetrics.rowHeight, height: UIListMetrics.rowHeight)
				.contentShape(Circle())
		}
		.buttonStyle(.plain)
		.background(.thinMaterial, in: Circle())
		.overlay(Circle().strokeBorder(.separator))
		.accessibilityLabel(MenuStrings.Navigation.jumpToPresent)
		.help(MenuStrings.Navigation.jumpToPresent)
	}
}
