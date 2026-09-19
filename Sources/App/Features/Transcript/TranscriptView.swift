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
	private var reactionPicker: ReactionPopover?

	let topicBar = TranscriptTopicBar()
	let scrollView = NSScrollView()
	/* SwiftUI owns controls; this adapter only hosts them. */
	let jumpToLatest = NSHostingView(rootView: TranscriptJumpToLatestButton(action: {}))
	var jumpToLatestBottomConstraint: NSLayoutConstraint?
	let textView: TranscriptTextView
	var scrollViewTopWithTopicConstraint: NSLayoutConstraint?
	var scrollViewTopWithoutTopicConstraint: NSLayoutConstraint?
	private let notifications = NotificationSubscriptions()
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
		guard let scalar = characters?.unicodeScalars.first else { return false }
		guard scalar.value >= 0x20, scalar.value != 0x7F, scalar != " " else { return false }
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

	// MARK: - The topic bar

	/// Takes the topic the conversation is on now.
	func setTopic(_ topic: String?) {
		topicBar.setTopic(topic, modes: channelModeCaption)
		showTopicBarIfDrawn()
	}

	/// Redraws the bar from the topic it holds: the modes, the theme or the
	/// reader's text size moved.
	func refreshTopicBar() {
		topicBar.refresh(modes: channelModeCaption)
		showTopicBarIfDrawn()
	}

	/// A bar with neither a topic nor modes to draw gives its room back to the
	/// transcript, which is the only thing outside the bar its content decides.
	private func showTopicBarIfDrawn() {
		let hidden = topicBar.isEmpty
		topicBar.isHidden = hidden
		let outgoing = hidden ? scrollViewTopWithTopicConstraint : scrollViewTopWithoutTopicConstraint
		let incoming = hidden ? scrollViewTopWithoutTopicConstraint : scrollViewTopWithTopicConstraint
		outgoing?.isActive = false
		incoming?.isActive = true
		needsLayout = true
	}

	/// The channel's modes as the caption spells them, with any key masked, or
	/// nothing where the view is not a channel or has no modes yet.
	private var channelModeCaption: String? {
		guard let modes = viewController?.associatedConversation?.modeInfo?.stringWithMaskedPassword,
		      modes.isEmpty == false
		else { return nil }
		return modes
	}

	/// Whether the channel lets this reader set the topic: either it is not
	/// restricted to operators, or they are one.
	var canModifyTopic: Bool {
		guard let channel = viewController?.associatedConversation, channel.isChannel else { return false }
		guard channel.modeInfo?.modes.modeInfo(for: ChannelMode.operatorTopic.rawValue)?.modeIsSet == true
		else { return true }
		guard let nickname = viewController?.associatedSession?.userNickname,
		      let member = channel.findMember(nickname)
		else { return false }
		return member.isOp || member.isHalfOp
	}

	/// Names the transcript for an assistive reader. Without it the text view
	/// is announced as an unlabelled document, in a window full of them.
	func updateAccessibilityDescription() {
		let name = viewController?.associatedConversation?.name
			?? viewController?.associatedSession?.networkNameAlt ?? ""
		textView.setAccessibilityLabel(String(localized: .Transcript.transcriptAccessibility(name)))
		textView.setAccessibilityRoleDescription(String(localized: .Transcript.transcriptRole))
	}

	/** Shows the profile of a nickname the reader clicked in the transcript,
	 anchored to the text that named them. Only someone in the conversation has
	 a profile to show: a name that has since left is left alone. */
	func showMemberInformation(for nickname: String, relativeTo rect: NSRect, of view: NSView) {
		closeMemberInformation()
		guard let member = viewController?.associatedConversation?.findMember(nickname) else { return }
		let popover = NSPopover()
		popover.behavior = .transient
		popover.delegate = self
		popover.contentViewController = MemberListUserInfoPopover.makeViewController(for: member)
		memberInformationPopover = popover
		/* The text view is flipped, so `.maxY` is the edge below the name. */
		popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
	}

	func closeMemberInformation() {
		memberInformationPopover?.close()
		memberInformationPopover = nil
	}

	/** Offers the reactions for a message, anchored to the characters the
	 message drew.

	 The window raises the command, because it is a menu command with a
	 conversation to send the reaction to; where the picker opens is the
	 transcript's answer, because only it knows where the message is. A message
	 whose rows are no longer laid out has no anchor, so the pointer is the
	 fallback -- the reader is looking at it either way. */
	func presentReactionPicker(forMessage identifier: String, onPick: @escaping (String) -> Void) {
		closeReactionPicker()
		let picker = ReactionPopover()
		picker.onPick = onPick
		picker.onClose = { [weak self] in self?.reactionPicker = nil }
		reactionPicker = picker
		picker.present(relativeTo: anchorRect(forMessage: identifier), of: textView)
	}

	func closeReactionPicker() {
		reactionPicker?.close()
		reactionPicker = nil
	}

	/// Where a message is drawn, in the text view's coordinates, falling back to
	/// the pointer for a message the layout has not reached.
	private func anchorRect(forMessage identifier: String) -> NSRect {
		guard let window, let range = document.range(ofMessage: identifier), range.length > 0 else {
			return pointerRect()
		}
		/* The last character of the message: the picker opens under the end of
		 what it answers rather than under the first of several lines. */
		let tail = NSRange(location: NSMaxRange(range) - 1, length: 1)
		let screenRect = textView.firstRect(forCharacterRange: tail, actualRange: nil)
		guard screenRect.isEmpty == false else { return pointerRect() }
		return textView.convert(window.convertFromScreen(screenRect), from: nil)
	}

	private func pointerRect() -> NSRect {
		guard let window else { return .zero }
		let point = textView.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
		return NSRect(origin: point, size: .zero).insetBy(dx: -1, dy: -1)
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
		topicBar.canModifyTopic = { [weak self] in self?.canModifyTopic == true }
		topicBar.onModifyTopic = { [weak self] in self?.commands.topicBarDoubleClicked() }
		topicBar.onOpenLink = { [weak self] in self?.commands.openWebpage($0) }
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
		addSubview(topicBar)
		addSubview(scrollView)
		addSubview(jumpToLatest)
		/* No rule under the topic: the change of colour and the gap are the
		 edge, and a hairline there read as a second toolbar. */
		scrollViewTopWithTopicConstraint = scrollView.topAnchor.constraint(
			equalTo: topicBar.bottomAnchor,
			constant: TranscriptMetrics.topicGap
		)
		scrollViewTopWithoutTopicConstraint = scrollView.topAnchor.constraint(equalTo: topAnchor)
		NSLayoutConstraint.activate([
			topicBar.topAnchor.constraint(equalTo: topAnchor),
			topicBar.leadingAnchor.constraint(equalTo: leadingAnchor),
			topicBar.trailingAnchor.constraint(equalTo: trailingAnchor),
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

	override func layout() {
		super.layout()
		guard window != nil, !isHiddenOrHasHiddenAncestor, editDepth == 0 else { return }
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

	func textView(_: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
		guard let url = link as? URL else { return false }
		commands.openWebpage(url)
		return true
	}
}

extension TranscriptView {
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

extension TranscriptView: NSPopoverDelegate {
	func popoverDidClose(_ notification: Notification) {
		if notification.object as? NSPopover === memberInformationPopover {
			memberInformationPopover = nil
		}
	}
}
