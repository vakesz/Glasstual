// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension TranscriptController {
	func reloadTheme() {
		if !terminating {
			backingView?.applyTheme()
		}
	}

	func jumpToCurrentSession() {
		for lineNumber in [transcriptSessionBoundary.firstCurrentSessionLineNumber,
		                   newestLineNumberFromPreviousSession, oldestLineNumber].compactMap(\.self)
			where backingView?.jump(to: lineNumber) == true
		{
			return
		}
	}

	/// The end of the conversation: the bottom of what is drawn, or, when a
	/// window of old history is showing, the live end that window left.
	func jumpToPresent() {
		if historyRecovery.isDetachedFromLive {
			returnToLive()
		} else {
			backingView?.scrollToBottom()
		}
	}

	func jump(toLine lineNumber: String, completionHandler: ((Bool) -> Void)? = nil) {
		let successful = backingView?.jump(to: lineNumber) == true
		completionHandler?(successful)
	}

	func setTopic(_ topic: String?) {
		guard !terminating else { return }
		backingView?.setTopic(topic?.isEmpty == false ? topic : nil)
	}

	/** Redraws the topic bar's mode caption from the channel as it stands now.

	 The modes are not pushed to the view the way the topic is: nothing in the
	 IRC layer addresses one transcript when they change. The bar is refreshed
	 where the change already surfaces — the mode line landing in this view, the
	 view coming back on screen, and the window retitling this item. */
	func refreshTopicBar() {
		guard !terminating else { return }
		backingView?.refreshTopicBar()
	}

	func mark() {
		let mark = (newestLineNumber ?? lastLineStorage?.uniqueIdentifier).map(UnreadMarker.line) ?? .latest
		transcriptProjection.setMark(mark)
		backingView?.setUnreadMarker(mark)
	}

	/** Puts the boundary above a line that is being printed unseen.

	 The line is named rather than looked up: it has not rendered yet, and
	 neither may the lines printed just before it, so "the newest line drawn"
	 is wherever rendering happens to have reached. The boundary is drawn when
	 the line is, by ``settleUnreadMarker(onDrawing:)``. */
	func mark(before lineIdentifier: String) {
		let mark = UnreadMarker.before(lineIdentifier)
		transcriptProjection.setMark(mark)
		backingView?.setUnreadMarker(mark)
	}

	/// The line a pending boundary waits for has been drawn: the boundary
	/// lands on it and from here on is kept the way any marked line is.
	func settleUnreadMarker(onDrawing lineIdentifier: String) {
		guard transcriptProjection.mark == .before(lineIdentifier) else { return }
		let mark = UnreadMarker.line(lineIdentifier)
		transcriptProjection.setMark(mark)
		backingView?.setUnreadMarker(mark)
	}

	func mark(at date: Date) {
		transcriptProjection.setMark(.after(date))
		backingView?.setUnreadMarker(.after(date))
	}

	func goToMark() {
		switch transcriptProjection.mark {
		case .none: break
		case .latest: jumpToPresent()
		case let .line(identifier):
			jump(toLine: backingView?.displayedLines
				.first(where: { $0.matches(identifier: identifier) })?.lineNumber
				?? oldestLineNumber ?? identifier)
		case let .before(identifier):
			if let line = backingView?.displayedLines.first(where: { $0.matches(identifier: identifier) })?.lineNumber {
				jump(toLine: line)
			}
		case let .after(date):
			if let line = backingView?.displayedLines
				.first(where: { $0.receivedAt >= date && $0.lineType.isConversation })?.lineNumber
			{
				jump(toLine: line)
			}
		}
	}

	func notifyDidBecomeVisible() {
		refreshTopicBar()
		maybeReloadHistory()
	}

	func updateTextScale() {
		guard let attachedWindow else {
			return
		}
		backingView?.setTextScale(attachedWindow.textSizeMultiplier)
	}

	func changeScrollbackLimit() {
		let policy = bufferPolicy
		transcriptProjection.setCapacity(policy.hardLimit)
		backingView?.setBufferLimit(policy.hardLimit)
		forgetRetiredProjectionMessages()
	}

	/// The view dropped these lines.
	func notifyLinesWereRemoved(_ lineNumbers: [String]) {
		guard !terminating else {
			return
		}
		transcriptProjection.retireDisplayedLines(lineNumbers)
		forgetRetiredProjectionMessages()
		highlightCursor.forget(lineNumbers)
	}

	func nextHighlight() {
		visitHighlight(offset: 1)
	}

	func previousHighlight() {
		visitHighlight(offset: -1)
	}

	/// The highlights in the order they are drawn, for the commands that step
	/// through them. Walked on demand, once per keystroke.
	private var highlightedLineNumbers: [String] {
		backingView?.displayedLines.compactMap { $0.body.isHighlight ? $0.lineNumber : nil } ?? []
	}

	private func visitHighlight(offset: Int) {
		guard viewIsLoaded, !terminating,
		      let target = highlightCursor.step(by: offset, through: highlightedLineNumbers)
		else {
			return
		}
		jump(toLine: target)
	}
}
