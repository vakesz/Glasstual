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

private extension NSAttributedString.Key {
	static let transcriptLineNumber = NSAttributedString.Key("GlasstualTranscriptLineNumber")
	static let transcriptNickname = NSAttributedString.Key("GlasstualTranscriptNickname")
	static let transcriptLineType = NSAttributedString.Key("GlasstualTranscriptLineType")
	static let transcriptMessageIdentifier = NSAttributedString.Key("GlasstualTranscriptMessageIdentifier")
	static let transcriptExcerpt = NSAttributedString.Key("GlasstualTranscriptExcerpt")
	static let transcriptAction = NSAttributedString.Key("GlasstualTranscriptAction")
}

/// Where a selection sits, named by the line it starts in rather than by an
/// offset into a document that is about to change underneath it.
private struct SelectionAnchor: Equatable {
	let lineNumber: String
	let offset: Int
	let length: Int
}

private extension TranscriptMarker {
	var isUnread: Bool {
		if case .unread = self {
			true
		} else {
			false
		}
	}
}

@MainActor
private final class NativeTranscriptTextView: NSTextView {
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
private final class NativeTranscriptView: NSView, NSTextViewDelegate {
	weak var owner: LogView?

	let topicField = NSTextField(wrappingLabelWithString: "")
	/* SwiftUI owns controls; this adapter only hosts one. */
	let topicDisclosure = NSHostingView(rootView: TopicDisclosureButton(isExpanded: false, action: {}))
	var isTopicExpanded = false
	private let separator = NSBox()
	private let scrollView = NSScrollView()
	private let textView: NativeTranscriptTextView
	private var scrollViewTopWithTopicConstraint: NSLayoutConstraint?
	private var scrollViewTopWithoutTopicConstraint: NSLayoutConstraint?
	private let notifications = NotificationSubscriptions()
	private var lines: [TranscriptLine] = []
	/** How many characters each line occupies in the text storage, in the order
	 ``lines`` holds them. It is what lets an edit reach one line's characters:
	 a line's location is the sum of the lengths before it, so appending,
	 trimming and restyling a single line all touch the document in place
	 instead of rewriting it. */
	private var lineLengths: [Int] = []
	private var inlineImages: [String: [TranscriptInlineImage]] = [:]
	private var bufferLimit = LogViewBufferPolicy.defaultHardLimit
	/** Older lines the reader pulled in by scrolling back. They raise the
	 buffer's ceiling rather than pushing the newest lines out of it, so loading
	 scrollback can never make the end of the conversation disappear. */
	private var scrollbackAllowance = 0
	private var textScale: CGFloat = 1
	/** Whether the reader is following the end of the transcript. Set by their
	 own scrolling and by nothing else; appends, document growth and a return
	 to the window all scroll to the end while it holds. */
	private var followsBottom = true
	private var scrollsToBottomOnLayout = false
	/// Resolved nickname colours for the batch being rendered. Each lookup costs
	/// a read of the defaults store, and one batch asks for the same handful of
	/// names over and over.
	private var nicknameColors: [String: NSColor] = [:]
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
		/* Only the reader's own scrolling decides whether they follow the end.
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
		guard window != nil, followsBottom, isNearBottom == false, isFollowingDocumentGrowth == false else { return }
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
		scrollbackAllowance = 0
		followsBottom = true
		lines = Array(newLines.suffix(bufferLimit))
		let retained = Set(lines.map(\.lineNumber))
		inlineImages = inlineImages.filter { retained.contains($0.key) }
		rebuild(preservingScrollPosition: false)
		scrollToBottom()
	}

	func append(_ newLines: [TranscriptLine]) {
		guard newLines.isEmpty == false else { return }
		let followsBottom = followsBottom
		let anchor = selectionAnchor()
		insert(newLines, at: lines.count)
		trimToBufferLimit()
		textView.updateBottomAlignment()
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
	func prepend(_ newLines: [TranscriptLine]) {
		guard newLines.isEmpty == false else { return }
		let room = LogViewBufferPolicy.validLimits.upperBound - lines.count
		guard room > 0 else { return }
		/* The tail of the fetched block is the part adjacent to what is on
		 screen, so a block that does not fit keeps its newest lines. */
		let accepted = Array(newLines.suffix(room))
		let anchor = selectionAnchor()
		preservingVisibleText {
			insert(accepted, at: 0)
			scrollbackAllowance += accepted.count
			textView.updateBottomAlignment()
		}
		restoreSelection(anchor)
	}

