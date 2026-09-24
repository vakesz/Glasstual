// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual

/// A window that records what the connection code asked it to draw instead of
/// drawing anything.
@MainActor
final class RecordingSessionOutput: ServerSessionPresenting {
	private(set) var selectedItems: [ChatItem] = []
	private(set) var reloadedItems: [ChatItem] = []
	private(set) var reloadedGroups: [ChatItem] = []
	private(set) var titleUpdates: [ChatItem?] = []
	private(set) var clearedItems: [ChatItem] = []
	/// Every sheet the protocol layer asked for, in order. No window is
	/// involved, which is the point of the seam.
	private(set) var presentedAlerts: [AlertRequest] = []
	/// Every confirmation the protocol layer asked for, in order.
	private(set) var confirmations: [AlertRequest] = []
	private(set) var closedSheetSessions: [ServerSession] = []
	/// One `+b`/`+e`/`+I`/`+q` entry a window would have taken, and the list it
	/// was routed to.
	struct MaskListEntry: Equatable {
		let channelName: String
		let modeSymbol: String
		let mask: String
		let author: String?
		let date: Date?
	}

	private(set) var maskListEntries: [MaskListEntry] = []
	/// The `(channel, mode letter)` pairs an end-of-list reply was routed to.
	private(set) var maskListFinishes: [String] = []
	var maskListFinishedCount: Int {
		maskListFinishes.count
	}

	/// Tests can suspend the answer to exercise stale-session handling.
	var confirmation: (@MainActor (AlertRequest) async -> Bool)?
	var confirmationAnswer = true
	var showsMaskListSheet = false
	/// The channels whose sheets the protocol layer asked to have closed.
	private(set) var closedSheetChannelIds: [String] = []
	/// Every highlight offered to an open highlight list, in order.
	private(set) var loggedHighlights: [HighlightRecord] = []

	var selectedItem: ChatItem?
	var selectedSession: ServerSession?
	var selectedConversation: Conversation?
	var isKeyWindow = false
	var isMainWindow = false
	var visibleItems: [ChatItem] = []

	func presentAlertSheet(_ request: AlertRequest, completion _: @escaping AlertCompletion) {
		presentedAlerts.append(request)
	}

	func confirm(_ request: AlertRequest) async -> Bool {
		confirmations.append(request)
		if let confirmation {
			return await confirmation(request)
		}
		return confirmationAnswer
	}

	func closeSheets(for session: ServerSession) {
		closedSheetSessions.append(session)
	}

	func maskListEntryReceived(
		for _: ServerSession,
		inChannelNamed channelName: String,
		modeSymbol: String,
		mask: String,
		setBy author: String?,
		creationDate date: Date?
	) -> Bool {
		guard showsMaskListSheet else { return false }

		maskListEntries.append(MaskListEntry(
			channelName: channelName,
			modeSymbol: modeSymbol,
			mask: mask,
			author: author,
			date: date
		))

		return true
	}

	func maskListFinished(for _: ServerSession, inChannelNamed channelName: String, modeSymbol: String) -> Bool {
		guard showsMaskListSheet else { return false }

		maskListFinishes.append("\(channelName) +\(modeSymbol)")

		return true
	}

	func closeSheets(forConversationId conversationId: String) {
		closedSheetChannelIds.append(conversationId)
	}

	func highlightWasLogged(_ entry: HighlightRecord) {
		loggedHighlights.append(entry)
	}

	func selectedConversation(on session: ServerSession) -> Conversation? {
		selectedSession === session ? selectedConversation : nil
	}

	func select(_ item: ChatItem?) {
		guard let item else { return }
		selectedItems.append(item)
		selectedItem = item
	}

	func isItemSelected(_ item: ChatItem?) -> Bool {
		item != nil && selectedItem === item
	}

	func isItemVisible(_ item: ChatItem) -> Bool {
		visibleItems.contains { $0 === item }
	}

	func reloadChatItem(_ item: ChatItem) {
		reloadedItems.append(item)
	}

	func reloadChatItemGroup(_ item: ChatItem) {
		reloadedGroups.append(item)
	}

	func reloadSidebarItems(for session: ServerSession) {
		reloadedGroups.append(session)
	}

	func refreshMessageCount(for item: ChatItem) {
		reloadedItems.append(item)
	}

	func updateTitle(for item: ChatItem) {
		titleUpdates.append(item)
	}

	func updateTitle() {
		titleUpdates.append(nil)
	}

	func updateDrawingForUserInUserList(_: User) {}

	func assignMemberList(to _: Conversation) {}

	func updateMemberListVisibilityForSelection() {}

	func clearContents(of item: ChatItem) {
		clearedItems.append(item)
	}

	func destroyInputHistory(for _: ChatItem) {}

	func notifyAllViewsAppearanceDidChange() {}
}
