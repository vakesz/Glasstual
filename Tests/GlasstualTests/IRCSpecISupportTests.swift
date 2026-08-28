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

/// RPL_ISUPPORT (numeric 005) tokens, against the parameter definitions in
/// modern.ircdocs.horse ("Feature Advertisement") and RFC 2812 §5 for the
/// numerics that carry them.
@Suite("ISUPPORT tokens")
@MainActor
struct IRCSpecISupportTests {
	private func supportInfo(_ tokens: String...) -> IRCISupportInfo {
		let info = IRCISupportInfo()

		for token in tokens {
			info.processConfigurationData(token)
		}

		return info
	}

	// MARK: - PREFIX

	/// `PREFIX=(modes)prefixes`: the two halves are positional, ordered from
	/// most to least privileged.
	@Test("PREFIX: modes and characters pair up in rank order")
	func prefixPairsInRankOrder() {
		let info = supportInfo("PREFIX=(qaohv)~&@%+")

		#expect(info.userPrefix(forModeSymbol: "q") == "~")
		#expect(info.userPrefix(forModeSymbol: "a") == "&")
		#expect(info.userPrefix(forModeSymbol: "o") == "@")
		#expect(info.userPrefix(forModeSymbol: "h") == "%")
		#expect(info.userPrefix(forModeSymbol: "v") == "+")

		#expect(info.modeSymbol(forUserPrefix: "~") == "q")
		#expect(info.characterIsUserPrefix("%"))
		#expect(info.characterIsUserPrefix("!") == false)

		#expect(info.rankForUserPrefix(withMode: "q") > info.rankForUserPrefix(withMode: "o"))
		#expect(info.rankForUserPrefix(withMode: "o") > info.rankForUserPrefix(withMode: "v"))
		#expect(info.rankForUserPrefix(withMode: "z") == 0)
	}

	/// The default when a server says nothing is the RFC 1459 §4.2.3 pair.
	@Test("PREFIX: the default is (ov)@+")
	func prefixDefaultsToOpAndVoice() {
		let info = supportInfo()

		#expect(info.userPrefix(forModeSymbol: "o") == "@")
		#expect(info.userPrefix(forModeSymbol: "v") == "+")
	}

	/// A malformed `PREFIX` says nothing usable, so the previous table has to
	/// survive rather than being replaced by a half-parsed one.
	@Test(
		"PREFIX: a malformed token is ignored",
		arguments: ["PREFIX=ov@+", "PREFIX=(ov@+", "PREFIX=(ovh)@+", "PREFIX=()"]
	)
	func malformedPrefixIsIgnored(_ token: String) {
		let info = supportInfo(token)

		#expect(info.userPrefix(forModeSymbol: "o") == "@")
		#expect(info.userPrefix(forModeSymbol: "v") == "+")
	}

	/// Every mode named in `PREFIX` is also a channel mode that takes a
	/// nickname parameter, whether or not `CHANMODES` mentioned it.
	@Test("PREFIX: prefix modes always take a parameter")
	func prefixModesTakeAParameter() {
		let info = supportInfo("PREFIX=(qaohv)~&@%+")

		for mode in ["q", "a", "o", "h", "v"] {
			#expect(info.modeHasParameter(mode, whenModeIsSet: true))
			#expect(info.modeHasParameter(mode, whenModeIsSet: false))
		}
	}

	// MARK: - CHANMODES

	/// `CHANMODES=A,B,C,D`: group A is a list mode and group B is a setting,
	/// both always parameterised; group C is parameterised only when set;
	/// group D never is. Groups past D have no defined meaning.
	@Test("CHANMODES: the parameter rule for each group")
	func chanModesGroupsDecideParameters() {
		let info = supportInfo("CHANMODES=beI,k,l,imnpst")

		#expect(info.modeHasParameter("b", whenModeIsSet: true))
		#expect(info.modeHasParameter("b", whenModeIsSet: false))
		#expect(info.modeHasParameter("k", whenModeIsSet: true))
		#expect(info.modeHasParameter("k", whenModeIsSet: false))
		#expect(info.modeHasParameter("l", whenModeIsSet: true))
		#expect(info.modeHasParameter("l", whenModeIsSet: false) == false)
		#expect(info.modeHasParameter("t", whenModeIsSet: true) == false)
		#expect(info.modeHasParameter("t", whenModeIsSet: false) == false)
	}

