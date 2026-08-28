import Foundation
@testable import Glasstual
import Testing

/** *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
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
@MainActor
@Suite("Channel mode state")
struct ChannelModeTests {
	private let client = GLTTestClient()

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

		#expect(channelMode.changeCommand(for: modes) == "-k+l secret 10")
	}

	@Test("Modes that did not change produce no command")
	func unchangedModesProduceNoCommand() throws {
		let channelMode = try channelMode(currentModes: "+nt")
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)

		#expect(channelMode.changeCommand(for: modes) == "")
	}

	@Test("The mode string lists every letter first and the parameters after them")
	func modeStringListsParametersAfterLetters() throws {
		let channelMode = try channelMode(currentModes: "+ntk secret +l 5")

		#expect(channelMode.string == "+klnt secret 5")
		#expect(channelMode.stringWithMaskedPassword == "+klnt ****** 5")
	}

	@Test("A change command orders its modes the same way whatever order they were set in")
	func changeCommandIsDeterministic() throws {
		let channelMode = try channelMode(currentModes: "")
		let modes = try #require(channelMode.modes.copy() as? ChannelModeContainer)
		modes.changeMode("z", modeIsSet: true, modeParameter: "last")
		modes.changeMode("a", modeIsSet: true, modeParameter: "first")

		#expect(channelMode.changeCommand(for: modes) == "+az first last")
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
