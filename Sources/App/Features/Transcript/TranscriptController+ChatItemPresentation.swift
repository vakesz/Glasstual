// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** A transcript controller is the view a chat item is drawn into. Every
 requirement already existed on the class; the protocol is what lets the IRC
 layer hold one without depending on the concrete `TranscriptController`. */
extension TranscriptController: ChatItemPresentation {
	var presentationIdentifier: String {
		uniqueIdentifier
	}

	func lastRenderedLineDate() -> Date? {
		backingView?.displayedLines.filter {
			ChatHistoryPolicy.marksReadPosition(lineType: $0.lineType, messageIdentifier: $0.messageIdentifier)
		}.map(\.receivedAt).max()
	}

	/** Both conversation seams answer from the union of what the view is showing
	 and what it has been handed but not applied yet. A line moves from the second
	 to the first synchronously on the main actor, so neither holds it twice.

	 Lines loaded from storage are in neither list, which is why `Client`
	 combines this with the historic log's index: history seeding fills that index
	 synchronously, so it already accounts for the scrollback. */
	func newestConversationLineDate() -> Date? {
		let displayed = backingView?.displayedLines.filter(\.lineType.isConversation).map(\.receivedAt) ?? []
		let awaiting = linesAwaitingRender.filter(\.lineType.isConversation).map(\.receivedAt)

		return (displayed + awaiting).max()
	}

	func conversationLineCount(after date: Date) -> Int {
		let displayed = backingView?.displayedLines
			.count { $0.lineType.isConversation && $0.receivedAt > date } ?? 0

		return displayed + linesAwaitingRender.count { $0.lineType.isConversation && $0.receivedAt > date }
	}

	func lastPrintedLine() -> LogLine? {
		lastLine()
	}
}
