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

/// Behaviour corpus for RPL_ISUPPORT token handling.
///
/// The suite pins the semantics other code depends on — casefold equality,
/// mode parameter classes, prefix ranking, and numeric limits — and asserts
/// that malformed tokens are ignored rather than crashing.
@MainActor
struct IRCISupportCorpusTests {
	private static func supportInfo(_ configuration: String) -> IRCISupportInfo {
		let supportInfo = IRCISupportInfo()

		supportInfo.processConfigurationData(configuration)

		return supportInfo
	}

	// MARK: - CASEMAPPING

	struct CasefoldCase: Sendable {
		let configuration: String
		let input: String
		let folded: String

		init(_ configuration: String, _ input: String, _ folded: String) {
			self.configuration = configuration
			self.input = input
			self.folded = folded
		}
	}

	nonisolated static let casefoldCases: [CasefoldCase] = [
		/* rfc1459 folds the four "national" characters as well as A-Z. */
		CasefoldCase("CASEMAPPING=rfc1459", "Alice[]\\~", "alice{}|^"),
		CasefoldCase("CASEMAPPING=RFC1459", "Alice[]\\~", "alice{}|^"),
		/* strict-rfc1459 leaves the tilde alone. */
		CasefoldCase("CASEMAPPING=strict-rfc1459", "Alice[]\\~", "alice{}|~"),
		/* ascii folds A-Z and nothing else. */
		CasefoldCase("CASEMAPPING=ascii", "Alice[]\\~", "alice[]\\~"),
		CasefoldCase("CASEMAPPING=ASCII", "Alice[]\\~", "alice[]\\~"),
		/* Unknown mappings fall back to rfc1459. */
		CasefoldCase("CASEMAPPING=nonsense", "Alice[]\\~", "alice{}|^"),
		/* Non-ASCII letters are never folded by any mapping. */
		CasefoldCase("CASEMAPPING=ascii", "\u{00C4}b\u{00C7}", "\u{00C4}b\u{00C7}"),
		CasefoldCase("CASEMAPPING=rfc1459", "\u{00C4}b\u{00C7}", "\u{00C4}b\u{00C7}"),
		/* An empty string folds to itself. */
		CasefoldCase("CASEMAPPING=rfc1459", "", ""),
	]

	@Test(arguments: Self.casefoldCases)
	func foldsCaseAccordingToTheAdvertisedMapping(testCase: CasefoldCase) {
		let supportInfo = Self.supportInfo(testCase.configuration)

		#expect(supportInfo.casefoldString(testCase.input) == testCase.folded)
	}

	@Test
	func rfc1459TreatsBracketsAndBracesAsTheSameNickname() {
		let supportInfo = Self.supportInfo("CASEMAPPING=rfc1459")

		#expect(supportInfo.casefoldString("[Alice]") == supportInfo.casefoldString("{alice}"))
	}

	@Test
	func asciiTreatsBracketsAndBracesAsDifferentNicknames() {
		let supportInfo = Self.supportInfo("CASEMAPPING=ascii")

		#expect(supportInfo.casefoldString("[Alice]") != supportInfo.casefoldString("{alice}"))
	}

	/// `rfc7613` folds ASCII case only. It must not apply the rfc1459
	/// bracket-to-brace mapping.
	@Test(.disabled("Phase 1: rfc7613 is parsed as rfc1459, so [Alice] folds to {alice}"))
	func rfc7613FoldsAsciiCaseOnly() {
		let supportInfo = Self.supportInfo("CASEMAPPING=rfc7613")

		#expect(supportInfo.casefoldString("Alice[]\\~") == "alice[]\\~")
		#expect(supportInfo.casefoldString("[Alice]") != supportInfo.casefoldString("{alice}"))
	}

	// MARK: - CHANMODES

	struct ModeParameterCase: Sendable {
		let modeSymbol: String
		let whenSet: Bool
		let hasParameter: Bool

		init(_ modeSymbol: String, whenSet: Bool, hasParameter: Bool) {
			self.modeSymbol = modeSymbol
			self.whenSet = whenSet
			self.hasParameter = hasParameter
		}
	}