	func clear() {
		lines.removeAll()
		lineLengths.removeAll()
		inlineImages.removeAll()
		nicknameColors.removeAll()
		scrollbackAllowance = 0
		textView.textStorage?.setAttributedString(NSAttributedString())
		textView.updateBottomAlignment()
	}

	func updateDelivery(_ update: TranscriptDeliveryUpdate) {
		guard let index = lines.firstIndex(where: { $0.lineNumber == update.lineNumber }) else { return }
		lines[index].deliveryState = update.state
		lines[index].messageIdentifier = update.messageIdentifier ?? lines[index].messageIdentifier
		lines[index].deliveryFailureReason = update.reason
		refresh(at: index)
	}

	func updateReactions(_ reactions: [String: [String]], messageIdentifier: String) {
		guard let index = lines.firstIndex(where: { $0.messageIdentifier == messageIdentifier }) else { return }
		lines[index].reactions = reactions
		refresh(at: index)
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
		textView.setSelectedRange(match)
		textView.scrollRangeToVisible(match)
	}

	/// A download outlives the line that asked for it, so an image whose line
	/// has already scrolled out of the buffer is dropped rather than kept.
	func addInlineImage(_ image: TranscriptInlineImage) {
		guard let index = lines.firstIndex(where: { $0.lineNumber == image.lineNumber }) else { return }
		var images = inlineImages[image.lineNumber] ?? []
		images.removeAll { $0.linkIdentifier == image.linkIdentifier }
		images.append(image)
		inlineImages[image.lineNumber] = images
		refresh(at: index)
	}

