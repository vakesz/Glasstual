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

/** The AppKit adapter behind a transcript: the text view, the scroll view and
 the topic bar, plus the editing, selection and scrolling that keep them in
 step. ``LogView`` is the feature-facing handle on it, and rendering a row into
 attributed text lives in `NativeTranscriptViewRendering.swift`. */
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
final class NativeTranscriptTextView: NSTextView {
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

	convenience init(owner: LogView) {
		self.init(usingTextLayoutManager: true)
		self.owner = owner
	}

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
}

@MainActor
final class NativeTranscriptView: NSView, NSTextViewDelegate, NSTextLayoutManagerDelegate {
	weak var owner: LogView?

	let topicField = TopicLabel(wrappingLabelWithString: "")
	/* SwiftUI owns controls; this adapter only hosts one. */
	let topicDisclosure = NSHostingView(rootView: TopicDisclosureButton(isExpanded: false, action: {}))
	var isTopicExpanded = false
	/// The profile a single click on a nickname asked for, while it waits out
	/// the double-click interval.
	private var pendingNicknameClick: Task<Void, Never>?
	/// Whether such a click is still waiting. The edits that have to call it off
	/// are what this reports on.
	var hasPendingNicknameClick: Bool {
		pendingNicknameClick != nil
	}

	private let scrollView = OverlayScrollView()
	let textView: NativeTranscriptTextView
	private var scrollViewTopWithTopicConstraint: NSLayoutConstraint?
	private var scrollViewTopWithoutTopicConstraint: NSLayoutConstraint?
	private let notifications = NotificationSubscriptions()
	var lines: [TranscriptLine] = []
	/** How many characters each line occupies in the text storage, in the order
	 ``lines`` holds them. It is what lets an edit reach one line's characters:
	 a line's location is the sum of the lengths before it, so appending,
	 trimming and restyling a single line all touch the document in place
	 instead of rewriting it. */
	private var lineLengths: [Int] = []
	/// The identifiers ``lines`` holds, so an edit can reject a line the
	/// document already shows without walking it.
	private var lineNumbers: Set<String> = []
	var inlineImages: [String: [CachedTranscriptImage]] = [:]
	private var editDepth = 0
	private var batchSelection: SelectionAnchor?
	private var batchViewport: (endpoint: SelectionAnchor.Endpoint, offset: CGFloat)?
	private var bufferLimit = LogViewBufferPolicy.defaultHardLimit
	/** Older lines the reader pulled in by scrolling back. They raise the
	 buffer's ceiling rather than pushing the newest lines out of it, so loading
	 scrollback can never make the end of the conversation disappear. */
	private var scrollbackAllowance = 0
	var textScale: CGFloat = 1
	/** Whether the reader is following the end of the transcript. Scrolling,
	 find and jump commands set it; appends, document growth and a return
	 to the window all scroll to the end while it holds. */
	private var followsBottom = true
	private var scrollsToBottomOnLayout = false
	/// The clip view's last observed top, so a bounds change can say whether
	/// the reader moved towards the start of the transcript.
	private var lastVisibleTop: CGFloat = 0
	private var topicLineHeightCache: (font: NSFont, height: CGFloat)?
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
	private var isAdjustingSelection = false