	/// A mode the server never classified takes no parameter: guessing would
	/// eat the next token and desynchronise the whole MODE line.
	@Test("CHANMODES: an unlisted mode takes no parameter")
	func unlistedModesTakeNoParameter() {
		let info = supportInfo("CHANMODES=beI,k,l,imnpst")

		#expect(info.modeHasParameter("Z", whenModeIsSet: true) == false)
	}

	/// Groups past D exist on some servers and have no agreed meaning, so the
	/// modes in them must not be given a parameter policy.
	@Test("CHANMODES: groups past D are ignored")
	func groupsPastDAreIgnored() {
		let info = supportInfo("CHANMODES=b,k,l,imnpst,XY")

		#expect(info.modeHasParameter("X", whenModeIsSet: true) == false)
		#expect(info.modeHasParameter("Y", whenModeIsSet: false) == false)
	}

	// MARK: - CASEMAPPING

	/// `CASEMAPPING=rfc1459`: `[`, `]`, `\` and `~` are the upper-case forms
	/// of `{`, `}`, `|` and `^` (RFC 1459 §2.2).
	@Test("CASEMAPPING=rfc1459 folds the four Scandinavian pairs")
	func rfc1459CaseMapping() {
		let info = supportInfo("CASEMAPPING=rfc1459")

		#expect(info.casefoldString("Nick[]\\~") == "nick{}|^")
		#expect(info.casefoldString("#Chan[]") == "#chan{}")
	}

	/// `CASEMAPPING=strict-rfc1459` is the same minus `~`/`^`.
	@Test("CASEMAPPING=strict-rfc1459 leaves ~ alone")
	func strictRFC1459CaseMapping() {
		let info = supportInfo("CASEMAPPING=strict-rfc1459")

		#expect(info.casefoldString("Nick[]\\~") == "nick{}|~")
	}

	/// `CASEMAPPING=ascii` folds A-Z only.
	@Test("CASEMAPPING=ascii folds A-Z only")
	func asciiCaseMapping() {
		let info = supportInfo("CASEMAPPING=ascii")

		#expect(info.casefoldString("Nick[]\\~") == "nick[]\\~")
	}

	/// Case folding is ASCII-only in every mapping: a nickname is a byte
	/// string, and folding it with Unicode rules would make `İ` equal `i`.
	@Test("CASEMAPPING: folding never applies Unicode case rules", arguments: ["rfc1459", "strict-rfc1459", "ascii"])
	func caseMappingIsASCIIOnly(_ mapping: String) {
		let info = supportInfo("CASEMAPPING=\(mapping)")

		#expect(info.casefoldString("İ") == "İ")
		#expect(info.casefoldString("Ä") == "Ä")
	}

	/// An unrecognised mapping falls back to rfc1459, the mapping a server
	/// that sends no `CASEMAPPING` at all is assumed to use.
	@Test("CASEMAPPING: an unknown value falls back to rfc1459")
	func unknownCaseMappingFallsBack() {
		#expect(supportInfo("CASEMAPPING=utf8-only").casefoldString("A[") == "a{")
		#expect(supportInfo().casefoldString("A[") == "a{")
	}

	/// Nickname comparison is what the mapping is for: two spellings that fold
	/// together are the same user.
	@Test("CASEMAPPING: the client compares its own nickname with the mapping")
	func clientComparesNicknamesWithTheMapping() {
		let client = GLTTestClient(configDictionary: ["nickname": "user[at]home"])

		client.supportInfo.processConfigurationData("CASEMAPPING=rfc1459")

		#expect(client.nicknameIsMyself("user{at}home"))
		#expect(client.nicknameIsMyself("USER{AT}HOME"))
		#expect(client.nicknameIsMyself("user(at)home") == false)
	}

	// MARK: - CHANTYPES and STATUSMSG

