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

import Foundation
@testable import Glasstual
import Testing

/// Behaviour corpus for the channel mode string parser.
///
/// Every case is parsed against `CHANMODES=beI,k,l,imnpst` and
/// `PREFIX=(ov)@+`, the shape almost every network advertises.
@MainActor
struct IRCModeParserCorpusTests {
	nonisolated struct ParsedMode: Sendable, Equatable {
		let symbol: String
		let isSet: Bool
		let parameter: String?

		init(_ symbol: String, _ isSet: Bool, _ parameter: String? = nil) {
			self.symbol = symbol
			self.isSet = isSet
			self.parameter = parameter
		}
	}

	nonisolated struct ModeCase: Sendable {
		let modeString: String
		let expected: [ParsedMode]

		init(_ modeString: String, _ expected: [ParsedMode]) {
			self.modeString = modeString
			self.expected = expected
		}
	}

	private static func supportInfo() -> IRCISupportInfo {
		let supportInfo = IRCISupportInfo()

		supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")

		return supportInfo
	}

	nonisolated static let modeCases: [ModeCase] = [
		/* Prefix modes consume one parameter in both directions. */
		ModeCase("+o alice", [ParsedMode("o", true, "alice")]),
		ModeCase("-o alice", [ParsedMode("o", false, "alice")]),
		ModeCase("+ov alice bob", [ParsedMode("o", true, "alice"), ParsedMode("v", true, "bob")]),
		/* A sign inside a token flips the direction of the modes after it. */
		ModeCase("+o-v alice bob", [ParsedMode("o", true, "alice"), ParsedMode("v", false, "bob")]),
		ModeCase("+o-o alice bob", [ParsedMode("o", true, "alice"), ParsedMode("o", false, "bob")]),
		/* Class B modes always consume a parameter. */
		ModeCase("+k secret", [ParsedMode("k", true, "secret")]),
		ModeCase("-k secret", [ParsedMode("k", false, "secret")]),
		/* Class C modes consume a parameter only when set. */
		ModeCase("+l 50", [ParsedMode("l", true, "50")]),
		ModeCase("-l", [ParsedMode("l", false, nil)]),
		/* Class A modes always consume a parameter. */
		ModeCase("+b *!*@spam.example", [ParsedMode("b", true, "*!*@spam.example")]),
		ModeCase("-b *!*@spam.example", [ParsedMode("b", false, "*!*@spam.example")]),
		ModeCase("+beI one two three", [
			ParsedMode("b", true, "one"), ParsedMode("e", true, "two"), ParsedMode("I", true, "three"),
		]),
		/* Class D modes never consume a parameter. */
		ModeCase("+nt", [ParsedMode("n", true, nil), ParsedMode("t", true, nil)]),
		ModeCase("-imnpst", [
			ParsedMode("i", false, nil), ParsedMode("m", false, nil), ParsedMode("n", false, nil),
			ParsedMode("p", false, nil), ParsedMode("s", false, nil), ParsedMode("t", false, nil),
		]),
		/* Parameters are handed out in order, skipping modes that take none. */
		ModeCase("+mo alice", [ParsedMode("m", true, nil), ParsedMode("o", true, "alice")]),
		ModeCase("+klnt secret 50", [
			ParsedMode("k", true, "secret"), ParsedMode("l", true, "50"),
			ParsedMode("n", true, nil), ParsedMode("t", true, nil),
		]),
		/* Runs of whitespace between tokens collapse. */
		ModeCase("+o    alice", [ParsedMode("o", true, "alice")]),
		/* Unknown modes are reported without consuming a parameter. */
		ModeCase("+Z leftover", [ParsedMode("Z", true, nil)]),
		ModeCase("-Z", [ParsedMode("Z", false, nil)]),
		/* A mode whose parameter is missing is still reported. */
		ModeCase("+k", [ParsedMode("k", true, nil)]),
		ModeCase("+o", [ParsedMode("o", true, nil)]),
		/* Tokens that carry no sign are skipped, not treated as modes. */
		ModeCase("", []),
		ModeCase("   ", []),
		ModeCase("alice", []),
		ModeCase("+", []),
		ModeCase("-", []),
		/* A stray parameter after a parameter-less mode is ignored. */
		ModeCase("+i leftover", [ParsedMode("i", true, nil)]),
		/* Later sign tokens reset the direction. */
		ModeCase("+n -t", [ParsedMode("n", true, nil), ParsedMode("t", false, nil)]),
	]

	@Test(arguments: Self.modeCases)
	func parsesModeStrings(testCase: ModeCase) {
		let parsed = Self.supportInfo().parseModes(testCase.modeString).map {
			ParsedMode($0.modeSymbol, $0.modeIsSet, $0.modeParameter)
		}

		#expect(parsed == testCase.expected)
	}

	@Test
	func defaultChannelModesOnlyKnowOperatorAndVoice() {
		let supportInfo = IRCISupportInfo()
		let parsed = supportInfo.parseModes("+ov alice bob")

		#expect(parsed.count == 2)
		#expect(parsed.first?.modeParameter == "alice")
		#expect(parsed.last?.modeParameter == "bob")
	}

	// MARK: - Aggregate channel state

	/// `ChannelModeState` holds its client weakly, so the suite owns one for
	/// the lifetime of each test.
	private let client = GLTTestClient()

	private func channelState(applying modeString: String) throws -> ChannelModeState {
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")

		let channel = try #require(client.findChannelOrCreate("#chat"))
		let state = ChannelModeState(channel: channel)

		_ = state.updateModes(modeString)

		return state
	}

	@Test
	func aggregateStateKeepsParameterisedModes() throws {
		let state = try channelState(applying: "+ntk secret +l 5")

		#expect(state.string == "+klnt secret 5")
		#expect(state.stringWithMaskedPassword == "+klnt ****** 5")
		#expect(state.modeIsDefined("k"))
		#expect(state.modeInfo(for: "k")?.modeParameter == "secret")
	}

	/// List modes and prefix modes belong to their own lists, not to the
	/// aggregate channel mode state.
	@Test(arguments: ["b", "q", "o", "v"])
	func aggregateStateRejectsListAndPrefixModes(modeSymbol: String) throws {
		let state = try channelState(applying: "+bqov mask nick alice bob")

		#expect(state.modeIsDefined(modeSymbol) == false)
	}

	@Test
	func unsettingAModeDropsItsParameterFromTheString() throws {
		let state = try channelState(applying: "+kl secret 5")

		_ = state.updateModes("-l")

		#expect(state.string == "+k secret")
	}
}