	func applyTheme() {
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
	private func trimToBufferLimit() {
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
		guard let index = lines.firstIndex(where: { $0.lineNumber == lineNumber }) else { return nil }
		return NSRange(location: documentLocation(ofLineAt: index), length: lineLengths[index])
	}

	/// Renders `newLines` and splices them into the document at `index`.
	private func insert(_ newLines: [TranscriptLine], at index: Int) {
		guard let storage = textView.textStorage, newLines.isEmpty == false else { return }
		nicknameColors.removeAll(keepingCapacity: true)
		let rendered = NSMutableAttributedString()
		var lengths: [Int] = []
		lengths.reserveCapacity(newLines.count)
		for line in newLines {
			let start = rendered.length
			rendered.append(render(line))
			lengths.append(rendered.length - start)
		}
		storage.replaceCharacters(
			in: NSRange(location: documentLocation(ofLineAt: index), length: 0),
			with: rendered
		)
		lines.insert(contentsOf: newLines, at: index)
		lineLengths.insert(contentsOf: lengths, at: index)
	}

	/// Removes a contiguous run of lines and the characters they drew.
	private func remove(_ indices: Range<Int>) {
		guard let storage = textView.textStorage, indices.isEmpty == false else { return }
		let location = documentLocation(ofLineAt: indices.lowerBound)
		let length = lineLengths[indices].reduce(0, +)
		for line in lines[indices] {
			inlineImages.removeValue(forKey: line.lineNumber)
		}
		storage.deleteCharacters(in: NSRange(location: location, length: length))
		lines.removeSubrange(indices)
		lineLengths.removeSubrange(indices)
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
		textView.updateBottomAlignment()
		restoreSelection(anchor)
	}

	/** Rewrites the whole document.

	 Only a change that alters how every line draws needs one: the theme and the
	 text scale. Ordinary traffic edits the storage in place, which is what keeps
	 a busy channel from re-rendering its whole scrollback per message. */
	private func rebuild(preservingScrollPosition: Bool = true) {
		let oldOrigin = scrollView.contentView.bounds.origin
		let anchor = selectionAnchor()
		nicknameColors.removeAll(keepingCapacity: true)
		let result = NSMutableAttributedString()
		lineLengths.removeAll(keepingCapacity: true)
		lineLengths.reserveCapacity(lines.count)

		for line in lines {
			let start = result.length
			result.append(render(line))
			lineLengths.append(result.length - start)
		}
		textView.textStorage?.setAttributedString(result)
		textView.updateBottomAlignment()
		restoreSelection(anchor)
		guard preservingScrollPosition else { return }
		textView.layoutSubtreeIfNeeded()
		scrollView.contentView.scroll(to: oldOrigin)
		scrollView.reflectScrolledClipView(scrollView.contentView)
	}

	/// Runs an edit that changes what sits above the viewport and keeps the
	/// text the reader is looking at where it was.
	private func preservingVisibleText(_ edit: () -> Void) {
		let oldHeight = textView.bounds.height
		let origin = scrollView.contentView.bounds.origin
		edit()
		textView.layoutSubtreeIfNeeded()
		var adjusted = origin
		adjusted.y += textView.bounds.height - oldHeight
		scrollView.contentView.scroll(to: adjusted)
		scrollView.reflectScrolledClipView(scrollView.contentView)
	}

	/** The selection expressed against the line it starts in.

	 A character offset into the document is only meaningful until the document
	 changes: trimming the oldest lines or inserting older ones shifts every
	 offset after them, and a selection restored by number then covers text the
	 reader never selected — which `copyOnSelect` would put on the pasteboard. */
	private func selectionAnchor() -> SelectionAnchor? {
		let selection = textView.selectedRange()
		guard selection.length > 0, lineLengths.count == lines.count else { return nil }
		var location = 0
		for (index, line) in lines.enumerated() {
			let next = location + lineLengths[index]
			if selection.location < next {
				return SelectionAnchor(
					lineNumber: line.lineNumber,
					offset: selection.location - location,
					length: selection.length
				)
			}
			location = next
		}
		return nil
	}

	private func restoreSelection(_ anchor: SelectionAnchor?) {
		guard let anchor, let storage = textView.textStorage else { return }
		var restored = NSRange(location: 0, length: 0)
		if let range = range(ofLine: anchor.lineNumber), anchor.offset <= range.length {
			let location = min(range.location + anchor.offset, storage.length)
			restored = NSRange(location: location, length: min(anchor.length, storage.length - location))
		}
		isAdjustingSelection = true
		textView.setSelectedRange(restored)
		isAdjustingSelection = false
		owner?.selection = restored.length > 0
			? (textView.string as NSString).substring(with: restored)
			: nil
	}

	/// Whether the reader is at the end, judged by the part of the clip view
	/// the input bar does not cover.
	private var isNearBottom: Bool {
		let clip = scrollView.contentView
		let visibleBottom = clip.bounds.maxY - scrollView.contentInsets.bottom
		return visibleBottom >= textView.frame.maxY - 40
	}

	private func effectiveFont(_ controller: ThemeController) -> NSFont {
		let font = controller.font
		return NSFont(name: font.fontName, size: font.pointSize * textScale)
			?? NSFont.systemFont(ofSize: font.pointSize * textScale)
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

// MARK: - Rendering a line

private extension NativeTranscriptView {
	func render(_ line: TranscriptLine) -> NSAttributedString {
		let result = NSMutableAttributedString()
		for marker in line.markers {
			result.append(render(marker, lineNumber: line.lineNumber))
		}
		let controller = SharedApplication.sharedThemeController()
		let theme = controller.theme
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineSpacing = theme.lineSpacing
		paragraph.paragraphSpacing = theme.messageSpacing
		paragraph.firstLineHeadIndent = theme.horizontalPadding
		paragraph.headIndent = theme.horizontalPadding
		paragraph.tailIndent = -theme.horizontalPadding

		let metadata = metadataAttributes(for: line, paragraph: paragraph)
		if theme.layout == .bubbles {
			let header = "\(line.timestamp)  \(line.formattedNickname)\n"
			result.append(NSAttributedString(string: header, attributes: metadata))
		} else {
			result.append(NSAttributedString(string: "\(line.timestamp)  ", attributes: metadata))
			if line.formattedNickname.isEmpty == false {
				result.append(NSAttributedString(
					string: "\(line.formattedNickname)  ",
					attributes: nicknameAttributes(for: line, paragraph: paragraph)
				))
			}
		}

		for run in line.body.runs {
			result.append(NSAttributedString(
				string: run.text,
				attributes: runAttributes(run, line: line, paragraph: paragraph)
			))
		}
		appendDeliveryAndReactions(for: line, to: result, paragraph: paragraph)
		for image in inlineImages[line.lineNumber] ?? [] {
			append(image, to: result, paragraph: paragraph)
		}
		result.append(NSAttributedString(string: "\n", attributes: metadata))
		return result
	}

	func metadataAttributes(
		for line: TranscriptLine,
		paragraph: NSParagraphStyle
	) -> [NSAttributedString.Key: Any] {
		let controller = SharedApplication.sharedThemeController()
		let palette = controller.theme.palette
		var attributes = lineAttributes(for: line).merging([
			.font: NSFont.systemFont(ofSize: max(9, effectiveFont(controller).pointSize - 1)),
			.foregroundColor: controller.resolved(palette.secondaryText),
			.paragraphStyle: paragraph,
		]) { _, new in new }
		if let background = bubbleBackground(for: line) {
			attributes[.backgroundColor] = background
		}
		return attributes
	}

	func nicknameAttributes(
		for line: TranscriptLine,
		paragraph: NSParagraphStyle
	) -> [NSAttributedString.Key: Any] {
		let controller = SharedApplication.sharedThemeController()
		let palette = controller.theme.palette
		let fallback = line.memberType == .localUser ? palette.localNickname : palette.remoteNickname
		let color = Preferences.Messages.disableNicknameColorHashing.value
			? controller.resolved(fallback)
			: nicknameColor(for: line.nickname ?? "")
		var attributes = lineAttributes(for: line).merging([
			.font: NSFontManager.shared.convert(effectiveFont(controller), toHaveTrait: .boldFontMask),
			.foregroundColor: color,
			.paragraphStyle: paragraph,
			.transcriptNickname: line.nickname ?? "",
			.transcriptAction: "nickname:\(line.nickname ?? "")",
		]) { _, new in new }
		if let background = bubbleBackground(for: line) {
			attributes[.backgroundColor] = background
		}
		return attributes
	}

	func runAttributes(
		_ run: TranscriptTextRun,
		line: TranscriptLine,
		paragraph: NSParagraphStyle
	) -> [NSAttributedString.Key: Any] {
		let controller = SharedApplication.sharedThemeController()
		let palette = controller.theme.palette
		var attributes = lineAttributes(for: line)
		var font = effectiveFont(controller)
		if run.traits
			.contains(.monospace)
		{
			font = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
		}
		if run.traits.contains(.bold) {
			font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
		}
		if run.traits.contains(.italic) {
			font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
		}
		attributes[.font] = font
		attributes[.paragraphStyle] = paragraph
		attributes[.foregroundColor] = resolved(run.foreground) ?? controller.resolved(
			line.lineType == .privateMessage || line.lineType == .action ? palette.primaryText : palette.eventText
		)
		if let background = resolved(run.background) {
			attributes[.backgroundColor] = background
		}
		if run.traits.contains(.highlighted) {
			attributes[.backgroundColor] = controller.resolved(palette.highlightBackground)
			attributes[.foregroundColor] = controller.resolved(palette.highlightText)
		}
		if run.traits.contains(.strikethrough) {
			attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
		}
		if run.traits.contains(.underline) {
			attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
		}
		if let background = bubbleBackground(for: line) {
			attributes[.backgroundColor] = background
		}
		switch run.action {
		case let .link(url):
			attributes[.link] = url
			attributes[.foregroundColor] = controller.resolved(palette.link)
		case let .channel(name):
			attributes[.transcriptAction] = "channel:\(name)"
			attributes[.foregroundColor] = controller.resolved(palette.link)
		case let .nickname(name):
			attributes[.transcriptAction] = "nickname:\(name)"
			attributes[.transcriptNickname] = name
			attributes[.foregroundColor] = nicknameColor(for: name)
		case nil:
			break
		}
		return attributes
	}

	/// A nickname's colour, remembered for the batch being rendered. Resolving
	/// one reads the pinned-colour dictionary out of the defaults store, and a
	/// batch of lines asks for the same few names repeatedly.
	func nicknameColor(for nickname: String) -> NSColor {
		if let cached = nicknameColors[nickname] {
			return cached
		}
		let color = UserNicknameColorStyleGenerator.color(for: nickname)
		nicknameColors[nickname] = color
		return color
	}

	func bubbleBackground(for line: TranscriptLine) -> NSColor? {
		let controller = SharedApplication.sharedThemeController()
		guard controller.theme.layout == .bubbles else { return nil }
		let palette = controller.theme.palette
		let pair = line.memberType == .localUser ? palette.bubbleOutgoing : palette.bubbleIncoming
		return controller.resolved(pair)
	}

	func lineAttributes(for line: TranscriptLine) -> [NSAttributedString.Key: Any] {
		[
			.transcriptLineNumber: line.lineNumber,
			.transcriptLineType: line.lineTypeString,
			.transcriptMessageIdentifier: line.messageIdentifier ?? "",
			.transcriptExcerpt: line.body.plainText,
		]
	}

	func appendDeliveryAndReactions(
		for line: TranscriptLine,
		to result: NSMutableAttributedString,
		paragraph: NSParagraphStyle
	) {
		let controller = SharedApplication.sharedThemeController()
		let palette = controller.theme.palette
		var details: [String] = []
		switch line.deliveryState {
		case .pending: details.append(TranscriptThemeStrings.pending)
		case .delivered: details.append(TranscriptThemeStrings.delivered)
		case .failed:
			details.append(
				TranscriptThemeStrings.failed + (line.deliveryFailureReason.map { ": \($0)" } ?? "")
			)
		case .none: break
		}
		for emoji in line.reactions.keys.sorted() {
			details.append("\(emoji) \(line.reactions[emoji]?.count ?? 0)")
		}
		guard details.isEmpty == false else { return }
		var attributes = lineAttributes(for: line)
		attributes[.font] = NSFont.systemFont(ofSize: max(9, effectiveFont(controller).pointSize - 1))
		attributes[.foregroundColor] = line.deliveryState == .failed
			? controller.resolved(palette.failure)
			: controller.resolved(palette.secondaryText)
		attributes[.paragraphStyle] = paragraph
		result.append(NSAttributedString(string: "  \(details.joined(separator: "  "))", attributes: attributes))
	}

	func append(
		_ inlineImage: TranscriptInlineImage,
		to result: NSMutableAttributedString,
		paragraph: NSParagraphStyle
	) {
		guard let image = NSImage(data: inlineImage.imageData) else { return }
		let maxSize = NSSize(
			width: min(480, max(120, textView.bounds.width - 40)),
			height: 320
		)
		let scale = min(1, maxSize.width / image.size.width, maxSize.height / image.size.height)
		image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
		let attachment = NSTextAttachment()
		attachment.image = image
		let attachmentString = NSMutableAttributedString(string: "\n")
		attachmentString.append(NSAttributedString(attachment: attachment))
		attachmentString.addAttribute(.paragraphStyle, value: paragraph, range: attachmentString.fullRange)
		result.append(attachmentString)
	}

	func attributedTopic(_ topic: String) -> NSAttributedString {
		let controller = SharedApplication.sharedThemeController()
		let palette = controller.theme.palette
		let result = NSMutableAttributedString(string: topic, attributes: [
			.font: NSFont.preferredFont(forTextStyle: .body),
			.foregroundColor: controller.resolved(palette.primaryText),
		])
		for link in LinkParser.locateLinks(in: topic)
			where LogRenderer.isSafeLink(link.stringValue)
		{
			guard let url = URL(string: link.stringValue), NSMaxRange(link.range) <= result.length else {
				continue
			}
			result.addAttributes([
				.link: url,
				.foregroundColor: controller.resolved(palette.link),
				.underlineStyle: NSUnderlineStyle.single.rawValue,
			], range: link.range)
		}
		return result
	}

	func resolved(_ color: TranscriptRunColor?) -> NSColor? {
		switch color {
		case let .palette(index):
			guard NSColor.formatterColors.indices.contains(index) else { return nil }
			return NSColor.formatterColors[index]
		case let .rgb(components):
			return components.color
		case nil:
			return nil
		}
	}
}

private extension NativeTranscriptView {
	func render(_ marker: TranscriptMarker, lineNumber: String) -> NSAttributedString {
		let controller = SharedApplication.sharedThemeController()
		let palette = controller.theme.palette
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .center
		let text: String
		let color: NSColor
		let font: NSFont
		switch marker {
		case let .date(value):
			text = value
			color = controller.resolved(palette.secondaryText)
			font = NSFont.systemFont(
				ofSize: max(9, effectiveFont(controller).pointSize - 1),
				weight: .medium
			)
			paragraph.paragraphSpacing = 6
		case let .currentSession(value):
			text = value
			color = controller.resolved(palette.secondaryText)
			font = NSFont.systemFont(
				ofSize: max(9, effectiveFont(controller).pointSize - 1),
				weight: .medium
			)
			paragraph.paragraphSpacingBefore = 5
			paragraph.paragraphSpacing = 6
			paragraph.textBlocks = [separatorBlock(
				ruleColor: color.withAlphaComponent(0.22),
				topPadding: 5
			)]
		case .unread:
			// The previous Simplified theme used only a quiet accent hairline.
			// Keeping the caption out of the transcript prevents an unread
			// boundary from competing with actual messages.
			text = "\u{200B}"
			color = .clear
			font = NSFont.systemFont(ofSize: 1)
			paragraph.paragraphSpacingBefore = 5
			paragraph.paragraphSpacing = 5
			paragraph.textBlocks = [separatorBlock(
				ruleColor: controller.resolved(palette.unreadMarker).withAlphaComponent(0.6)
			)]
		}
		return NSAttributedString(string: "\(text)\n", attributes: [
			.font: font,
			.foregroundColor: color,
			.paragraphStyle: paragraph,
			.transcriptLineNumber: lineNumber,
		])
	}

	func separatorBlock(ruleColor: NSColor, topPadding: CGFloat = 0) -> NSTextBlock {
		let block = NSTextBlock()
		block.setContentWidth(100, type: .percentageValueType)
		block.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
		block.setBorderColor(ruleColor, for: .minY)
		if topPadding > 0 {
			block.setWidth(topPadding, type: .absoluteValueType, for: .padding, edge: .minY)
		}
		return block
	}
}

@MainActor
public final class LogView: NSObject {
	public weak var viewController: LogController?
	public var contextMenuTarget = LogPolicyTarget()
	public var selection: String?

	private lazy var nativeView = NativeTranscriptView(owner: self)
	fileprivate let policy = LogPolicy()
	private let notifications = NotificationSubscriptions()

	@available(*, unavailable, message: "Use init(viewController:)")
	override public init() {
		fatalError("Use init(viewController:)")
	}

	public init(viewController: LogController) {
		self.viewController = viewController
		super.init()
		_ = nativeView
		for name in [Notification.Name.themeWasModified, .themeAppearanceChanged] {
			notifications.observe(name) { [weak self] _ in self?.nativeView.applyTheme() }
		}
	}

	public var hasSelection: Bool {
		selection?.isEmpty == false
	}

	public var view: NSView {
		nativeView
	}

	public func clearSelection() {
		nativeView.clearSelection()
	}

	public func takeContextMenuTarget() -> LogPolicyTarget {
		defer { contextMenuTarget = LogPolicyTarget() }
		return contextMenuTarget
	}

	public func copySelection() {
		nativeView.copySelection()
	}

	public func printContent() {
		guard let window = nativeView.window else { return }
		let operation = NSPrintOperation(view: nativeView.printableView, printInfo: .shared)
		operation.showsPrintPanel = true
		operation.showsProgressPanel = true
		operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
	}

	public func keyDown(_ event: NSEvent, in _: NSView) -> Bool {
		let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		guard modifiers.isDisjoint(with: [.command, .option, .control]) else { return false }
		viewController?.logViewKeyDown(event)
		return true
	}

	public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		guard let fileURL = NSURL(from: sender.draggingPasteboard) as URL?, fileURL.isFileURL else {
			return false
		}
		viewController?.logViewReceivedDrop(withFile: fileURL.path)
		return true
	}

	public func findString(_ searchString: String, movingForward: Bool) {
		nativeView.find(searchString, movingForward: movingForward)
	}

	func prepareContextTarget(at point: NSPoint) {
		contextMenuTarget = nativeView.contextTarget(at: point)
	}

	func contextMenu(defaultItems: [NSMenuItem]) -> NSMenu {
		policy.contextMenu(for: self, defaultMenuItems: defaultItems)
	}

	func setTopic(_ topic: String?) {
		nativeView.setTopic(topic)
	}

	func setBottomContentInset(_ inset: CGFloat) {
		nativeView.setBottomContentInset(inset)
	}

	func setBufferLimit(_ limit: Int) {
		nativeView.setBufferLimit(limit)
	}

	func setTextScale(_ scale: CGFloat) {
		nativeView.setTextScale(scale)
	}

	func replaceLines(_ lines: [TranscriptLine]) {
		nativeView.replace(with: lines)
	}

	func appendLines(_ lines: [TranscriptLine]) {
		nativeView.append(lines)
	}

	func prependLines(_ lines: [TranscriptLine]) {
		nativeView.prepend(lines)
	}

	func clearLines() {
		nativeView.clear()
	}

	func updateDelivery(_ update: TranscriptDeliveryUpdate) {
		nativeView.updateDelivery(update)
	}

	func updateReactions(_ reactions: [String: [String]], messageIdentifier: String) {
		nativeView.updateReactions(reactions, messageIdentifier: messageIdentifier)
	}

	func setUnreadMarker(_ mark: TranscriptScrollbackMark) {
		nativeView.setUnreadMarker(mark)
	}

	func jump(to lineNumber: String) -> Bool {
		nativeView.jump(to: lineNumber)
	}

	func scrollToBottom() {
		nativeView.scrollToBottom()
	}

	func addInlineImage(_ image: TranscriptInlineImage) {
		nativeView.addInlineImage(image)
	}

	func applyTheme() {
		nativeView.applyTheme()
	}
}

// MARK: - Topic disclosure

private struct TopicDisclosureButton: View {
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

private extension NativeTranscriptView {
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

private extension NativeTranscriptView {
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

private extension TranscriptLine {
	var lineTypeString: String {
		LogLine.string(for: lineType) ?? ""
	}
}

private extension NSAttributedString {
	var fullRange: NSRange {
		NSRange(location: 0, length: length)
	}
}