	@Test("CHANTYPES lists the prefixes that start a channel name")
	func chanTypesListsChannelPrefixes() {
		let client = GLTTestClient()

		client.supportInfo.processConfigurationData("CHANTYPES=#&")

		#expect(client.supportInfo.channelNamePrefixes == ["#", "&"])
		#expect(client.stringIsChannelName("#chan"))
		#expect(client.stringIsChannelName("&chan"))
		#expect(client.stringIsChannelName("+chan") == false)
		#expect(client.stringIsChannelName("nick") == false)
	}

	/// `STATUSMSG=@+`: a target may be prefixed with one of these to reach
	/// only the members holding that prefix.
	@Test("STATUSMSG marks a prefixed channel target")
	func statusMessagePrefixIsRecognised() {
		let info = supportInfo("STATUSMSG=@+", "PREFIX=(ov)@+", "CHANTYPES=#")

		#expect(info.extractStatusMessagePrefix(fromChannelNamed: "@#chan") == "@")
		#expect(info.extractStatusMessagePrefix(fromChannelNamed: "+#chan") == "+")
		#expect(info.extractStatusMessagePrefix(fromChannelNamed: "#chan") == "")
		#expect(info.extractStatusMessagePrefix(fromChannelNamed: "%#chan") == "")
		#expect(info.statusMessagePrefix(forModeSymbol: "o") == "@")
		#expect(info.statusMessagePrefix(forModeSymbol: "v") == "+")
	}

	/// A prefix character only starts a status message when a channel name
	/// follows it; `@nick` is a plain nickname.
	@Test("STATUSMSG: a prefix without a channel name is not a status target")
	func statusMessageNeedsAChannelName() {
		let info = supportInfo("STATUSMSG=@+", "CHANTYPES=#")

		#expect(info.extractStatusMessagePrefix(fromChannelNamed: "@nick") == "")
		#expect(info.extractStatusMessagePrefix(fromChannelNamed: "@") == "")
	}

	// MARK: - TARGMAX, MAXTARGETS and MODES

	/// `TARGMAX=CMD:n[,CMD:n]`: a command with no number after the colon has
	/// no limit, which the client stores as zero and reads as "unlimited".
	@Test("TARGMAX: per-command limits, and an empty limit meaning unlimited")
	func targetMaximumsAreParsedPerCommand() {
		let info = supportInfo("TARGMAX=PRIVMSG:3,NOTICE:3,JOIN:,KICK:1")

		#expect(info.maximumTargets(forCommand: "PRIVMSG") == 3)
		#expect(info.maximumTargets(forCommand: "privmsg") == 3)
		#expect(info.maximumTargets(forCommand: "JOIN") == 0)
		#expect(info.maximumTargets(forCommand: "KICK") == 1)
	}

	/// `MAXTARGETS` is the older, command-agnostic form and stands in for any
	/// command `TARGMAX` did not name.
	@Test("MAXTARGETS covers commands TARGMAX did not name")
	func maximumTargetsCoversUnnamedCommands() {
		let info = supportInfo("MAXTARGETS=4", "TARGMAX=PRIVMSG:2")

		#expect(info.maximumTargets(forCommand: "PRIVMSG") == 2)
		#expect(info.maximumTargets(forCommand: "NOTICE") == 4)
	}

	/// Targets go out in chunks no larger than the advertised limit.
	@Test("TARGMAX: targets are chunked to the limit")
	func targetsAreChunkedToTheLimit() {
		let targets = ["#a", "#b", "#c", "#d", "#e"]

		#expect(IRCISupportInfo.chunkTargets(targets, limit: 2) == [["#a", "#b"], ["#c", "#d"], ["#e"]])
		#expect(IRCISupportInfo.chunkTargets(targets, limit: 5) == [targets])
	}

	/// `MODES=n` is how many parameterised modes may ride on one MODE command.
	@Test("MODES: the mode count per command, with an RFC default")
	func modeCountPerCommand() {
		#expect(supportInfo("MODES=6").maximumModeCount == 6)
		#expect(supportInfo().maximumModeCount == UInt(IRCProtocolLimits.maximumNodesPerModeCommand))
	}

	// MARK: - Length limits

