// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct ChannelModeQueryPurityTests {
	private func channelMode(currentModes modeString: String) throws -> (TestClient, ChannelModeState) {
		let client = TestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")

		let channel = try #require(client.findChannelOrCreate("#chat"))
		let channelMode = ChannelModeState(channel: channel)
		_ = channelMode.updateModes(modeString)
		return (client, channelMode)
	}

	@Test("Querying a mode does not define it")
	func queryingAModeDoesNotDefineIt() throws {
		let (client, channelMode) = try channelMode(currentModes: "")
		defer { withExtendedLifetime(client) {} }

		#expect(channelMode.modeInfo(for: "n") == nil)
		#expect(channelMode.modeIsDefined("n") == false)
	}

	@Test("Reading modes for the properties sheet does not produce a removal command")
	func readingModesProducesNoRemovalCommand() throws {
		let (client, channelMode) = try channelMode(currentModes: "")
		defer { withExtendedLifetime(client) {} }
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)

		/* This is what the channel-properties sheet does: read each mode it displays. */
		for symbol in ["k", "l", "n", "t", "i", "m", "p", "s"] {
			_ = modes.modeInfo(for: symbol)
		}

		#expect(channelMode.changeGroups(for: modes).isEmpty)
	}

	@Test("A mode set after being queried still produces an add command")
	func settingAQueriedModeStillWorks() throws {
		let (client, channelMode) = try channelMode(currentModes: "")
		defer { withExtendedLifetime(client) {} }
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)

		_ = modes.modeInfo(for: "k")
		modes.changeMode("k", modeIsSet: true, modeParameter: "secret")

		#expect(channelMode.changeGroups(for: modes) == [ModeChangeGroup(symbols: "+k", parameters: ["secret"])])
	}
}
