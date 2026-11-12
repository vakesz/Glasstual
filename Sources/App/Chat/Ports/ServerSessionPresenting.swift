// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Where a menu asks ``ServerPropertiesSheet`` to open, and what it opens
/// there with. The payloads used to travel beside the case as an `Any?` the
/// sheet cast back.
enum ServerPropertiesDestination {
	case `default`
	case addressBook
	/// A new ignore entry, pre-filled with the hostmask `/ignore` collected.
	case newIgnoreEntry(hostmask: String?)
	/// The address book entry the member-list menu asked to edit.
	case editIgnoreEntry(AddressBookEntry)
}

/** The window-side work the protocol layer asks for: selection, redraws, titles
 and the member list. Implemented by the main window; absent in tests. */
@MainActor
protocol ServerSessionPresenting: AnyObject {
	// MARK: Selection

	var selectedItem: ChatItem? { get }
	var selectedSession: ServerSession? { get }
	var selectedConversation: Conversation? { get }
	func selectedConversation(on session: ServerSession) -> Conversation?
	func select(_ item: ChatItem?)
	func isItemSelected(_ item: ChatItem?) -> Bool
	func isItemVisible(_ item: ChatItem) -> Bool

	var isKeyWindow: Bool { get }
	var isMainWindow: Bool { get }
	/// Closes every sheet the window is showing on this session's behalf.
	func closeSheets(for session: ServerSession)

	// MARK: Channel mask lists

	/** A `+b`/`+e`/`+I`/`+q` list entry arrived from the server.

	 The connection, the channel and the mode letter all travel with the mask
	 because a window is open on one list of one channel: this seam is shared
	 with the transcript and is one object for every connection, so an entry
	 routed to whichever list happened to be frontmost put another channel's bans
	 in it. The receiver answers `false` for an entry that is not its own, and the
	 protocol layer prints it into the transcript instead.

	 `true` when a window is showing that list and took the entry, in which case
	 the protocol layer does not also print it. */
	func maskListEntryReceived(
		for session: ServerSession,
		inChannelNamed channelName: String,
		modeSymbol: String,
		mask: String,
		setBy author: String?,
		creationDate date: Date?
	) -> Bool
	/// The end of such a list. `true` when a window showing that list took it.
	func maskListFinished(for session: ServerSession, inChannelNamed channelName: String, modeSymbol: String) -> Bool
	/// The server refused a change to a channel's access list, with the numeric
	/// it answered and its text. `true` when the open list for that channel took
	/// it, in which case the protocol layer does not also print it.
	func maskListChangeRefused(
		for session: ServerSession,
		inChannelNamed channelName: String,
		numeric: UInt,
		text: String
	) -> Bool
	/// Dismisses whatever sheet is scoped to a conversation that is going away.
	/// The protocol layer knows the conversation is gone; which sheets were
	/// hanging off it is the window layer's business.
	func closeSheets(forConversationId conversationId: String)
	/// Offers a freshly logged highlight to a highlight list that happens to be
	/// open for the same session, so the list does not have to be reopened to
	/// show it. A no-op when none is open.
	func highlightWasLogged(_ entry: HighlightRecord)

	// MARK: ServerEndpoint list

	func reloadChatItem(_ item: ChatItem)
	func reloadChatItemGroup(_ item: ChatItem)
	/// Reloads a session and its children in place, keeping the selection.
	func reloadSidebarItems(for session: ServerSession)
	func refreshMessageCount(for item: ChatItem)

	// MARK: Titles and chrome

	func updateTitle(for item: ChatItem)
	func updateTitle()
	func updateDrawingForUserInUserList(_ user: User)

	// MARK: Member list

	func assignMemberList(to conversation: Conversation)
	func updateMemberListVisibilityForSelection()

	// MARK: Views

	func clearContents(of item: ChatItem)
	func destroyInputHistory(for item: ChatItem)
}

extension ServerSessionPresenting {
	/// A presenter with no access-list window has nothing to take a refusal.
	func maskListChangeRefused(
		for _: ServerSession,
		inChannelNamed _: String,
		numeric _: UInt,
		text _: String
	) -> Bool {
		false
	}
}
