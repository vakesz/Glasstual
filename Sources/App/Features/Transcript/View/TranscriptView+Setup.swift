// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

extension TranscriptView {
	func configure() {
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
		if viewController?.associatedConversation != nil {
			notifications.observe(ConversationConfigWasUpdated.self) { [weak self] message in
				guard let self, message.subject === viewController?.associatedConversation else { return }
				reloadFolding()
				updateAccessibilityDescription()
			}
		}
		if viewController?.associatedSession != nil {
			notifications.observe(ServerSessionConfigWasUpdated.self) { [weak self] message in
				guard let self, message.subject === viewController?.associatedSession else { return }
				reloadFolding()
				updateAccessibilityDescription()
			}
		}
	}

	func configureTopicBar() {
		topicBar.canModifyTopic = { [weak self] in self?.canModifyTopic == true }
		topicBar.onModifyTopic = { [weak self] in self?.commands.topicBarDoubleClicked() }
		topicBar.onOpenLink = { [weak self] in self?.commands.openWebpage($0) }
	}

	func configureTextView() {
		textView.delegate = self
		/* The separators are layout fragments of their own; see
		 `TranscriptRuleLayoutFragment`. */
		textView.textLayoutManager?.delegate = self
		textView.isEditable = false
		textView.isSelectable = true
		textView.setAccessibilityIdentifier("channel-transcript")
		updateAccessibilityDescription()
		/* VoiceOver reaches the messages, the mentions, the links and the days
		 by rotor, the structure a single text view otherwise hides. */
		textView.setAccessibilityCustomRotors(makeAccessibilityRotors())
		textView.isRichText = true
		textView.importsGraphics = false
		/* The find bar is the transcript's own, inline above the text, which is
		 where macOS puts search in a document window. */
		textView.usesFindBar = true
		textView.isIncrementalSearchingEnabled = true
		textView.isAutomaticLinkDetectionEnabled = false
		textView.isAutomaticDataDetectionEnabled = false
		textView.drawsBackground = false
		/* Rings only the image placeholder under the caret; see the text
		 view's focus ring mask. */
		textView.focusRingType = .exterior
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

	func configureScrollView() {
		scrollView.documentView = textView
		/* The insets are this view's, from the first layout on. The scroll view
		 runs under the toolbar and the topic bar, so the reader's text can pass
		 beneath the Liquid Glass toolbar the way it does in Mail and Messages;
		 the top inset is the safe area plus the topic bar, the bottom inset the
		 input bar, and both are set here rather than by AppKit's automatic
		 adjustment, which knows about neither the topic bar nor the input bar.
		 Turning it off at construction keeps the view from ever running with
		 both. */
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
		notifications.observe(.NSSystemTimeZoneDidChange) { [weak self] _ in
			self?.reloadClock()
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

	func configureJumpToLatestButton() {
		/* A reader who has scrolled away has no way back to the end but the
		 menu, and the transcript is where they are looking. */
		jumpToLatest.sizingOptions = .intrinsicContentSize
		jumpToLatest.translatesAutoresizingMaskIntoConstraints = false
		jumpToLatest.isHidden = true
		jumpToLatest.rootView = TranscriptJumpToLatestButton { [weak self] in
			guard let controller = self?.viewController else {
				self?.scrollToBottom()
				return
			}
			controller.jumpToPresent()
		}
	}

	func addSubviewsAndActivateConstraints() {
		toolbarBackdrop.wantsLayer = true
		toolbarBackdrop.translatesAutoresizingMaskIntoConstraints = false
		addSubview(scrollView)
		addSubview(toolbarBackdrop)
		addSubview(topicBar)
		addSubview(jumpToLatest)
		/* The topic bar is pinned under the toolbar, over the text: the
		 transcript scrolls beneath both, and the top content inset keeps the
		 first line clear of them. Both are opaque, in the transcript's
		 background, so the text passing beneath never shows through the window
		 title or the topic. */
		NSLayoutConstraint.activate([
			toolbarBackdrop.topAnchor.constraint(equalTo: topAnchor),
			toolbarBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
			toolbarBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
			toolbarBackdrop.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
			topicBar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
			topicBar.leadingAnchor.constraint(equalTo: leadingAnchor),
			topicBar.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
			jumpToLatest.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -UISpacing.loose),
		])
		jumpToLatestBottomConstraint = jumpToLatest.bottomAnchor.constraint(
			equalTo: bottomAnchor,
			constant: -UISpacing.wide
		)
		jumpToLatestBottomConstraint?.isActive = true
	}

	override func layout() {
		super.layout()
		updateTopContentInset()
		guard window != nil, !isHiddenOrHasHiddenAncestor, editDepth == 0 else { return }
		reflowInlineImages()
		textView.updateBottomAlignment()
		if scrollsToBottomOnLayout {
			/* The scroll view tiles in its own pass, after this one; forcing it
			 here gives the clip its height now, so the scroll lands in the same
			 layout instead of a notification later. */
			scrollView.layoutSubtreeIfNeeded()
			scrollToBottomIfPending()
		}
	}

	override func viewDidEndLiveResize() {
		super.viewDidEndLiveResize()
		reflowInlineImages()
	}

	/** Draws the inline images again when the column they are sized to has
	 changed width.

	 An image is sized when its line is drawn, from the width the text view has
	 then; a transcript that is resized afterwards, or that was not yet laid out
	 when the image arrived, keeps pictures sized to a column that is gone. A
	 live resize waits for its end rather than redrawing every frame, and only a
	 change in the widest size an image may take redraws at all, so a window
	 wider than the box costs nothing. */
	func reflowInlineImages() {
		guard inLiveResize == false, editDepth == 0, document.inlineMedia.isEmpty == false else { return }
		scrollView.layoutSubtreeIfNeeded()
		let width = TranscriptMetrics.inlineImageMaximumWidth(forTextViewWidth: textView.bounds.width)
		guard width != renderedInlineImageWidth else { return }
		performEditingBatch {
			for lineNumber in document.inlineMedia.keys {
				if let index = document.index(ofLine: lineNumber) {
					refresh(at: index)
				}
			}
		}
		renderedInlineImageWidth = width
	}

	// Starts a batch of renders: the colours resolved for the last one, and the
	// pinned-colour table they were resolved against, both belong to it alone.
}
