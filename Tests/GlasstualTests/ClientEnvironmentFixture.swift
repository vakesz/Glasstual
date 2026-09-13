/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual and/or Codeux Software, nor the names of
 *    its contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
@testable import Glasstual

/// A window that records what the connection code asked it to draw instead of
/// drawing anything.
@MainActor
final class RecordingClientOutput: ClientOutput {
	private(set) var selectedItems: [TreeItem] = []
	private(set) var reloadedItems: [TreeItem] = []
	private(set) var reloadedGroups: [TreeItem] = []
	private(set) var titleUpdates: [TreeItem?] = []
	private(set) var clearedItems: [TreeItem] = []
	private(set) var evaluatedFunctions: [String] = []
	/// Every sheet the protocol layer asked for, in order. No window is
	/// involved, which is the point of the seam.
	private(set) var presentedAlerts: [AlertRequest] = []
	/// Every blocking confirmation the protocol layer asked for, in order.
	private(set) var modalConfirmations: [AlertRequest] = []
	private(set) var closedSheetClients: [IRCClient] = []
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

	/// What `confirmModally` answers, and whether an access list window is up.
	var modalConfirmationAnswer = true
	var showsAccessListSheet = false
	/// The channels whose sheets the protocol layer asked to have closed.
	private(set) var closedSheetChannelIds: [String] = []
	/// Every highlight offered to an open highlight list, in order.
	private(set) var loggedHighlights: [HighlightLogEntry] = []

	var selectedItem: TreeItem?
	var selectedClient: IRCClient?
	var selectedChannel: Channel?
	var isKeyWindow = false
	var isMainWindow = false
	var visibleItems: [TreeItem] = []

	func presentAlertSheet(_ request: AlertRequest, completion _: @escaping AlertCompletion) {
		presentedAlerts.append(request)
	}

	func confirmModally(_ request: AlertRequest) -> Bool {
		modalConfirmations.append(request)

		return modalConfirmationAnswer
	}

	func closeSheets(for client: IRCClient) {
		closedSheetClients.append(client)
	}

	func accessListEntryReceived(
		for _: IRCClient,
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

	func accessListFinished(for _: IRCClient, inChannelNamed channelName: String, modeSymbol: String) -> Bool {
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

	func selectedChannel(on client: IRCClient) -> Channel? {
		selectedClient === client ? selectedChannel : nil
	}

	func select(_ item: TreeItem?) {
		guard let item else { return }
		selectedItems.append(item)
		selectedItem = item
	}

	func isItemSelected(_ item: TreeItem?) -> Bool {
		item != nil && selectedItem === item
	}

	func isItemVisible(_ item: TreeItem) -> Bool {
		visibleItems.contains { $0 === item }
	}

	func reloadTreeItem(_ item: TreeItem) {
		reloadedItems.append(item)
	}

	func reloadTreeGroup(_ item: TreeItem) {
		reloadedGroups.append(item)
	}

	func reloadServerListItems(for client: IRCClient) {
		reloadedGroups.append(client)
	}

	func refreshMessageCount(for item: TreeItem) {
		reloadedItems.append(item)
	}

	func updateTitle(for item: TreeItem) {
		titleUpdates.append(item)
	}

	func updateTitle() {
		titleUpdates.append(nil)
	}

	func updateDrawingForUserInUserList(_: User) {}

	func assignMemberList(to _: Channel) {}

	func updateMemberListVisibilityForSelection() {}

	func clearContents(of item: TreeItem) {
		clearedItems.append(item)
	}

	func destroyInputHistory(for _: TreeItem) {}

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

	func showServerPropertiesSheet(for _: IRCClient, selection: ServerPropertiesDestination) {
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
	/// A world of this fixture's own, so channel creation works without the
	/// application's. `ClientServices` refers to it weakly; this keeps it alive.
	let world: World
	private(set) var environment: ClientEnvironment

	init(preferences: ClientPreferences = .current()) {
		let services = ClientServices(
			output: output,
			menu: menu,
			applicationState: applicationState
		)
		environment = ClientEnvironment(preferences: preferences, services: services)
		/* The world installs itself in the services it is given. */
		world = World(environment: environment)
	}

	/// Re-reads the defaults store, for a test that writes a preference after
	/// the client already exists.
	func refreshPreferences() {
		environment.preferences = .current()
	}
}
