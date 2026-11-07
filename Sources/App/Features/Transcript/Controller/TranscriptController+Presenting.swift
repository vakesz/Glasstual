// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What the IRC layer sees of a transcript. Every requirement is answered by
 the controller's own state; the protocol is what lets a chat item hold one
 without depending on the concrete `TranscriptController`. */
extension TranscriptController {
	var presentationIdentifier: String {
		uniqueIdentifier
	}

	/// The newest line this view printed. The IRC layer consults it when it
	/// decides what history to ask the server for.
	func lastPrintedLine() -> ChatLine? {
		lastLineStorage
	}

	func lastRenderedLineDate() -> Date? {
		backingView?.displayedLines.filter(\.lineType.isConversation).compactMap(\.serverTimestamp).max()
	}

	/** Both conversation seams answer from the union of what the view is showing
	 and what it has been handed but not applied yet. A line moves from the second
	 to the first synchronously on the main actor, so neither holds it twice.

	 Lines loaded from storage are in neither list, which is why
	 `newestKnownConversationLineDate(for:)` combines this with the scrollback's
	 duplicate index: history seeding fills that index synchronously, so it already
	 accounts for the scrollback. */
	func newestConversationLineDate() -> Date? {
		let displayed = backingView?.displayedLines.filter(\.lineType.isConversation).map(\.receivedAt) ?? []
		let awaiting = awaitingRender.lines.filter(\.lineType.isConversation).map(\.receivedAt)

		return (displayed + awaiting).max()
	}

	/** The newest line the person sent that the view holds and has not deleted.
	 Lines queued for rendering are newer than the displayed ones, so they are
	 read first. The scan stops at the first match and reads only what the
	 view keeps, never stored history. */
	func newestMessageIdentifier(sentBy isSender: (String) -> Bool) -> String? {
		func identifier(
			of kind: ChatLineKind, nickname: String?, messageIdentifier: String?
		) -> String? {
			guard kind.isRedactableMessage, let nickname, isSender(nickname),
			      let messageIdentifier, messageIdentifier.isEmpty == false,
			      redactions.contains(messageIdentifier) == false
			else { return nil }

			return messageIdentifier
		}

		for line in awaitingRender.lines.reversed() {
			if let found = identifier(of: line.lineType, nickname: line.nickname, messageIdentifier: line.messageIdentifier) {
				return found
			}
		}
		for row in (backingView?.displayedLines ?? []).reversed() {
			if let found = identifier(of: row.lineType, nickname: row.nickname, messageIdentifier: row.messageIdentifier) {
				return found
			}
		}
		return nil
	}

	func conversationLineCount(after date: Date) -> Int {
		let displayed = backingView?.displayedLines
			.count { $0.lineType.isConversation && $0.receivedAt > date } ?? 0

		return displayed + awaitingRender.lines.count { $0.lineType.isConversation && $0.receivedAt > date }
	}
}
