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
			notifications.observe(.conversationConfigWasUpdated) { [weak self] notification in
				guard let self, let conversation = viewController?.associatedConversation,
				      notification.object as AnyObject? === conversation else { return }
				reloadFolding()
			}
		}
		if viewController?.associatedSession != nil {
			notifications.observe(.serverSessionConfigWasUpdated) { [weak self] notification in
				guard let self, let session = viewController?.associatedSession,
				      notification.object as AnyObject? === session else { return }
				reloadFolding()
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

	func configureScrollView() {
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

	func configureJumpToLatestButton() {
		/* A reader who has scrolled away has no way back to the end but the
		 menu, and the transcript is where they are looking. */
		jumpToLatest.sizingOptions = .intrinsicContentSize
		jumpToLatest.translatesAutoresizingMaskIntoConstraints = false
		jumpToLatest.isHidden = true
		jumpToLatest.rootView = TranscriptJumpToLatestButton { [weak self] in
			self?.scrollToBottom()
		}
	}

	func addSubviewsAndActivateConstraints() {
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

	// Starts a batch of renders: the colours resolved for the last one, and the
	// pinned-colour table they were resolved against, both belong to it alone.
}
