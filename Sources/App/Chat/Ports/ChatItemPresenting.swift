// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The view a single sidebar item is drawn into, as the protocol layer sees it.

 The item holds this weakly and does not create it: the main window's transcript
 registry owns the controller and installs itself here. When there is no window
 — tests, teardown — the reference is simply `nil` and printing is a no-op. */
@MainActor
protocol ChatItemPresenting: AnyObject {
	/** Main actor: the only readers are the two termination logs
	 (`Conversation.prepareForApplicationTermination`, its session's counterpart),
	 which already run there, so the identifier never leaves the main actor. */
	var presentationIdentifier: String { get }

	func print(_ chatLine: ChatLine, completionBlock: PrintedLineCompletion?)
	/** Main actor: the newest printed line is the controller's own state, and
	 both callers (`Conversation.lastLine`, `ServerSession.lastLine`) are already
	 there. */
	func lastPrintedLine() -> ChatLine?
	/// The newest line on screen a read marker may be placed at: a conversation
	/// line the server stamped, per ``ChatHistoryPolicy/marksReadPosition(lineType:messageIdentifier:)``.
	func lastRenderedLineDate() -> Date?
	/** The newest line a person wrote that this view knows about, ignoring the
	 events the session narrates — a join, a mode, a topic. A line printed in this
	 turn counts, whether or not it has rendered yet.

	 A received read marker is answered against this: the burst a join prints is
	 stamped now, and none of it is news the badge should count. */
	func newestConversationLineDate() -> Date?
	/// How many of the view's conversation lines are newer than `date`, which is
	/// how many messages a read marker placed at `date` leaves unread.
	func conversationLineCount(after date: Date) -> Int
	func setTopic(_ topic: String?)

	func mark()
	func mark(at date: Date)
	func noteReaction(_ emoji: String, fromNickname nickname: String, toMessageIdentifier identifier: String)
	func updateDeliveryState(
		forLineNumber lineNumber: String,
		state: ChatLineDeliveryState,
		messageIdentifier: String?,
		reason: String?
	)
	/** Puts lines older than anything on screen above what the view shows.

	 "Earlier", not "replayed" or "scrollback": both sources arrive here. A
	 server history page comes in through this call, and so does a page read
	 back out of the local scrollback database. Nothing on this side of the seam
	 asks where a line came from — only that it belongs above the rest — so one
	 method serves both. */
	func prependEarlierChatLines(_ chatLines: [ChatLine])

	func tearDown(_ reason: ChatItemTeardown)
}

extension ChatItemPresenting {
	func lastRenderedLineDate() -> Date? {
		lastPrintedLine().flatMap {
			ChatHistoryPolicy.marksReadPosition(lineType: $0.lineType, messageIdentifier: $0.messageIdentifier)
				? $0.receivedAt : nil
		}
	}

	/// A presentation that keeps no history of its own answers from the last line
	/// it printed, which is a conversation line or nothing.
	func newestConversationLineDate() -> Date? {
		guard let chatLine = lastPrintedLine(), chatLine.lineType.isConversation else { return nil }

		return chatLine.receivedAt
	}

	func conversationLineCount(after date: Date) -> Int {
		newestConversationLineDate().map { $0 > date } == true ? 1 : 0
	}
}

/// Why a sidebar item's view is being torn down. One question the conformer
/// answers once, rather than three protocol members a caller has to match up
/// with the `preservingLocalData` flag elsewhere.
enum ChatItemTeardown {
	/// The application is quitting. The transcript is flushed and its log file
	/// closed; nothing is deleted.
	case applicationTermination
	/// The item is going away but is expected back — a transfer, an import —
	/// so its log file stays where it is.
	case preservingRemoval
	/// The item is going away for good, and its log file goes with it.
	case permanentRemoval
}
