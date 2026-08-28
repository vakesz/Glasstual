/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct IRCChannelModeQueryPurityTests {
	private func channelMode(currentModes modeString: String) throws -> ChannelModeState {
		let client = GLTTestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")

		let channel = try #require(client.findChannelOrCreate("#chat"))
		let channelMode = ChannelModeState(channel: channel)
		_ = channelMode.updateModes(modeString)
		return channelMode
	}

	@Test("Querying a mode does not define it")
	func queryingAModeDoesNotDefineIt() throws {
		let channelMode = try channelMode(currentModes: "")

		#expect(channelMode.modeInfo(for: "n") == nil)
		#expect(channelMode.modeIsDefined("n") == false)
	}

	@Test("Reading modes for the properties sheet does not produce a removal command")
	func readingModesProducesNoRemovalCommand() throws {
		let channelMode = try channelMode(currentModes: "")
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)

		/* This is what the channel-properties sheet does: read each mode it displays. */
		for symbol in ["k", "l", "n", "t", "i", "m", "p", "s"] {
			_ = modes.modeInfo(for: symbol)
		}

		#expect(channelMode.changeCommand(for: modes) == "")
	}

	@Test("A mode set after being queried still produces an add command")
	func settingAQueriedModeStillWorks() throws {
		let channelMode = try channelMode(currentModes: "")
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)

		_ = modes.modeInfo(for: "k")
		modes.changeMode("k", modeIsSet: true, modeParameter: "secret")

		#expect(channelMode.changeCommand(for: modes) == "+k secret")
	}
}
