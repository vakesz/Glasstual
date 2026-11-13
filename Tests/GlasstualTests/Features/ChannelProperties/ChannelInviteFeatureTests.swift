// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

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
		#expect(ChannelInviteSheet.invitationTitle(for: nicknames) == headline)
	}

	@Test("Inviting reports the chosen channel")
	func invitingReportsTheChosenChannel() {
		var selectedChannel: String?
		let sheet = ChannelInviteSheet(nicknames: ["alice"], on: TestServerSession()) { selectedChannel = $0 }

		sheet.start(withChannels: ["#general", "#support"])
		sheet.invite(to: "#support")

		#expect(selectedChannel == "#support")
	}

	@Test("The picker starts on the first channel offered", arguments: [
		(["#general", "#support"], "#general"),
		([], ""),
	])
	func pickerStartsOnTheFirstChannel(_ channels: [String], _ selection: String) {
		#expect(ChannelInviteView.initialSelection(from: channels) == selection)
	}
}