	/// The `*LEN` tokens are byte budgets the client has to respect before it
	/// sends, because a server silently truncates instead of erroring.
	@Test("The *LEN tokens are read as byte budgets")
	func lengthTokensAreRead() {
		let info = supportInfo(
			"AWAYLEN=200 CHANNELLEN=64 KICKLEN=255 NICKLEN=16 TOPICLEN=390 KEYLEN=23 LINELEN=1024"
		)

		#expect(info.maximumAwayLength == 200)
		#expect(info.maximumChannelNameLength == 64)
		#expect(info.maximumKickLength == 255)
		#expect(info.maximumNicknameLength == 16)
		#expect(info.maximumTopicLength == 390)
		#expect(info.maximumKeyLength == 23)
		#expect(info.maximumLineLength == 1024)
	}

	/// Truncation is by bytes, not characters, and never splits a character in
	/// half — a message truncated mid-sequence would be invalid UTF-8.
	@Test("The *LEN budgets truncate by bytes without splitting a character")
	func truncationCountsBytes() {
		#expect(ClientWireUtilities.truncated("abcdef", toByteCount: 3) == "abc")
		#expect(ClientWireUtilities.truncated("abc", toByteCount: 10) == "abc")
		// Each "é" is two bytes, so a four-byte budget holds exactly two.
		#expect(ClientWireUtilities.truncated("ééé", toByteCount: 4) == "éé")
		#expect(ClientWireUtilities.truncated("ééé", toByteCount: 5) == "éé")
		// Zero means the server advertised no limit.
		#expect(ClientWireUtilities.truncated("abcdef", toByteCount: 0) == "abcdef")
	}

	/// A nickname the server cannot accept is not a nickname: the length bound
	/// comes from `NICKLEN` once the server has advertised it.
	@Test("NICKLEN bounds what the client will treat as a nickname")
	func nicknameLengthIsBounded() {
		let client = GLTTestClient()

		client.supportInfo.processConfigurationData("NICKLEN=8")

		#expect(client.stringIsNickname("shortnic"))
		#expect(client.stringIsNickname("muchtoolongnickname") == false)
	}

	// MARK: - Token syntax

	/// modern.ircdocs.horse: "The client MUST NOT assume that a parameter is
	/// present" — a bare token is a flag, and `-TOKEN` withdraws a previously
	/// advertised one.
	@Test("A token may be withdrawn with a leading -")
	func tokensCanBeWithdrawn() {
		let info = supportInfo("NICKLEN=16 CHANTYPES=#& SAFELIST WHOX")

		#expect(info.maximumNicknameLength == 16)
		#expect(info.safeListSupported)
		#expect(info.whoxSupported)

		info.processConfigurationData("-NICKLEN -CHANTYPES -SAFELIST -WHOX")

		#expect(info.maximumNicknameLength == UInt(IRCProtocolLimits.defaultNicknameMaximumLength))
		#expect(info.channelNamePrefixes == ["#"])
		#expect(info.safeListSupported == false)
		#expect(info.whoxSupported == false)
	}

	/// modern.ircdocs.horse: for the tokens whose value is a list of
	/// characters, an explicitly empty value says the server has none of them.
	/// That is not the same as the bare token, which says nothing.
	@Test("PREFIX=, CHANTYPES= and STATUSMSG= mean the server has none")
	func anEmptyValueMeansNone() {
		let info = supportInfo("PREFIX=(ov)@+ CHANTYPES=#& STATUSMSG=@+")

		#expect(info.userPrefix(forModeSymbol: "o") == "@")
		#expect(info.channelNamePrefixes == ["#", "&"])
		#expect(info.statusMessageModeSymbols == ["@", "+"])

		info.processConfigurationData("PREFIX= CHANTYPES= STATUSMSG=")

		#expect(info.userPrefix(forModeSymbol: "o") == nil)
		#expect(info.userPrefix(forModeSymbol: "v") == nil)
		#expect(info.modeSymbolIsUserPrefix("o") == false)
		#expect(info.channelNamePrefixes.isEmpty)
		#expect(info.statusMessageModeSymbols.isEmpty)
	}

