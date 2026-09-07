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
@MainActor
final class NativeTranscriptTextView: NSTextView {
	weak var owner: LogView?
	private var bottomAlignmentOffset: CGFloat = 0

	/// Told synchronously when the document's height changes, so a transcript
	/// that follows its end can stay there in the same pass that grew it.
	var onHeightChange: (@MainActor () -> Void)?

	convenience init(owner: LogView) {
		self.init(usingTextLayoutManager: true)
		self.owner = owner
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
final class NativeTranscriptView: NSView, NSTextViewDelegate {
	weak var owner: LogView?

	let topicField = NSTextField(wrappingLabelWithString: "")
	/* SwiftUI owns controls; this adapter only hosts one. */
	let topicDisclosure = NSHostingView(rootView: TopicDisclosureButton(isExpanded: false, action: {}))
	var isTopicExpanded = false
	private let separator = NSBox()
	private let scrollView = NSScrollView()
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
	/// Resolved nickname colours for the batch being rendered. Each lookup costs
	/// a read of the defaults store, and one batch asks for the same handful of
	/// names over and over.
	var nicknameColors: [String: NSColor] = [:]
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

		separator.boxType = .separator
		separator.translatesAutoresizingMaskIntoConstraints = false

		textView.delegate = self
		textView.isEditable = false
		textView.isSelectable = true
		textView.setAccessibilityIdentifier("channel-transcript")
		textView.isRichText = true
		textView.importsGraphics = false
		textView.usesFindPanel = true
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

		scrollView.documentView = textView
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
			guard let self, scrollView.contentView.bounds.minY < 160 else { return }
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
		addSubview(separator)
		addSubview(scrollView)
		scrollViewTopWithTopicConstraint = scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor)
		scrollViewTopWithoutTopicConstraint = scrollView.topAnchor.constraint(equalTo: topAnchor)
		NSLayoutConstraint.activate([
			topicField.topAnchor.constraint(equalTo: topAnchor, constant: 7),
			topicField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
			topicField.trailingAnchor.constraint(equalTo: topicDisclosure.leadingAnchor, constant: -6),
			topicDisclosure.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
			topicDisclosure.firstBaselineAnchor.constraint(equalTo: topicField.firstBaselineAnchor),
			separator.topAnchor.constraint(equalTo: topicField.bottomAnchor, constant: 7),
			separator.leadingAnchor.constraint(equalTo: leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: trailingAnchor),
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
		guard window != nil, followsBottom else { return }
		scrollsToBottomOnLayout = true
		needsLayout = true
	}

	/// The space beneath the transcript that something else is drawn over.
	func setBottomContentInset(_ inset: CGFloat) {
		guard scrollView.contentInsets.bottom != inset else { return }
		scrollView.automaticallyAdjustsContentInsets = false
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
		separator.isHidden = hasTopic == false
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
		guard newLines.isEmpty == false else { return }
		let followsBottom = followsBottom
		let anchor = selectionAnchor()
		insert(newLines, at: lines.count)
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
		var seen = Set(lines.map(\.lineNumber))
		let accepted = Array(newLines.filter { seen.insert($0.lineNumber).inserted }.suffix(room))
		let anchor = selectionAnchor()
		preservingVisibleText {
			insert(accepted, at: 0)
			scrollbackAllowance += accepted.count
			updateLayoutAfterEdit()
		}
		restoreSelection(anchor)
		return accepted.map(\.lineNumber)
	}

	func clear() {
		lines.removeAll()
		lineLengths.removeAll()
		inlineImages.removeAll()
		nicknameColors.removeAll()
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

	func find(_ search: String, movingForward: Bool) {
		guard search.isEmpty == false else { return }
		let source = textView.string as NSString
		let selected = textView.selectedRange()
		let options: NSString.CompareOptions = movingForward ? [.caseInsensitive] : [.caseInsensitive, .backwards]
		let firstRange = if movingForward {
			NSRange(location: NSMaxRange(selected), length: source.length - NSMaxRange(selected))
		} else {
			NSRange(location: 0, length: selected.location)
		}
		var match = source.range(of: search, options: options, range: firstRange)
		if match.location == NSNotFound {
			match = source.range(of: search, options: options, range: NSRange(location: 0, length: source.length))
		}
		guard match.location != NSNotFound else { NSSound.beep(); return }
		followsBottom = false
		scrollsToBottomOnLayout = false
		textView.setSelectedRange(match)
		textView.scrollRangeToVisible(match)
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
			linkIdentifier: image.linkIdentifier, image: decoded, originalSize: decoded.size, attachment: attachment
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
		guard let storage = textView.textStorage, storage.length > 0 else { return target }
		let index = min(textView.characterIndexForInsertion(at: point), storage.length - 1)
		target.anchorURL = (storage.attribute(.link, at: index, effectiveRange: nil) as? URL)?.absoluteString
		target.nickname = storage.attribute(.transcriptNickname, at: index, effectiveRange: nil) as? String
		target.lineNumber = storage.attribute(.transcriptLineNumber, at: index, effectiveRange: nil) as? String
		target.lineMessageIdentifier = storage.attribute(
			.transcriptMessageIdentifier,
			at: index,
			effectiveRange: nil
		) as? String
		target.lineType = storage.attribute(.transcriptLineType, at: index, effectiveRange: nil) as? String
		target.lineNickname = target.nickname
		target.lineExcerpt = storage.attribute(.transcriptExcerpt, at: index, effectiveRange: nil) as? String
		if let action = storage.attribute(.transcriptAction, at: index, effectiveRange: nil) as? String {
			if action.hasPrefix("channel:") {
				target.channelName = String(action.dropFirst(8))
			}
			if action.hasPrefix("nickname:") {
				target.nickname = String(action.dropFirst(9))
			}
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
		nicknameColors.removeAll(keepingCapacity: true)
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
	}

	/// Removes a contiguous run of lines and the characters they drew.
	private func remove(_ indices: Range<Int>) {
		guard let storage = textView.textStorage, indices.isEmpty == false else { return }
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
		nicknameColors.removeAll(keepingCapacity: true)
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
		nicknameColors.removeAll(keepingCapacity: true)
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
		let start = position(anchor.start) ?? 0
		let end = position(anchor.end) ?? 0
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

	private func verticalPosition(at index: Int) -> CGFloat? {
		guard let window else { return nil }
		let rect = textView.firstRect(forCharacterRange: NSRange(location: index, length: 0), actualRange: nil)
		return textView.convert(window.convertFromScreen(rect), from: nil).minY
	}

	private func restoreViewport(_ anchor: (endpoint: SelectionAnchor.Endpoint, offset: CGFloat)) {
		guard window != nil, !isHiddenOrHasHiddenAncestor,
		      let verticalPosition = verticalPosition(at: position(anchor.endpoint) ?? 0) else { return }
		var origin = scrollView.contentView.bounds.origin
		origin.y = max(0, verticalPosition - anchor.offset)
		scrollView.contentView.scroll(to: origin)
		scrollView.reflectScrolledClipView(scrollView.contentView)
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

	@objc private func contentDoubleClicked(_ recognizer: NSClickGestureRecognizer) {
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

	func applyTopicExpansion() {
		topicField.maximumNumberOfLines = isTopicExpanded ? 0 : 1
		topicDisclosure.rootView = TopicDisclosureButton(isExpanded: isTopicExpanded) { [weak self] in
			self?.toggleTopicExpansion()
		}
		needsLayout = true
	}

	/// The chevron is only offered when one line does not hold the topic.
	func updateTopicDisclosure() {
		guard topicField.isHidden == false, let font = topicField.font, topicField.bounds.width > 0 else {
			topicDisclosure.isHidden = true
			return
		}
		let fullHeight = topicField.attributedStringValue.boundingRect(
			with: NSSize(width: topicField.bounds.width, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		).height
		let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
		let overflows = fullHeight > lineHeight * 1.5
		topicDisclosure.isHidden = overflows == false
		if overflows == false, isTopicExpanded {
			isTopicExpanded = false
			applyTopicExpansion()
		}
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
