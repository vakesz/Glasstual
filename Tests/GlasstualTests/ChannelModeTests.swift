// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Channel mode state")
struct ChannelModeTests {
	private let client = TestClient()

	private func channelMode(currentModes modeString: String) throws -> ChannelModeState {
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")

		let channel = try #require(client.findChannelOrCreate("#chat"))
		let channelMode = ChannelModeState(channel: channel)
		_ = channelMode.updateModes(modeString)
		return channelMode
	}

	@Test("A change command lists the removed mode parameters before the added ones")
	func removedModeParametersPrecedeAddedOnes() throws {
		let channelMode = try channelMode(currentModes: "+nk secret")
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)
		modes.changeMode("k", modeIsSet: false, modeParameter: "secret")
		modes.changeMode("l", modeIsSet: true, modeParameter: "10")

		#expect(channelMode.changeGroups(for: modes) == [
			ModeChangeGroup(symbols: "-k+l", parameters: ["secret", "10"]),
		])
	}

	@Test("Modes that did not change produce no command")
	func unchangedModesProduceNoCommand() throws {
		let channelMode = try channelMode(currentModes: "+nt")
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)

		#expect(channelMode.changeGroups(for: modes).isEmpty)
	}

	@Test("The mode string lists every letter first and the parameters after them")
	func modeStringListsParametersAfterLetters() throws {
		let channelMode = try channelMode(currentModes: "+ntk secret +l 5")

		#expect(channelMode.string == "+klnt secret 5")
		#expect(channelMode.stringWithMaskedPassword == "+klnt ****** 5")
	}

	@Test("A change command orders its modes the same way whatever order they were set in")
	func changeGroupsAreDeterministic() throws {
		let channelMode = try channelMode(currentModes: "")
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)
		modes.changeMode("l", modeIsSet: true, modeParameter: "last")
		modes.changeMode("k", modeIsSet: true, modeParameter: "first")

		#expect(channelMode.changeGroups(for: modes) == [
			ModeChangeGroup(symbols: "+kl", parameters: ["first", "last"]),
		])
	}

	/// The sheet still remembers the old limit after its box is cleared; pairing
	/// that text with `-l` shifted the new key onto the limit's slot.
	@Test("A removal carries a parameter only where the mode's class takes one")
	func removalParametersFollowTheModeClass() throws {
		let channelMode = try channelMode(currentModes: "+kl old 50")
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)
		modes.changeMode("l", modeIsSet: false, modeParameter: "50")
		modes.changeMode("k", modeIsSet: true, modeParameter: "new")

		#expect(channelMode.changeGroups(for: modes) == [
			ModeChangeGroup(symbols: "-l+k", parameters: ["new"]),
		])
	}

	@Test("Removing a key sends the key the channel was set with")
	func keyRemovalCarriesTheCurrentKey() throws {
		let channelMode = try channelMode(currentModes: "+k current")
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)
		modes.changeMode("k", modeIsSet: false, modeParameter: "edited")

		#expect(channelMode.changeGroups(for: modes) == [
			ModeChangeGroup(symbols: "-k", parameters: ["current"]),
		])
	}

	@Test("Modes unset on both sides, and set modes whose parameter is unchanged, send nothing")
	func unsetAndUnchangedModesSendNothing() throws {
		let channelMode = try channelMode(currentModes: "+ntl 50")
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)

		for symbol in ["i", "k", "m", "p", "s"] {
			modes.changeMode(symbol, modeIsSet: false, modeParameter: symbol == "k" ? "typed" : nil)
		}
		modes.changeMode("l", modeIsSet: true, modeParameter: "50")

		#expect(channelMode.changeGroups(for: modes).isEmpty)
	}

	@Test("A parameterised mode set with no parameter is left out of the change")
	func parameterisedAdditionWithoutParameterIsDropped() throws {
		let channelMode = try channelMode(currentModes: "")
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)
		modes.changeMode("l", modeIsSet: true, modeParameter: "")
		modes.changeMode("m", modeIsSet: true)

		#expect(channelMode.changeGroups(for: modes) == [ModeChangeGroup(symbols: "+m")])
	}

	@Test("List modes and user modes are not kept as channel state")
	func listAndUserModesAreNotStoredAsChannelState() throws {
		let channelMode = try channelMode(currentModes: "")

		channelMode.modes.changeMode("b", modeIsSet: true, modeParameter: "*!*@host")
		channelMode.modes.changeMode("o", modeIsSet: true, modeParameter: "nick")
		channelMode.modes.changeMode("n", modeIsSet: true)

		#expect(channelMode.modeInfo(for: "b") == nil)
		#expect(channelMode.modeInfo(for: "o") == nil)
		#expect(channelMode.modeInfo(for: "n") != nil)
	}

	@Test("A copied container edits and clears independently of the channel's own modes")
	func copiedContainerHasIndependentState() throws {
		let channelMode = try channelMode(currentModes: "+nt")
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)
		modes.changeMode("k", modeIsSet: true, modeParameter: "secret")

		#expect(channelMode.modeIsDefined("k") == false)
		#expect(modes.modeIsDefined("k"))

		modes.clear()

		#expect(channelMode.modeIsDefined("n"))
		#expect(modes.modes.isEmpty)
	}
}
