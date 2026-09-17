// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual

/// A window that records what the connection code asked it to draw instead of
/// drawing anything.
@MainActor
final class RecordingClientOutput: ClientOutput {
	private(set) var selectedItems: [ChatItem] = []
	private(set) var reloadedItems: [ChatItem] = []
	private(set) var reloadedGroups: [ChatItem] = []
	private(set) var titleUpdates: [ChatItem?] = []
	private(set) var clearedItems: [ChatItem] = []
	private(set) var evaluatedFunctions: [String] = []
	/// Every sheet the protocol layer asked for, in order. No window is
	/// involved, which is the point of the seam.
	private(set) var presentedAlerts: [AlertRequest] = []
	/// Every confirmation the protocol layer asked for, in order.
	private(set) var confirmations: [AlertRequest] = []
	private(set) var closedSheetClients: [Client] = []
	/// One `+b`/`+e`/`+I`/`+q` entry a window would have taken, and the list it
	/// was routed to.
	struct AccessListEntry: Equatable {
		let channelName: String
		let modeSymbol: String
		let mask: String
		let author: String?
		let date: Date?
	}

	private(set) var accessListEntries: [AccessListEntry] = []
	/// The `(channel, mode letter)` pairs an end-of-list reply was routed to.
	private(set) var accessListFinishes: [String] = []
	var accessListFinishedCount: Int {
		accessListFinishes.count
	}

	/// Tests can suspend the answer to exercise stale-session handling.
	var confirmation: (@MainActor (AlertRequest) async -> Bool)?
	var confirmationAnswer = true
	var showsAccessListSheet = false
	/// The channels whose sheets the protocol layer asked to have closed.
	private(set) var closedSheetChannelIds: [String] = []
	/// Every highlight offered to an open highlight list, in order.
	private(set) var loggedHighlights: [HighlightLogEntry] = []

	var selectedItem: ChatItem?
	var selectedClient: Client?
	var selectedChannel: Channel?
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

	func closeSheets(for client: Client) {
		closedSheetClients.append(client)
	}

	func accessListEntryReceived(
		for _: Client,
		inChannelNamed channelName: String,
		modeSymbol: String,
		mask: String,
		setBy author: String?,
		creationDate date: Date?
	) -> Bool {
		guard showsAccessListSheet else { return false }

		accessListEntries.append(AccessListEntry(
			channelName: channelName,
			modeSymbol: modeSymbol,
			mask: mask,
			author: author,
			date: date
		))

		return true
	}

	func accessListFinished(for _: Client, inChannelNamed channelName: String, modeSymbol: String) -> Bool {
		guard showsAccessListSheet else { return false }

		accessListFinishes.append("\(channelName) +\(modeSymbol)")

		return true
	}

	func closeSheets(forChannelId channelId: String) {
		closedSheetChannelIds.append(channelId)
	}

	func highlightWasLogged(_ entry: HighlightLogEntry) {
		loggedHighlights.append(entry)
	}

	func selectedChannel(on client: Client) -> Channel? {
		selectedClient === client ? selectedChannel : nil
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

	func reloadServerListItems(for client: Client) {
		reloadedGroups.append(client)
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

	func assignMemberList(to _: Channel) {}

	func updateMemberListVisibilityForSelection() {}

	func clearContents(of item: ChatItem) {
		clearedItems.append(item)
	}

	func destroyInputHistory(for _: ChatItem) {}

	func evaluateFunctionOnAllViews(_ function: String, arguments _: [Any]?, onQueue _: Bool) {
		evaluatedFunctions.append(function)
	}

	func notifyAllViewsAppearanceDidChange() {
		evaluatedFunctions.append("Glasstual.appearanceDidChange")
	}
}

/// A menu bar that records the sheets it was asked to raise.
@MainActor
final class RecordingMenuPresenter: ClientMenuPresenting {
	private(set) var soundsMuted: Bool?
	private(set) var serverPropertiesSelections: [ServerPropertiesDestination] = []
	private(set) var nicknameColorSheets: [String] = []
	private(set) var revealedFolders: [URL] = []

	func toggleMuteOnNotificationSoundsShortcut(on muted: Bool) {
		soundsMuted = muted
	}

	func showServerPropertiesSheet(for _: Client, selection: ServerPropertiesDestination) {
		serverPropertiesSelections.append(selection)
	}

	func showNicknameColorSheet(forNickname nickname: String) {
		nicknameColorSheets.append(nickname)
	}

	func openAcknowledgements(_: Any?) {}

	func navigateToTreeItem(at _: URL) {}

	func revealInFinder(_ url: URL) {
		revealedFolders.append(url)
	}
}

/// An application that is never terminating and never in ghost mode.
@MainActor
final class RecordingApplicationState: ClientApplicationState {
	var ghostModeIsOn = false
	var applicationIsTerminating = false
	private(set) var clientsFinishedTerminating = 0

	func noteClientDidFinishTerminating() {
		clientsFinishedTerminating += 1
	}
}

/** Owns the doubles a test client talks to. `ClientServices` holds them weakly,
 so something has to keep them alive for as long as the client does. */
@MainActor
final class ClientEnvironmentFixture {
	let output = RecordingClientOutput()
	let menu = RecordingMenuPresenter()
	let applicationState = RecordingApplicationState()
	/// A client directory of this fixture's own, so channel creation works without the
	/// application's. `ClientServices` refers to it weakly; this keeps it alive.
	let clientDirectory: ClientDirectory
	private(set) var environment: ClientEnvironment

	init(preferences: ClientPreferences = .current()) {
		let services = ClientServices(
			output: output,
			menu: menu,
			applicationState: applicationState
		)
		environment = ClientEnvironment(preferences: preferences, services: services)
		/* The directory installs itself in the services it is given. */
		clientDirectory = ClientDirectory(environment: environment)
	}

	/// Re-reads the defaults store, for a test that writes a preference after
	/// the client already exists.
	func refreshPreferences() {
		environment.preferences = .current()
	}
}