	init(owner: LogView) {
		self.owner = owner
		textView = NativeTranscriptTextView(owner: owner)
		super.init(frame: .zero)
		configure()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	/// The pending click only holds this view weakly, so it would wake to find
	/// nothing; cancelling ends the sleep now rather than leaving a task
	/// running for a view that is gone.
	isolated deinit {
		pendingNicknameClick?.cancel()
	}

	private func configure() {
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true

		topicField.isSelectable = true
		topicField.allowsEditingTextAttributes = true
		topicField.lineBreakMode = .byTruncatingTail
		topicField.translatesAutoresizingMaskIntoConstraints = false
		topicField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		let topicClick = NSClickGestureRecognizer(target: self, action: #selector(topicDoubleClicked(_:)))
		topicClick.numberOfClicksRequired = 2
		topicField.addGestureRecognizer(topicClick)

		/* The topic stays on one line and the chevron unfolds it. A click on the
		 text itself cannot do that: the field is selectable so its links open
		 and its words copy, and a single click there has to keep meaning that. */
		topicDisclosure.sizingOptions = .intrinsicContentSize
		topicDisclosure.translatesAutoresizingMaskIntoConstraints = false
		topicDisclosure.setContentHuggingPriority(.required, for: .horizontal)
		topicDisclosure.setContentCompressionResistancePriority(.required, for: .horizontal)
		applyTopicExpansion()

		textView.delegate = self
		/* The separators are layout fragments of their own; see
		 `TranscriptRuleLayoutFragment`. */
		textView.textLayoutManager?.delegate = self
		textView.isEditable = false
		textView.isSelectable = true
		textView.setAccessibilityIdentifier("channel-transcript")
		textView.isRichText = true
		textView.importsGraphics = false
		/* The find bar is the transcript's own, inline above the text, which is
		 where macOS puts search in a document window. */
		textView.usesFindBar = true
		textView.isIncrementalSearchingEnabled = true
		textView.isAutomaticLinkDetectionEnabled = false
		textView.isAutomaticDataDetectionEnabled = false
		textView.drawsBackground = false
		textView.textContainerInset = NSSize(width: 0, height: 8)
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
			guard movedUp, top < 160 else { return }
			owner?.viewController?.loadOlderHistory()
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

		addSubview(topicField)
		addSubview(topicDisclosure)
		addSubview(scrollView)
		/* No rule under the topic: the change of colour and the gap are the
		 edge, and a hairline there read as a second toolbar. */
		scrollViewTopWithTopicConstraint = scrollView.topAnchor.constraint(
			equalTo: topicField.bottomAnchor,
			constant: 6
		)
		scrollViewTopWithoutTopicConstraint = scrollView.topAnchor.constraint(equalTo: topAnchor)
		NSLayoutConstraint.activate([
			topicField.topAnchor.constraint(equalTo: topAnchor, constant: 7),
			topicField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
			topicField.trailingAnchor.constraint(equalTo: topicDisclosure.leadingAnchor, constant: -6),
			topicDisclosure.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
			topicDisclosure.firstBaselineAnchor.constraint(equalTo: topicField.firstBaselineAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
		setTopic(nil)
		applyTheme()
	}

	override func layout() {
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

	/** Performs the scroll a return to the window asked for, once the clip view
	 has a height to scroll within. The first layout after the view lands in a
	 window runs before the scroll view has tiled, so the clip is still empty
	 then; the clip's frame change afterwards is what says it is ready. */
	private func scrollToBottomIfPending() {
		guard scrollsToBottomOnLayout, scrollView.contentView.bounds.height > 0 else { return }
		scrollsToBottomOnLayout = false
		scrollToBottom()
	}

	private var isFollowingDocumentGrowth = false

	private func documentHeightDidChange() {
		guard editDepth == 0, window != nil, !isHiddenOrHasHiddenAncestor,
		      followsBottom, isNearBottom == false, isFollowingDocumentGrowth == false else { return }
		/* `scrollToBottom` resizes the document itself; that resize must not
		 come back through here. */
		isFollowingDocumentGrowth = true
		defer { isFollowingDocumentGrowth = false }
		scrollToBottom()
	}

	/** A transcript that was following the end when it was hidden shows the end
	 again when it comes back: the lines that arrived meanwhile are what the
	 reader opened the channel for. The scroll waits for the first layout in
	 the window, where the clip view has its real height. */
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		/* A popover cannot be anchored to a view that is in no window, and the
		 view that comes back is showing a conversation the click is no longer
		 about. */
		if window == nil {
			cancelPendingNicknameClick()
		}
		guard window != nil, followsBottom else { return }
		scrollsToBottomOnLayout = true
		needsLayout = true
	}

	/// Starts a batch of renders: the colours resolved for the last one, and the
	/// pinned-colour table they were resolved against, both belong to it alone.
	private func beginNicknameColorBatch() {
		nicknameColors.removeAll(keepingCapacity: true)
		nicknameColorOverrides = nil
	}

	/// The space beneath the transcript that something else is drawn over.
	func setBottomContentInset(_ inset: CGFloat) {
		guard scrollView.contentInsets.bottom != inset else { return }
		scrollView.contentInsets.bottom = inset
		scrollView.scrollerInsets.bottom = inset
		needsLayout = true
	}

	func setTopic(_ topic: String?) {
		let value = topic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		let hasTopic = value.isEmpty == false
		topicField.attributedStringValue = attributedTopic(value)
		topicField.toolTip = value
		topicField.isHidden = hasTopic == false
		if isTopicExpanded {
			isTopicExpanded = false
			applyTopicExpansion()
		}
		if hasTopic {
			scrollViewTopWithoutTopicConstraint?.isActive = false
			scrollViewTopWithTopicConstraint?.isActive = true
		} else {
			scrollViewTopWithTopicConstraint?.isActive = false
			scrollViewTopWithoutTopicConstraint?.isActive = true
		}
		needsLayout = true
	}

	func setBufferLimit(_ limit: Int) {
		bufferLimit = max(1, limit)
		let anchor = selectionAnchor()
		trimToBufferLimit()
		restoreSelection(anchor)
	}

	func setTextScale(_ scale: CGFloat) {
		textScale = max(0.5, min(scale, 3))
		/* The topic is drawn by a label rather than by the document, so the
		 rebuild below does not reach it. */
		topicField.attributedStringValue = attributedTopic(topicField.stringValue)
		topicField.invalidateIntrinsicContentSize()
		topicLineHeightCache = nil
		needsLayout = true
		rebuild()
	}

	func replace(with newLines: [TranscriptLine]) {
		clear()
		scrollbackAllowance = 0
		followsBottom = true
		lines = Array(newLines.suffix(bufferLimit))
		rebuild(preservingScrollPosition: false)
		scrollToBottom()
	}

	func append(_ newLines: [TranscriptLine]) {
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

	/** Adds older lines above what is already drawn.

	 Nothing is dropped from the end: the newest lines are the ones the reader
	 comes back to, and the controller still names them. The window's top edge
	 grows instead, up to the largest scrollback the preference allows, which is
	 what keeps a reader who holds the scroll wheel from growing the document
	 without bound. */
	func prepend(_ newLines: [TranscriptLine]) -> [String] {
		guard newLines.isEmpty == false else { return [] }
		let room = LogViewBufferPolicy.validLimits.upperBound - lines.count
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

	/// The lines of `newLines` the document does not already hold, in order and
	/// without repeats within the batch itself.
	private func acceptingNewIdentifiers(_ newLines: [TranscriptLine]) -> [TranscriptLine] {
		var batch = Set<String>()
		return newLines.filter {
			lineNumbers.contains($0.lineNumber) == false && batch.insert($0.lineNumber).inserted
		}
	}

	func clear() {
		cancelPendingNicknameClick()
		lines.removeAll()
		lineLengths.removeAll()
		lineNumbers.removeAll()
		inlineImages.removeAll()
		beginNicknameColorBatch()
		scrollbackAllowance = 0
		textView.textStorage?.setAttributedString(NSAttributedString())
		if let owner {
			owner.inlineImageLoader.cancelLoads(forView: owner.viewIdentifier)
		}
		updateLayoutAfterEdit()
	}

	func updateDelivery(_ update: TranscriptDeliveryUpdate) {
		guard let index = lines.firstIndex(where: { $0.lineNumber == update.lineNumber }) else { return }
		lines[index].deliveryState = update.state
		lines[index].messageIdentifier = update.messageIdentifier ?? lines[index].messageIdentifier
		lines[index].deliveryFailureReason = update.reason
		refresh(at: index)
	}

	func updateReactions(_ reactions: [String: [String]], messageIdentifier: String) {
		for index in lines.indices where lines[index].messageIdentifier == messageIdentifier {
			lines[index].mergeReactions(reactions)
			refresh(at: index)
		}
	}

	func setUnreadMarker(_ mark: TranscriptScrollbackMark) {
		var changed: [Int] = []
		for index in lines.indices where lines[index].markers.contains(where: \.isUnread) {
			lines[index].markers.removeAll(where: \.isUnread)
			changed.append(index)
		}
		let target: Int? = switch mark {
		case .none: nil
		case .latest: lines.indices.last
		case let .line(identifier): lines
			.firstIndex { $0.matches(identifier: identifier) } ?? lines.indices.first
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

	func jump(to lineNumber: String) -> Bool {
		guard let range = range(ofLine: lineNumber) else { return false }
		followsBottom = false
		scrollsToBottomOnLayout = false
		textView.scrollRangeToVisible(range)
		return true
	}

	/** Scrolls so the last line sits just above the bottom content inset.

	 `scrollRangeToVisible` judges visibility by the clip view's bounds, which
	 still include the strip beneath the floating input bar; a line that lands
	 there counts as visible and the view stops following. The target is
	 computed from the inset instead. */
	func scrollToBottom() {
		followsBottom = true
		guard editDepth == 0, window != nil, !isHiddenOrHasHiddenAncestor else {
			/* Nothing can be measured while the view is off screen or mid-edit.
			 The layout pass is what performs the deferred scroll, so it has to be
			 asked for: a hidden view that is never marked dirty never lays out
			 again, and the transcript comes back parked where it was. */
			scrollsToBottomOnLayout = true
			needsLayout = true
			return
		}
		let clip = scrollView.contentView
		/* Measure at the width the clip will give the text: a view sized before
		 the scroll view tiled wraps at the wrong width, and the end it scrolls
		 to is then not the end the reader sees. */
		if clip.bounds.width > 0, textView.frame.width != clip.bounds.width {
			textView.setFrameSize(NSSize(width: clip.bounds.width, height: textView.frame.height))
		}
		if let layoutManager = textView.textLayoutManager {
			layoutManager.ensureLayout(for: layoutManager.documentRange)
		}
		textView.sizeToFit()
		let insets = scrollView.contentInsets
		let targetY = textView.frame.maxY + insets.bottom - clip.bounds.height
		clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: max(-insets.top, targetY)))
		scrollView.reflectScrolledClipView(clip)
	}

	/** Runs a find command on the transcript's own find bar.

	 The bar is the text view's, and the tag is how `NSTextView` reads which
	 find action a sender asked for.

	 Only opening the bar takes the keyboard, and only when the find session
	 does not already hold it: ⌘G and ⇧⌘G are pressed while the reader is typing
	 in the find field or in the message field, and moving the keyboard onto the
	 transcript under them stopped the next keystroke reaching either. */
	func performFindAction(_ action: NSTextFinder.Action) {
		if action == .showFindInterface, findSessionHoldsKeyboard == false {
			window?.makeFirstResponder(textView)
		}
		/* A match the reader is reading is a place in the transcript, so the
		 next line to arrive must not pull the viewport off it -- and neither may
		 a scroll-to-end that an earlier append deferred to the next layout pass.
		 Both flags, exactly as `jump(to:)` clears them. Following resumes the
		 same way a jump's does: by scrolling back to the end. */
		switch action {
		case .showFindInterface, .nextMatch, .previousMatch:
			followsBottom = false
			scrollsToBottomOnLayout = false
		default:
			break
		}
		let sender = NSMenuItem()
		sender.tag = action.rawValue
		textView.performTextFinderAction(sender)
	}

	/// Whether the keyboard is already inside the find session: the transcript
	/// itself, or the find bar the text view puts above it.
	private var findSessionHoldsKeyboard: Bool {
		guard let responder = window?.firstResponder as? NSView else { return false }
		if responder === textView || responder.isDescendant(of: textView) {
			return true
		}
		guard let findBar = scrollView.findBarView else { return false }
		return responder === findBar || responder.isDescendant(of: findBar)
	}

	/// A download outlives the line that asked for it, so an image whose line
	/// has already scrolled out of the buffer is dropped rather than kept.
	func addInlineImage(_ image: TranscriptInlineImage) -> Bool {
		guard let index = lines.firstIndex(where: { $0.lineNumber == image.lineNumber }) else { return false }
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

	func applyTheme() {
		beginEditing()
		defer { endEditing() }
		let controller = SharedApplication.sharedThemeController()
		layer?.backgroundColor = controller.backgroundColor.cgColor
		textView.insertionPointColor = controller.resolved(controller.theme.palette.primaryText)
		topicField.attributedStringValue = attributedTopic(topicField.stringValue)
		rebuild()
	}

	func textViewDidChangeSelection(_: Notification) {
		guard let owner, isAdjustingSelection == false else { return }
		let range = textView.selectedRange()
		owner.selection = range.length > 0 ? (textView.string as NSString).substring(with: range) : nil
		/* Stepping through find results selects each match in turn; that is the
		 find bar moving the reader, not the reader selecting text, so it must
		 not overwrite the pasteboard. */
		guard scrollView.isFindBarVisible == false else { return }
		if Preferences.Messages.copyOnSelect.value, owner.hasSelection {
			owner.copySelection()
		}
	}

	func textView(_: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
		guard let url = link as? URL else { return false }
		owner?.policy.openWebpage(url)
		return true
	}

	func contextTarget(at point: NSPoint) -> LogPolicyTarget {
		let target = LogPolicyTarget()
		guard let storage = textView.textStorage, let index = characterIndex(at: point) else { return target }
		target.anchorURL = (storage.attribute(.link, at: index, effectiveRange: nil) as? URL)?.absoluteString
		target.nickname = storage.attribute(.transcriptNickname, at: index, effectiveRange: nil) as? String
		target.lineNumber = storage.attribute(.transcriptLineNumber, at: index, effectiveRange: nil) as? String
		target.lineMessageIdentifier = storage.attribute(
			.transcriptMessageIdentifier,
			at: index,
			effectiveRange: nil
		) as? String
		target.lineType = storage.attribute(.transcriptLineType, at: index, effectiveRange: nil) as? String
		/* The line's author, not whichever name the click landed on: a reply
		 raised from a message body answers the person who wrote it. */
		target.lineNickname = storage.attribute(.transcriptLineNickname, at: index, effectiveRange: nil) as? String
		target.lineExcerpt = storage.attribute(.transcriptExcerpt, at: index, effectiveRange: nil) as? String
		switch TranscriptAction(attributeValue: storage.attribute(.transcriptAction, at: index, effectiveRange: nil)) {
		case let .channel(name): target.channelName = name
		case let .nickname(name): target.nickname = name
		case nil: break
		}
		/* Only an inline image, not every attachment: a delivery receipt is a
		 symbol drawn the same way, and it is not a picture to copy or save. */
		if let address = storage.attribute(.transcriptInlineImage, at: index, effectiveRange: nil) as? String {
			target.inlineImageURL = address
			target.inlineImage = (storage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment)?
				.image
		}
		return target
	}

	/// The ceiling the buffer is trimmed to: what the reader asked for, widened
	/// by the scrollback they pulled in, and never past the largest scrollback
	/// the preference allows.
	private var effectiveBufferLimit: Int {
		min(bufferLimit + scrollbackAllowance, LogViewBufferPolicy.validLimits.upperBound)
	}

	/// Drops the oldest lines that no longer fit. Only the oldest: the end of
	/// the transcript is what the controller, the jump commands and the reader
	/// all address.
	private func trimToBufferLimit(force: Bool = false) {
		guard editDepth == 0 || force else { return }
		let limit = effectiveBufferLimit
		guard lines.count > limit else { return }
		let count = lines.count - limit
		preservingVisibleText {
			remove(lines.startIndex ..< count)
		}
	}

	/// Where a line begins in the text storage.
	private func documentLocation(ofLineAt index: Int) -> Int {
		lineLengths[..<index].reduce(0, +)
	}

	private func range(ofLine lineNumber: String) -> NSRange? {
		guard let index = lines.firstIndex(where: { $0.matches(identifier: lineNumber) }) else { return nil }
		return NSRange(location: documentLocation(ofLineAt: index), length: lineLengths[index])
	}

	/// Renders `newLines` and splices them into the document at `index`.
	private func insert(_ newLines: [TranscriptLine], at index: Int) {
		guard let storage = textView.textStorage, newLines.isEmpty == false else { return }
		cancelPendingNicknameClick()
		beginNicknameColorBatch()
		var lengths: [Int] = []
		lengths.reserveCapacity(newLines.count)
		var location = index == lines.count ? storage.length : documentLocation(ofLineAt: index)
		storage.beginEditing()
		defer { storage.endEditing() }
		for start in stride(from: 0, to: newLines.count, by: 32) {
			let rendered = NSMutableAttributedString()
			for line in newLines[start ..< min(start + 32, newLines.count)] {
				let length = rendered.length
				rendered.append(render(line))
				lengths.append(rendered.length - length)
			}
			storage.replaceCharacters(in: NSRange(location: location, length: 0), with: rendered)
			location += rendered.length
		}
		lines.insert(contentsOf: newLines, at: index)
		lineLengths.insert(contentsOf: lengths, at: index)
		lineNumbers.formUnion(newLines.lazy.map(\.lineNumber))
	}

	/// Removes a contiguous run of lines and the characters they drew.
	private func remove(_ indices: Range<Int>) {
		guard let storage = textView.textStorage, indices.isEmpty == false else { return }
		cancelPendingNicknameClick()
		let location = documentLocation(ofLineAt: indices.lowerBound)
		let length = lineLengths[indices].reduce(0, +)
		var retiredMarkers: [String: TranscriptMarker] = [:]
		let retiredLineNumbers = lines[indices].map(\.lineNumber)
		for line in lines[indices] {
			inlineImages.removeValue(forKey: line.lineNumber)
			for marker in line.markers {
				retiredMarkers[marker.selectionSegment] = marker
			}
		}
		storage.deleteCharacters(in: NSRange(location: location, length: length))
		lines.removeSubrange(indices)
		lineLengths.removeSubrange(indices)
		lineNumbers.subtract(retiredLineNumbers)
		if indices.lowerBound == 0 {
			/* The oldest lines are the ones scrollback added, so the ceiling
			 they raised comes back down with them. Without this a reader who
			 pulled history in once holds the widened buffer for the session,
			 and a 500-line scrollback ends up keeping tens of thousands. */
			scrollbackAllowance = max(0, scrollbackAllowance - indices.count)
		}
		if let owner {
			for identifier in retiredLineNumbers {
				owner.inlineImageLoader.cancelLoads(forView: owner.viewIdentifier, lineNumber: identifier)
			}
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
		storage.replaceCharacters(
			in: NSRange(location: documentLocation(ofLineAt: index), length: lineLengths[index]),
			with: rendered
		)
		lineLengths[index] = rendered.length
		updateLayoutAfterEdit()
		restoreSelection(anchor)
	}

	/** Rewrites the whole document.

	 Only a change that alters how every line draws needs one: the theme and the
	 text scale. Ordinary traffic edits the storage in place, which is what keeps
	 a busy channel from re-rendering its whole scrollback per message. */
	private func rebuild(preservingScrollPosition: Bool = true) {
		let oldOrigin = scrollView.contentView.bounds.origin
		let viewport = viewportAnchor()
		let anchor = selectionAnchor()
		beginNicknameColorBatch()
		let retainedLines = lines
		lines.removeAll(keepingCapacity: true)
		lineLengths.removeAll(keepingCapacity: true)
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
	}
}

extension NativeTranscriptView {
	/** The selection expressed against its two semantic endpoints.

	 A character offset into the document is only meaningful until the document
	 changes: trimming the oldest lines or inserting older ones shifts every
	 offset after them, and a selection restored by number then covers text the
	 reader never selected — which `copyOnSelect` would put on the pasteboard. */
	private func selectionAnchor() -> SelectionAnchor? {
		guard editDepth == 0 else { return nil }
		let selection = textView.selectedRange()
		guard selection.length > 0, lineLengths.count == lines.count else { return nil }
		guard let start = selectionEndpoint(at: selection.location),
		      let end = selectionEndpoint(at: NSMaxRange(selection), isEnd: true) else { return nil }
		return SelectionAnchor(start: start, end: end)
	}

	private func selectionEndpoint(at position: Int, isEnd: Bool = false) -> SelectionAnchor.Endpoint? {
		var location = 0
		for (index, line) in lines.enumerated() {
			let next = location + lineLengths[index]
			if position < next || isEnd && position == next {
				var segmentRange = NSRange()
				let segment = textView.textStorage?.attribute(
					.transcriptSelectionSegment, at: max(location, position - (isEnd ? 1 : 0)),
					longestEffectiveRange: &segmentRange,
					in: NSRange(location: location, length: lineLengths[index])
				) as? String
				return SelectionAnchor.Endpoint(
					lineNumber: line.lineNumber,
					segment: segment,
					offset: position - (segment == nil ? location : segmentRange.location)
				)
			}
			location = next
		}
		return nil
	}

	private func restoreSelection(_ anchor: SelectionAnchor?) {
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
		owner?.selection = restored.length > 0
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

	private func viewportAnchor() -> (endpoint: SelectionAnchor.Endpoint, offset: CGFloat)? {
		guard !followsBottom, editDepth == 0, window != nil, !isHiddenOrHasHiddenAncestor,
		      lineLengths.count == lines.count else { return nil }
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

	private func restoreViewport(_ anchor: (endpoint: SelectionAnchor.Endpoint, offset: CGFloat)) {
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
	}

	func beginEditing() {
		cancelPendingNicknameClick()
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

	private func updateLayoutAfterEdit() {
		guard editDepth == 0, window != nil, !isHiddenOrHasHiddenAncestor else {
			needsLayout = true
			return
		}
		textView.updateBottomAlignment()
	}

	/// Whether the reader is at the end, judged by the part of the clip view
	/// the input bar does not cover.
	private var isNearBottom: Bool {
		let clip = scrollView.contentView
		let visibleBottom = clip.bounds.maxY - scrollView.contentInsets.bottom
		return visibleBottom >= textView.frame.maxY - 40
	}

	@objc private func topicDoubleClicked(_: NSClickGestureRecognizer) {
		owner?.policy.topicBarDoubleClicked()
	}

	/** Answers a click the text view has already handled.

	 A plain click on a name opens that member's profile, but only once the
	 double-click interval has passed without a second click: double-clicking a
	 name opens a conversation with them, and that must not also leave a popover
	 behind. Everything else about the click — the caret, the selection, a link
	 the reader followed — was settled before this ran. */
	private func textViewClicked(_ click: TranscriptClick) {
		cancelPendingNicknameClick()
		/* A click that left a selection behind was a drag over the text, and a
		 drag over a name selects the name rather than asking about its owner. */
		guard click.clickCount == 1, click.dragged == false, click.modifiers.isEmpty,
		      textView.selectedRange().length == 0
		else { return }
		if let reaction = clickedReaction(at: click.point) {
			owner?.policy.reactionChipClicked(reaction)
			return
		}
		guard let (nickname, range) = clickedNickname(at: click.point) else { return }
		pendingNicknameClick = Task { [weak self] in
			try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
			guard let self, Task.isCancelled == false else { return }
			pendingNicknameClick = nil
			/* The wait is long enough for a line to arrive, and the characters
			 the click named may no longer spell that name -- or may be gone. */
			guard let range = nicknameRange(spelling: nickname, at: range) else { return }
			showMemberInformation(for: nickname, spelledIn: range, clickedAt: click.point)
		}
	}

	/** Calls off the profile a single click asked for.

	 The popover is anchored to characters, so every edit that can move or
	 remove them takes the pending click with it: a line appended under the
	 name, a trim that dropped it, a theme change that rewrote the document.
	 Leaving it to the next click meant a popover opening a quarter of a second
	 later against whatever text had taken that range. */
	private func cancelPendingNicknameClick() {
		guard pendingNicknameClick != nil else { return }
		pendingNicknameClick?.cancel()
		pendingNicknameClick = nil
	}

	/// `range` if the storage still spells `nickname` there, and nothing if the
	/// document moved underneath the click.
	private func nicknameRange(spelling nickname: String, at range: NSRange) -> NSRange? {
		guard let storage = textView.textStorage, range.length > 0, NSMaxRange(range) <= storage.length
		else { return nil }
		var current = NSRange(location: NSNotFound, length: 0)
		guard case let .nickname(spelled) = TranscriptAction(attributeValue: storage.attribute(
			.transcriptAction, at: range.location, effectiveRange: &current
		)), spelled == nickname, NSEqualRanges(current, range) else { return nil }
		return current
	}

	private func showMemberInformation(for nickname: String, spelledIn range: NSRange, clickedAt point: NSPoint) {
		guard let window else { return }
		let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
		/* A range the layout has not reached answers with an empty rect, and a
		 popover anchored to one points at the view's corner rather than at the
		 name; the click itself is always somewhere real. */
		let rect = screenRect.isEmpty
			? NSRect(origin: point, size: .zero).insetBy(dx: -1, dy: -1)
			: textView.convert(window.convertFromScreen(screenRect), from: nil)
		owner?.showMemberInformation(for: nickname, relativeTo: rect, of: textView)
	}

	/// The reaction chip under a point, or nil where there is none.
	private func clickedReaction(at point: NSPoint) -> TranscriptReactionTarget? {
		guard let storage = textView.textStorage, let index = characterIndex(at: point) else { return nil }
		return TranscriptReactionTarget(
			attributeValue: storage.attribute(.transcriptReaction, at: index, effectiveRange: nil)
		)
	}

	/** The character a point in the text view names, or nil where the point is
	 not on the text at all.

	 Every question asked of a click -- the chip under it, the menu's target,
	 the name to show a profile for -- is a question about a character, and
	 `characterIndexForInsertion(at:)` answers a different one: it is the
	 nearest insertion point, so a click in the blank tail of a line, in the
	 gutter beside it, or below the last line all answer with a real character
	 that nothing was drawn at. Holding the point against the line fragment's
	 typographic bounds first is what makes the answer the character the reader
	 pointed at. */
	private func characterIndex(at point: NSPoint) -> Int? {
		guard let storage = textView.textStorage, storage.length > 0,
		      let layoutManager = textView.textLayoutManager
		else { return nil }
		let layoutPoint = layoutPoint(for: point)
		guard let fragment = layoutManager.textLayoutFragment(for: layoutPoint) else { return nil }
		let pointInFragment = NSPoint(
			x: layoutPoint.x - fragment.layoutFragmentFrame.minX,
			y: layoutPoint.y - fragment.layoutFragmentFrame.minY
		)
		guard fragment.textLineFragments.contains(where: { $0.typographicBounds.contains(pointInFragment) })
		else { return nil }
		return min(textView.characterIndexForInsertion(at: point), storage.length - 1)
	}

	/// Layout coordinates start at the container's origin, which the text view
	/// moves to keep a short transcript at the foot of the viewport.
	private func layoutPoint(for point: NSPoint) -> NSPoint {
		let origin = textView.textContainerOrigin
		return NSPoint(x: point.x - origin.x, y: point.y - origin.y)
	}

	/** The nickname under a point in the text view, and the characters that
	 spell it, or nil where there is none. Links are the text view's own, and
	 a click on one has already opened it. */
	private func clickedNickname(at point: NSPoint) -> (String, NSRange)? {
		guard let storage = textView.textStorage, var index = characterIndex(at: point) else { return nil }
		/* An insertion index rounds to the nearer boundary, so a click in the
		 right half of a name's last glyph answers with the character after the
		 name. Stepping back belongs to that case alone: the gap after a name
		 deliberately carries none of its action, and neither does whatever
		 follows an inline mention. */
		if index > 0, let boundary = insertionBoundaryX(at: index), layoutPoint(for: point).x < boundary {
			var runRange = NSRange(location: NSNotFound, length: 0)
			let previous = TranscriptAction(attributeValue: storage.attribute(
				.transcriptAction, at: index - 1, effectiveRange: &runRange
			))
			if case .nickname = previous, NSMaxRange(runRange) == index {
				index -= 1
			}
		}
		guard storage.attribute(.link, at: index, effectiveRange: nil) == nil else { return nil }
		var range = NSRange(location: NSNotFound, length: 0)
		guard case let .nickname(nickname) = TranscriptAction(
			attributeValue: storage.attribute(.transcriptAction, at: index, effectiveRange: &range)
		), nickname.isEmpty == false else { return nil }
		return (nickname, range)
	}

	/// Where an insertion boundary sits horizontally, in layout coordinates, so
	/// a click can be told from the glyph on either side of it.
	private func insertionBoundaryX(at index: Int) -> CGFloat? {
		guard let layoutManager = textView.textLayoutManager,
		      let contentManager = layoutManager.textContentManager,
		      let location = contentManager.location(contentManager.documentRange.location, offsetBy: index)
		else { return nil }
		var boundary: CGFloat?
		layoutManager.enumerateTextSegments(
			in: NSTextRange(location: location),
			type: .standard,
			options: [.rangeNotRequired]
		) { _, frame, _, _ in
			boundary = frame.minX
			return false
		}
		return boundary
	}

	@objc private func contentDoubleClicked(_ recognizer: NSClickGestureRecognizer) {
		/* The recognizer can claim the second click before the text view sees
		 it, so this is the other place a double click calls off the popover the
		 first click asked for. */
		cancelPendingNicknameClick()
		guard let owner else { return }
		owner.prepareContextTarget(at: recognizer.location(in: textView))
		if owner.contextMenuTarget.channelName != nil {
			owner.policy.channelNameDoubleClicked(in: owner)
		} else if owner.contextMenuTarget.nickname != nil {
			owner.policy.nicknameDoubleClicked(in: owner)
		}
	}
}

// MARK: - Topic disclosure

struct TopicDisclosureButton: View {
	let isExpanded: Bool
	let action: () -> Void

	private var label: String {
		isExpanded ? AccessibilityStrings.showLessTopic : AccessibilityStrings.showFullTopic
	}

	var body: some View {
		Button(action: action) {
			Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
				.font(.system(size: 11, weight: .semibold))
				.foregroundStyle(.secondary)
				.frame(width: 16, height: 16)
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(label)
		.help(label)
	}
}

extension NativeTranscriptView {
	func toggleTopicExpansion() {
		isTopicExpanded.toggle()
		applyTopicExpansion()
	}

	/// Unfolded, the topic still stops short of taking the transcript's room:
	/// the longest topic a server allows wraps to about this many lines at the
	/// column's minimum width, and anything beyond it is in the tooltip.
	static let expandedTopicLineLimit = 8

	/** Folded, the topic is one truncated line; unfolded it wraps in full from
	 its first word, up to `expandedTopicLineLimit` lines. The field caches its intrinsic height, so the cache is
	 dropped here: without that the chevron flipped and the field stayed one
	 line tall until something else moved the layout. */
	func applyTopicExpansion() {
		/* The field wraps up to the line limit and truncates the last line,
		 in both states; only the limit changes. */
		topicField.maximumNumberOfLines = isTopicExpanded ? Self.expandedTopicLineLimit : 1
		topicField.invalidateIntrinsicContentSize()
		topicDisclosure.rootView = TopicDisclosureButton(isExpanded: isTopicExpanded) { [weak self] in
			self?.toggleTopicExpansion()
		}
		needsLayout = true
	}

	/** Tells the field how wide it is, so its intrinsic height is the height of
	 the topic wrapped at that width rather than of one line. A constraint
	 write inside `layout()`, bounded the way the disclosure's is: the width
	 only changes when the frame does, and an unchanged width writes nothing. */
	private func updateTopicWrappingWidth() {
		let width = topicField.bounds.width
		guard width > 0, topicField.preferredMaxLayoutWidth != width else { return }
		topicField.preferredMaxLayoutWidth = width
		topicField.invalidateIntrinsicContentSize()
	}

	/// The chevron is only offered when one line does not hold the topic.
	func updateTopicDisclosure() {
		let text = topicField.attributedStringValue
		guard topicField.isHidden == false, let font = topicFont(of: text), topicField.bounds.width > 0 else {
			setTopicDisclosureHidden(true)
			return
		}
		let fullHeight = text.boundingRect(
			with: NSSize(width: topicField.bounds.width, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		).height
		let overflows = fullHeight > topicLineHeight(for: font) * 1.5
		setTopicDisclosureHidden(overflows == false)
		/* Also a constraint write from inside `layout()`, and bounded the same
		 way: the flag flips first, so the next pass finds nothing to fold. */
		if overflows == false, isTopicExpanded {
			isTopicExpanded = false
			applyTopicExpansion()
		}
	}

	/// Runs from `layout()`, so a write that changes nothing must not ask for
	/// another constraint pass.
	private func setTopicDisclosureHidden(_ hidden: Bool) {
		guard topicDisclosure.isHidden != hidden else { return }
		topicDisclosure.isHidden = hidden
	}

	/** The font the topic is actually drawn in.

	 ``attributedTopic(_:)`` scales the body size by the reader's text zoom and
	 writes the result into the string, which the field's own `font` never
	 learns: measuring the scaled string against an unscaled line height made
	 every one-line topic overflow at ⌘=, and the chevron appeared on a topic
	 with nothing to unfold. */
	private func topicFont(of text: NSAttributedString) -> NSFont? {
		guard text.length > 0 else { return topicField.font }
		return text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? topicField.font
	}

	/// Asked on every layout pass, so the measurement is kept per font.
	private func topicLineHeight(for font: NSFont) -> CGFloat {
		if let topicLineHeightCache, topicLineHeightCache.font == font {
			return topicLineHeightCache.height
		}
		let height = TextLineMetrics.lineHeight(for: font)
		topicLineHeightCache = (font, height)
		return height
	}
}

extension NativeTranscriptView {
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

extension NativeTranscriptView {
	var printableView: NSView {
		textView
	}

	func clearSelection() {
		textView.setSelectedRange(NSRange(location: 0, length: 0))
	}

	func copySelection() {
		textView.copy(nil)
	}
}

/** The topic label. Its intrinsic width is withheld from Auto Layout: a
 wrapping label reports the whole topic on one line as its natural width, and
 through the transcript's fitting size that became the column's minimum, so
 the window grew to the topic's length on every corner drag. The height still
 comes from the label, wrapped at `preferredMaxLayoutWidth`. */
final class TopicLabel: NSTextField {
	override var intrinsicContentSize: NSSize {
		var size = super.intrinsicContentSize
		size.width = NSView.noIntrinsicMetric
		return size
	}
}
