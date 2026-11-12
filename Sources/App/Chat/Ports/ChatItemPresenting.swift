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
	/// line carrying an explicit server timestamp.
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
	/** The message identifier of the newest line `isSender` accepts the nickname
	 of, among the lines this view has loaded: a message, action or notice that
	 carries an identifier and has not been deleted. `nil` when none is loaded.

	 Only the lines the view holds are read, never the stored history, so the
	 search is bounded by what the transcript keeps. */
	func newestMessageIdentifier(sentBy isSender: (String) -> Bool) -> String?
	func setTopic(_ topic: String?)

	func mark()
	/// Puts the unread boundary above the line with this identifier, which is
	/// about to be printed to a reader who is not looking.
	func mark(before lineIdentifier: String)
	func mark(at date: Date)
	func noteReaction(_ emoji: String, fromNickname nickname: String, toMessageIdentifier identifier: String)
	/** A message was deleted. The view replaces it with a placeholder, and the
	 history behind it overwrites the stored text.

	 A redaction can name a line that has not been drawn or stored yet, so the
	 conformer keeps it until that line arrives. */
	func noteRedaction(ofMessageIdentifier identifier: String)
	func replacePendingLine(_ line: ChatLine, reason: String?)
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

	/** Stores lines that belong somewhere in the middle of the history, such
	 as a filled gap, and draws each between the lines it falls between, by
	 the time it carries. They are older than what is drawn at the live end,
	 so they are not drawn there; one older than everything drawn is only
	 stored, and comes back with the older history. */
	func archiveRecoveredChatLines(_ chatLines: [ChatLine])
	/// Whether the conversation is missing messages the server still has.
	func noteMissingServerHistory(_ state: MissingServerHistoryState)
	/** Shows the message `identifier` names, fetching it from the server when
	 it is not stored, and says so in the conversation if it cannot. Returns
	 whether the presentation took the request. */
	func revealMessage(withIdentifier identifier: String) -> Bool

	func tearDown(_ reason: ChatItemTeardown)
}

extension ChatItemPresenting {
	/// A presentation that draws no messages has nothing to replace.
	func noteRedaction(ofMessageIdentifier _: String) {}

	/// A presentation without stored history has nowhere to put them.
	func archiveRecoveredChatLines(_: [ChatLine]) {}

	/// A presentation without a history banner has nothing to show.
	func noteMissingServerHistory(_: MissingServerHistoryState) {}

	/// A presentation without stored history cannot show one message of it.
	func revealMessage(withIdentifier _: String) -> Bool {
		false
	}

	func replacePendingLine(_ line: ChatLine, reason: String?) {
		updateDeliveryState(forLineNumber: line.uniqueIdentifier, state: line.deliveryState,
		                    messageIdentifier: line.messageIdentifier, reason: reason)
	}

	func lastRenderedLineDate() -> Date? {
		lastPrintedLine()?.readMarkerTimestamp
	}

	/// A presentation that keeps no history of its own answers from the last line
	/// it printed, which is a conversation line or nothing.
	func newestConversationLineDate() -> Date? {
		guard let chatLine = lastPrintedLine(), chatLine.lineType.isConversation else { return nil }

		return chatLine.receivedAt
	}

	/// A presentation that keeps no history of its own answers from the last line
	/// it printed.
	func newestMessageIdentifier(sentBy isSender: (String) -> Bool) -> String? {
		guard let chatLine = lastPrintedLine(), chatLine.lineType.isRedactableMessage,
		      let nickname = chatLine.nickname, isSender(nickname),
		      let identifier = chatLine.messageIdentifier, identifier.isEmpty == false
		else { return nil }

		return identifier
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
