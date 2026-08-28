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
final class GLTRecordingClientOutput: ClientOutput {
	private(set) var selectedItems: [IRCTreeItem] = []
	private(set) var reloadedItems: [IRCTreeItem] = []
	private(set) var reloadedGroups: [IRCTreeItem] = []
	private(set) var titleUpdates: [IRCTreeItem?] = []
	private(set) var clearedItems: [IRCTreeItem] = []
	private(set) var evaluatedFunctions: [String] = []

	var selectedItem: IRCTreeItem?
	var selectedClient: IRCClient?
	var selectedChannel: IRCChannel?
	var windowIsKey = false
	var windowIsMain = false
	var alertPresentationWindow: NSWindow?
	var visibleItems: [IRCTreeItem] = []
	var memberListIsAvailable = false

	func selectedChannel(on client: IRCClient) -> IRCChannel? {
		selectedClient === client ? selectedChannel : nil
	}

	func selectItem(_ item: IRCTreeItem) {
		selectedItems.append(item)
		selectedItem = item
	}

	func isItemSelectedInWindow(_ item: IRCTreeItem) -> Bool {
		selectedItem === item
	}

	func isItemVisible(_ item: IRCTreeItem) -> Bool {
		visibleItems.contains { $0 === item }
	}

	func reloadTreeItem(_ item: IRCTreeItem) {
		reloadedItems.append(item)
	}

	func reloadTreeGroup(_ item: IRCTreeItem) {
		reloadedGroups.append(item)
	}

	func reloadServerListItems(for client: IRCClient) {
		reloadedGroups.append(client)
	}

	func refreshMessageCount(for item: IRCTreeItem) {
		reloadedItems.append(item)
	}

	func updateTitle(for item: IRCTreeItem) {
		titleUpdates.append(item)
	}

	func updateTitle() {
		titleUpdates.append(nil)
	}

	func updateDrawingForUser(_: User) {}

	func beginMemberListUpdates() -> Bool {
		memberListIsAvailable
	}

	func endMemberListUpdates() {}

	func refreshMemberListDrawing(forMemberAt _: Int) {}

	func assignMemberList(to _: IRCChannel) {}

	func updateMemberListVisibilityForSelection() {}

	func clearContents(of item: IRCTreeItem) {
		clearedItems.append(item)
	}

	func destroyInputHistory(for _: IRCTreeItem) {}

	func evaluateFunctionOnAllViews(_ function: String, arguments _: [Any]?, onQueue _: Bool) {
		evaluatedFunctions.append(function)
	}

	func notifyAllViewsAppearanceDidChange() {
		evaluatedFunctions.append("Glasstual.appearanceDidChange")
	}
}

/// A menu bar that records the sheets it was asked to raise.
@MainActor
final class GLTRecordingMenuPresenter: ClientMenuPresenting {
	private(set) var soundsMuted: Bool?
	private(set) var serverPropertiesSelections: [UInt] = []
	private(set) var nicknameColorSheets: [String] = []

	func toggleMuteOnNotificationSoundsShortcut(on muted: Bool) {
		soundsMuted = muted
	}

	func showServerPropertiesSheet(for _: IRCClient, selection: UInt, context _: Any?) {
		serverPropertiesSelections.append(selection)
	}

	func showNicknameColorSheet(forNickname nickname: String) {
		nicknameColorSheets.append(nickname)
	}

	func openAcknowledgements(_: Any?) {}

	func navigateToTreeItem(at _: URL) {}

	func connectToGlasstualHelpChannel(_: Any?) {}

	func connectToGlasstualTestingChannel(_: Any?) {}
}

/// An application that is never terminating and never in ghost mode.
@MainActor
final class GLTRecordingApplicationState: ClientApplicationState {
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
final class GLTClientEnvironmentFixture {
	let output = GLTRecordingClientOutput()
	let menu = GLTRecordingMenuPresenter()
	let applicationState = GLTRecordingApplicationState()
	/// A world of this fixture's own, so channel creation works without the
	/// application's. `ClientServices` refers to it weakly; this keeps it alive.
	let world: IRCWorld
	private(set) var environment: ClientEnvironment

	init(preferences: ClientPreferences = .current()) {
		let services = ClientServices(
			output: output,
			menu: menu,
			applicationState: applicationState
		)
		environment = ClientEnvironment(preferences: preferences, services: services)
		/* The world installs itself in the services it is given. */
		world = IRCWorld(environment: environment)
	}

	/// Re-reads the defaults store, for a test that writes a preference after
	/// the client already exists.
	func refreshPreferences() {
		environment.preferences = .current()
	}
}