	/// `CHANMODES=beI,k,l,imnpst` with `PREFIX=(ov)@+`.
	nonisolated static let modeParameterCases: [ModeParameterCase] = [
		/* Class A (list modes) always take a parameter. */
		ModeParameterCase("b", whenSet: true, hasParameter: true),
		ModeParameterCase("b", whenSet: false, hasParameter: true),
		ModeParameterCase("e", whenSet: false, hasParameter: true),
		ModeParameterCase("I", whenSet: true, hasParameter: true),
		/* Class B (settings) always take a parameter. */
		ModeParameterCase("k", whenSet: true, hasParameter: true),
		ModeParameterCase("k", whenSet: false, hasParameter: true),
		/* Class C takes a parameter only when the mode is set. */
		ModeParameterCase("l", whenSet: true, hasParameter: true),
		ModeParameterCase("l", whenSet: false, hasParameter: false),
		/* Class D never takes a parameter. */
		ModeParameterCase("i", whenSet: true, hasParameter: false),
		ModeParameterCase("m", whenSet: false, hasParameter: false),
		ModeParameterCase("t", whenSet: true, hasParameter: false),
		/* Prefix modes behave like class B. */
		ModeParameterCase("o", whenSet: true, hasParameter: true),
		ModeParameterCase("v", whenSet: false, hasParameter: true),
		/* Unknown modes take no parameter. */
		ModeParameterCase("Z", whenSet: true, hasParameter: false),
		ModeParameterCase("Z", whenSet: false, hasParameter: false),
	]

