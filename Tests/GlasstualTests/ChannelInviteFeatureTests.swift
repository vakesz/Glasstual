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

	func channelInviteSheet(_: ChannelInviteSheet, onSelectChannel channelName: String) {
		selectedChannel = channelName
	}
}

@MainActor
@Suite("Channel invite sheet")
struct ChannelInviteFeatureTests {
	@Test(
		"The headline names one invitee, two invitees, or counts them",
		arguments: [
			(["alice"], "Invite alice"),
			(["alice", "bob"], "Invite alice and bob"),
			(["alice", "bob", "carol"], "Invite 3 users"),
		]
	)
	func headlineDescribesOneTwoAndManyInvitees(_ nicknames: [String], _ headline: String) {
		#expect(ChannelInviteStrings.invitationTitle(for: nicknames) == headline)
	}

	/// The sheet is titled, and the picker beneath it is labelled for what it
	/// chooses rather than repeating the sentence above it.
	@Test("The sheet names itself and its one control")
	func sheetCopyComesFromTheCatalog() {
		#expect(ChannelInviteStrings.windowTitle == "Invite to Channel")
		#expect(ChannelInviteStrings.channelPickerLabel == "Channel")
		#expect(ChannelInviteStrings.inviteButtonTitle == "Invite")
	}

	@Test("Inviting reports the chosen channel to the delegate")
	func invitingReportsTheChosenChannel() {
		let adapter = ChannelInviteSheet(nicknames: ["alice"], on: TestClient())
		let delegate = ChannelInviteDelegateSpy()
		adapter.delegate = delegate

		adapter.start(withChannels: ["#general", "#support"])
		adapter.invite(to: "#support")

		#expect(delegate.selectedChannel == "#support")
	}

	@Test("The picker starts on the first channel offered", arguments: [
		(["#general", "#support"], "#general"),
		([], ""),
	])
	func pickerStartsOnTheFirstChannel(_ channels: [String], _ selection: String) {
		#expect(ChannelInviteView.initialSelection(from: channels) == selection)
	}
}