	/// A server with no channel types has no channel names either, so nothing
	/// the user types can be mistaken for one.
	@Test("CHANTYPES= leaves no string that reads as a channel name")
	func anEmptyChannelTypeListRecognisesNoChannels() {
		let client = GLTTestClient()

		client.supportInfo.processConfigurationData("CHANTYPES=")

		#expect(client.stringIsChannelName("#chan") == false)
		#expect(client.stringIsChannelName("&chan") == false)
	}

	/// Only those three tokens read an empty value that way: everywhere else
	/// `KEY=` is the bare token, and must not be read as the number zero or as
	/// an empty list that wipes a default.
	@Test("An empty value elsewhere is still just the bare token")
	func anEmptyValueElsewhereIsTheBareToken() {
		let info = supportInfo("NICKLEN=16 CHANMODES=beI,k,l,imnpst")

		info.processConfigurationData("NICKLEN= CHANMODES= SAFELIST=")

		#expect(info.maximumNicknameLength == 16)
		#expect(info.modeHasParameter("b", whenModeIsSet: true))
		#expect(info.safeListSupported)
	}

	/// `-TOKEN` still withdraws the three, which puts the defaults back rather
	/// than leaving the empty list behind.
	@Test("-PREFIX and -CHANTYPES restore the defaults after an empty value")
	func withdrawingRestoresTheDefaults() {
		let info = supportInfo("PREFIX= CHANTYPES=")

		#expect(info.channelNamePrefixes.isEmpty)

		info.processConfigurationData("-PREFIX -CHANTYPES")

		#expect(info.channelNamePrefixes == ["#"])
		#expect(info.userPrefix(forModeSymbol: "o") == "@")
	}

	/// Token names are case-insensitive on the wire even though every server
	/// sends them upper-cased.
	@Test("Token names are matched case-insensitively")
	func tokenNamesAreCaseInsensitive() {
		#expect(supportInfo("nicklen=9").maximumNicknameLength == 9)
		#expect(supportInfo("NetWork=ExampleNet").networkName == "ExampleNet")
	}

	/// A value that is not a number says nothing, and must not be read as
	/// zero, which would mean "no limit" to every caller.
	@Test("A non-numeric length is ignored rather than read as zero")
	func nonNumericLengthsAreIgnored() {
		let info = supportInfo("NICKLEN=16")

		info.processConfigurationData("NICKLEN=lots")

		#expect(info.maximumNicknameLength == 16)
	}

	/// The whole line is one 005 parameter list, so tokens are separated by
	/// spaces and parsed independently of each other.
	@Test("A whole 005 line is parsed token by token")
	func wholeLinesAreParsed() {
		let info = supportInfo(
			"CHANTYPES=# EXCEPTS INVEX CHANMODES=eIbq,k,flj,CFLMPQScgimnprstz "
				+ "CHANLIMIT=#:120 PREFIX=(ov)@+ MAXLIST=bqeI:100 MODES=4 NETWORK=Libera.Chat "
				+ "STATUSMSG=@+ CASEMAPPING=rfc1459 NICKLEN=16 CHANNELLEN=50 TOPICLEN=390"
		)

		#expect(info.channelNamePrefixes == ["#"])
		#expect(info.banExceptionModeSymbol == "e")
		#expect(info.inviteExceptionModeSymbol == "I")
		#expect(info.networkName == "Libera.Chat")
		#expect(info.channelLimit(forChannelNamed: "#chan") == 120)
		#expect(info.maximumListEntries(forModeSymbol: ChannelModeSymbol("b")) == 100)
		#expect(info.modeHasParameter("f", whenModeIsSet: true))
		#expect(info.modeHasParameter("f", whenModeIsSet: false) == false)
		#expect(info.modeHasParameter("z", whenModeIsSet: true) == false)
	}

	/// `EXCEPTS` and `INVEX` may be sent bare, in which case the mode letters
	/// are the RFC 2811 §4 defaults.
	@Test("EXCEPTS and INVEX fall back to their default mode letters")
	func banAndInviteExceptionDefaults() {
		let info = supportInfo("EXCEPTS INVEX")

		#expect(info.banExceptionModeSymbol == "e")
		#expect(info.inviteExceptionModeSymbol == "I")
		#expect(info.isListSupported(.banException))
		#expect(info.isListSupported(.inviteException))
	}
}