	@Test(arguments: Self.modeParameterCases)
	func appliesChannelModeParameterPolicy(testCase: ModeParameterCase) {
		let supportInfo = Self.supportInfo("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")

		#expect(
			supportInfo.modeHasParameter(testCase.modeSymbol, whenModeIsSet: testCase.whenSet)
				== testCase.hasParameter
		)
	}

	// MARK: - PREFIX

	struct PrefixCase: Sendable {
		let modeSymbol: String
		let character: String
		let rank: UInt

		init(_ modeSymbol: String, _ character: String, rank: UInt) {
			self.modeSymbol = modeSymbol
			self.character = character
			self.rank = rank
		}
	}

	/// `PREFIX=(qaohv)~&@%+` ranks earlier symbols higher.
	nonisolated static let prefixCases: [PrefixCase] = [
		PrefixCase("q", "~", rank: 100),
		PrefixCase("a", "&", rank: 99),
		PrefixCase("o", "@", rank: 98),
		PrefixCase("h", "%", rank: 97),
		PrefixCase("v", "+", rank: 96),
	]

	@Test(arguments: Self.prefixCases)
	func ranksUserPrefixesInAdvertisedOrder(testCase: PrefixCase) {
		let supportInfo = Self.supportInfo("PREFIX=(qaohv)~&@%+")

		#expect(supportInfo.userPrefix(forModeSymbol: testCase.modeSymbol) == testCase.character)
		#expect(supportInfo.modeSymbol(forUserPrefix: testCase.character) == testCase.modeSymbol)
		#expect(supportInfo.rankForUserPrefix(withMode: testCase.modeSymbol) == testCase.rank)
		#expect(supportInfo.modeSymbolIsUserPrefix(testCase.modeSymbol))
		#expect(supportInfo.characterIsUserPrefix(testCase.character))
	}

	@Test
	func unknownPrefixesHaveNoRank() {
		let supportInfo = Self.supportInfo("PREFIX=(ov)@+")

		#expect(supportInfo.rankForUserPrefix(withMode: "q") == 0)
		#expect(supportInfo.modeSymbolIsUserPrefix("q") == false)
		#expect(supportInfo.characterIsUserPrefix("~") == false)
		#expect(supportInfo.userPrefix(forModeSymbol: "q") == nil)
	}

	/// Malformed PREFIX tokens are ignored; the defaults survive.
	@Test(arguments: ["PREFIX=", "PREFIX=(ov)@", "PREFIX=ov@+", "PREFIX=()", "PREFIX=(ov", "PREFIX=(o)v)@+"])
	func malformedPrefixTokensKeepTheDefaults(configuration: String) {
		let supportInfo = Self.supportInfo(configuration)

		#expect(supportInfo.userPrefix(forModeSymbol: "o") == "@")
		#expect(supportInfo.userPrefix(forModeSymbol: "v") == "+")
	}

	// MARK: - Numeric limits

	@Test
	func readsNumericLimits() {
		let supportInfo = Self.supportInfo(
			"AWAYLEN=200 KICKLEN=255 TOPICLEN=390 CHANNELLEN=64 KEYLEN=32 LINELEN=512 MODES=6 NICKLEN=20"
		)

		#expect(supportInfo.maximumAwayLength == 200)
		#expect(supportInfo.maximumKickLength == 255)
		#expect(supportInfo.maximumTopicLength == 390)
		#expect(supportInfo.maximumChannelNameLength == 64)
		#expect(supportInfo.maximumKeyLength == 32)
		#expect(supportInfo.maximumLineLength == 512)
		#expect(supportInfo.maximumModeCount == 6)
		#expect(supportInfo.maximumNicknameLength == 20)
	}

	/// Non-positive and non-numeric values leave the previous value in place.
	@Test(arguments: ["AWAYLEN=0", "AWAYLEN=-5", "AWAYLEN=abc", "AWAYLEN"])
	func rejectsNonPositiveLengths(configuration: String) {
		let supportInfo = Self.supportInfo("AWAYLEN=200 \(configuration)")

		#expect(supportInfo.maximumAwayLength == 200)
	}

	@Test
	func defaultsApplyBeforeAnyToken() {
		let supportInfo = IRCISupportInfo()

		#expect(supportInfo.maximumNicknameLength == UInt(IRCProtocolLimits.defaultNicknameMaximumLength))
		#expect(supportInfo.maximumModeCount == UInt(IRCProtocolLimits.maximumNodesPerModeCommand))
		#expect(supportInfo.maximumAwayLength == 0)
		#expect(supportInfo.channelNamePrefixes == ["#"])
		#expect(supportInfo.caseMapping == .rfc1459)
		#expect(supportInfo.configurationReceived == false)
	}

	struct ChannelLimitCase: Sendable {
		let channel: String
		let limit: UInt

		init(_ channel: String, _ limit: UInt) {
			self.channel = channel
			self.limit = limit
		}
	}

	@Test(arguments: [
		ChannelLimitCase("#chan", 25),
		ChannelLimitCase("&local", 10),
		ChannelLimitCase("!other", 10),
		ChannelLimitCase("+modeless", 0),
		ChannelLimitCase("", 0),
	])
	func readsChannelLimitsPerPrefix(testCase: ChannelLimitCase) {
		let supportInfo = Self.supportInfo("CHANLIMIT=#:25,&!:10")

		#expect(supportInfo.channelLimit(forChannelNamed: testCase.channel) == testCase.limit)
	}

	struct TargetLimitCase: Sendable {
		let command: String
		let limit: UInt

		init(_ command: String, _ limit: UInt) {
			self.command = command
			self.limit = limit
		}
	}

	@Test(arguments: [
		TargetLimitCase("PRIVMSG", 4),
		TargetLimitCase("privmsg", 4),
		TargetLimitCase("NOTICE", 3),
		/* Commands without a TARGMAX entry fall back to MAXTARGETS. */
		TargetLimitCase("JOIN", 7),
		TargetLimitCase("UNKNOWN", 7),
	])
	func readsMaximumTargets(testCase: TargetLimitCase) {
		let supportInfo = Self.supportInfo("MAXTARGETS=7 TARGMAX=PRIVMSG:4,NOTICE:3")

		#expect(supportInfo.maximumTargets(forCommand: testCase.command) == testCase.limit)
	}

	@Test
	func chunksTargetsByLimit() {
		let targets = ["a", "b", "c", "d", "e"]

		#expect(IRCISupportInfo.chunkTargets(targets, limit: 2) == [["a", "b"], ["c", "d"], ["e"]])
		#expect(IRCISupportInfo.chunkTargets(targets, limit: 0) == [["a"], ["b"], ["c"], ["d"], ["e"]])
		#expect(IRCISupportInfo.chunkTargets([], limit: 3).isEmpty)
	}

	// MARK: - Other tokens and non-crash behaviour

	@Test
	func readsCollectionTokens() {
		let supportInfo = Self.supportInfo(
			"CHANTYPES=#& STATUSMSG=@+ MAXLIST=beI:100 EXTBAN=~,qjm ELIST=CTU"
				+ " CLIENTTAGDENY=*,-typing NETWORK=Example SILENCE=15 WHOX SAFELIST UTF8ONLY"
		)

		#expect(supportInfo.channelNamePrefixes == ["#", "&"])
		#expect(supportInfo.statusMessageModeSymbols == ["@", "+"])
		#expect(supportInfo.maximumListEntries(forModeSymbol: ChannelModeSymbol("b")) == 100)
		#expect(supportInfo.maximumListEntries(forModeSymbol: ChannelModeSymbol("q")) == 0)
		#expect(supportInfo.extendedBanPrefix == "~")
		#expect(supportInfo.extendedBanTypes == ["q", "j", "m"])
		#expect(supportInfo.extendedListSupportsToken("c"))
		#expect(supportInfo.extendedListSupportsToken("z") == false)
		#expect(supportInfo.isClientTagDenied("anything"))
		#expect(supportInfo.isClientTagDenied("typing") == false)
		#expect(supportInfo.networkName == "Example")
		#expect(supportInfo.silenceSupported)
		#expect(supportInfo.maximumSilenceEntries == 15)
		#expect(supportInfo.whoxSupported)
		#expect(supportInfo.safeListSupported)
		#expect(supportInfo.utf8Only)
		#expect(supportInfo.configurationReceived)
	}

	@Test
	func extractsStatusMessagePrefixes() {
		let supportInfo = Self.supportInfo("STATUSMSG=@+ CHANTYPES=#&")

		#expect(supportInfo.extractStatusMessagePrefix(fromChannelNamed: "@#chan") == "@")
		#expect(supportInfo.extractStatusMessagePrefix(fromChannelNamed: "+&chan") == "+")
		#expect(supportInfo.extractStatusMessagePrefix(fromChannelNamed: "#chan") == "")
		#expect(supportInfo.extractStatusMessagePrefix(fromChannelNamed: "@") == "")
	}

	@Test
	func negatedTokensResetTheSetting() {
		let supportInfo = Self.supportInfo("AWAYLEN=200 CHANTYPES=#&")

		supportInfo.processConfigurationData("-AWAYLEN -CHANTYPES")

		#expect(supportInfo.maximumAwayLength == 0)
		#expect(supportInfo.channelNamePrefixes == ["#"])
	}

	@Test
	func resetRestoresDefaults() {
		let supportInfo = Self.supportInfo("AWAYLEN=200 PREFIX=(qaohv)~&@%+ CASEMAPPING=ascii")

		supportInfo.reset()

		#expect(supportInfo.maximumAwayLength == 0)
		#expect(supportInfo.caseMapping == .rfc1459)
		#expect(supportInfo.userPrefix(forModeSymbol: "o") == "@")
		#expect(supportInfo.userPrefix(forModeSymbol: "q") == nil)
		#expect(supportInfo.configurationReceived == false)
	}

	/// Tokens that no server should send must not crash the parser.
	@Test(arguments: [
		"",
		"   ",
		"=",
		"=value",
		"-",
		"--",
		"-NOSUCHTOKEN",
		"CHANMODES=",
		"CHANMODES=,,,",
		"CHANMODES=a,b,c,d,e,f",
		"CHANLIMIT=:",
		"CHANLIMIT=#",
		"TARGMAX=PRIVMSG:",
		"MAXLIST=b:0",
		"EXTBAN=",
		"EXTBAN=,",
		"PREFIX=()x",
		"STATUSMSG=",
		"SILENCE=",
		"NETWORK=",
	])
	func toleratesMalformedTokens(configuration: String) {
		let supportInfo = Self.supportInfo(configuration)

		/* The only contract is that parsing completed and the object is usable. */
		#expect(supportInfo.casefoldString("A") == "a")
	}
}
