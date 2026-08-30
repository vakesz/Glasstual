/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@MainActor
private final class ChannelInviteDelegateSpy: NSObject, ChannelInviteSheetDelegate {
	private(set) var selectedChannel: String?
	private(set) var didClose = false

	func channelInviteSheet(_: ChannelInviteSheet, onSelectChannel channelName: String) {
		selectedChannel = channelName
	}

	func channelInviteSheetWillClose(_: ChannelInviteSheet) {
		didClose = true
	}
}

@MainActor
@Suite("Channel invite sheet")
struct ChannelInviteFeatureTests {
	@Test(
		"The header names one invitee, two invitees, or counts them",
		arguments: [
			(["alice"], "Invite alice to:"),
			(["alice", "bob"], "Invite alice and bob to:"),
			(["alice", "bob", "carol"], "Invite 3 users to:"),
		]
	)
	func presentationDescribesOneTwoAndManyInvitees(_ nicknames: [String], _ headerTitle: String) {
		let content = ChannelInviteContent(nicknames: nicknames, channels: ["#general", "#support"])

		#expect(content.headerTitle == headerTitle)
	}

	@Test("The channels are offered in the order they were given, under localized controls")
	func presentationPreservesChannelOrderAndLocalizedControls() {
		let content = ChannelInviteContent(nicknames: ["alice"], channels: ["#zeta", "#alpha"])

		#expect(content.channels == ["#zeta", "#alpha"])
		#expect(content.channelPickerLabel == "Channel to invite users to")
		#expect(content.inviteButtonTitle == "Invite")
		#expect(content.cancelButtonTitle == "Cancel")
	}

	@Test("Accepting the sheet reports the selected channel, and closing it reports the close")
	func adapterUsesTheTypedLegacyDelegateContract() {
		let adapter = ChannelInviteSheet(nicknames: ["alice"], on: GLTTestClient())
		let delegate = ChannelInviteDelegateSpy()
		adapter.delegate = delegate

		adapter.start(withChannels: ["#general", "#support"])
		adapter.ok(nil)
		adapter.windowWillClose(Notification(name: NSWindow.willCloseNotification))

		#expect(delegate.selectedChannel == "#general")
		#expect(delegate.didClose)
	}
}
