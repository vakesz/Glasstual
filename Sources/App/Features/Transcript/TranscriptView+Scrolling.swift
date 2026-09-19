// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/** Where the reader is looking. The transcript either follows the newest line
 or holds the place the reader scrolled to, and every measurement here is
 taken against the part of the clip view the floating input bar does not
 cover. */
extension TranscriptView {
	/** Performs the scroll a return to the window asked for, once the clip view
	 has a height to scroll within. The first layout after the view lands in a
	 window runs before the scroll view has tiled, so the clip is still empty
	 then; the clip's frame change afterwards is what says it is ready. */
	func scrollToBottomIfPending() {
		guard scrollsToBottomOnLayout, scrollView.contentView.bounds.height > 0 else { return }
		scrollsToBottomOnLayout = false
		scrollToBottom()
	}

	func documentHeightDidChange() {
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
	 reader opened the conversation for. The scroll waits for the first layout in
	 the window, where the clip view has its real height. */
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		/* A popover cannot stay anchored to a view that is in no window, and the
		 view that comes back is showing a conversation it is no longer about. */
		if window == nil {
			closeMemberInformation()
			closeReactionPicker()
		}
		guard window != nil, followsBottom else { return }
		scrollsToBottomOnLayout = true
		needsLayout = true
	}

	/// The space beneath the transcript that something else is drawn over.
	func setBottomContentInset(_ inset: CGFloat) {
		guard scrollView.contentInsets.bottom != inset else { return }
		scrollView.contentInsets.bottom = inset
		scrollView.scrollerInsets.bottom = inset
		/* The button floats over the transcript, so it clears whatever is drawn
		 over the foot of it the same way the text does. */
		jumpToLatestBottomConstraint?.constant = -(inset + UISpacing.wide)
		needsLayout = true
	}

	/// The button is offered exactly while the reader is somewhere other than
	/// the end of a transcript that has an end to go to.
	func updateJumpToLatestVisibility() {
		jumpToLatest.isHidden = followsBottom || document.isEmpty
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
		ensureLayoutForTail()
		textView.sizeToFit()
		let insets = scrollView.contentInsets
		let targetY = textView.frame.maxY + insets.bottom - clip.bounds.height
		clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: max(-insets.top, targetY)))
		scrollView.reflectScrolledClipView(clip)
		noteViewportMovedByView()
	}

	/** Lays out the end of the document, which is the part a scroll to the end
	 lands in.

	 TextKit 2 lays out on demand and estimates the height of what it has not
	 reached, so the rest of a long scrollback is left to the viewport as it
	 comes into view. Laying out the whole document here made every appended
	 batch cost the entire transcript; the estimate it refines later moves the
	 document's height, which ``documentHeightDidChange()`` already follows. */
	func ensureLayoutForTail() {
		guard let layoutManager = textView.textLayoutManager,
		      let contentManager = layoutManager.textContentManager,
		      let lastStart = document.lineStarts.dropLast().last,
		      let tailStart = contentManager.location(contentManager.documentRange.location, offsetBy: lastStart),
		      let tail = NSTextRange(location: tailStart, end: contentManager.documentRange.endLocation)
		else { return }
		layoutManager.ensureLayout(for: tail)
	}

	/** Records a scroll this view made itself as the place the reader already is.

	 The clip's bounds notifications arrive on a later turn and cannot say who
	 moved the viewport, and only a reader moving towards the top asks for
	 history. Keeping an edit's own scroll — text trimmed or inserted above the
	 viewport, a rebuild, a restored anchor — from reading as that is what stops
	 a prepend or a trim from fetching the next page on the reader's behalf. */
	func noteViewportMovedByView() {
		lastVisibleTop = scrollView.contentView.bounds.minY
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

	/// Whether the reader is at the end, judged by the part of the clip view
	/// the input bar does not cover.
	var isNearBottom: Bool {
		let clip = scrollView.contentView
		let visibleBottom = clip.bounds.maxY - scrollView.contentInsets.bottom
		return visibleBottom >= textView.frame.maxY - TranscriptMetrics.followBottomSlack
	}
}
