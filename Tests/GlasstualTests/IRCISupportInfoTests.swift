/* *********************************************************************
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

import Foundation
@testable import Glasstual
import Testing

typealias SupportInfo = Glasstual.IRCISupportInfo

@MainActor
@Suite("ISUPPORT parsing")
struct IRCISupportInfoTests {
	@Test("A server that says nothing about case mapping gets RFC 1459")
	func defaultCaseMappingIsRFC1459() {
		let supportInfo = supportInfoWithConfiguration("NETWORK=Example")

		#expect(supportInfo.caseMapping == IRCISupportInfoCaseMapping.rfc1459)
		#expect(supportInfo.casefoldString("Nick[]\\~") == "nick{}|^")
	}

	@Test("ASCII case mapping leaves the bracket characters alone")
	func asciiCaseMappingLeavesBracketsAlone() {
		let supportInfo = supportInfoWithConfiguration("CASEMAPPING=ascii")

		#expect(supportInfo.caseMapping == IRCISupportInfoCaseMapping.ascii)
		#expect(supportInfo.casefoldString("Nick[]\\~") == "nick[]\\~")
	}

	@Test("Strict RFC 1459 folds the brackets but not the tilde")
	func strictRFC1459DoesNotFoldTilde() {
		let supportInfo = supportInfoWithConfiguration("CASEMAPPING=strict-rfc1459")

		#expect(supportInfo.caseMapping == IRCISupportInfoCaseMapping.strictRFC1459)
		#expect(supportInfo.casefoldString("A[]\\~") == "a{}|~")
	}

	@Test("Case folding is ASCII only, so accented letters keep their case")
	func nonASCIICharactersAreNotFolded() {
		let rfc = supportInfoWithConfiguration("CASEMAPPING=rfc1459")
		let ascii = supportInfoWithConfiguration("CASEMAPPING=ascii")

		#expect(rfc.casefoldString("ÄbÇ") == "ÄbÇ")
		#expect(rfc.casefoldString("ÄB[Ç]") == "Äb{Ç}")
		#expect(ascii.casefoldString("ÄbÇ") == "ÄbÇ")
		#expect(ascii.casefoldString("ŞİRİN") == "Şİrİn")
	}

	@Test("CHANMODES sorts the modes by when they take a parameter")
	func channelModesAreParsedIntoParameterClasses() {
		let supportInfo = supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst")

		#expect(supportInfo.channelModeKinds["b"] == .list)
		#expect(supportInfo.channelModeKinds["k"] == .setting)
		#expect(supportInfo.channelModeKinds["l"] == .settingWhenSet)
		#expect(supportInfo.channelModeKinds["t"] == .flag)

		#expect(supportInfo.modeHasParameter("b", whenModeIsSet: true))
		#expect(supportInfo.modeHasParameter("b", whenModeIsSet: false))
		#expect(supportInfo.modeHasParameter("k", whenModeIsSet: false))
		#expect(supportInfo.modeHasParameter("l", whenModeIsSet: true))

		#expect(supportInfo.modeHasParameter("l", whenModeIsSet: false) == false)
		#expect(supportInfo.modeHasParameter("t", whenModeIsSet: true) == false)
	}

	@Test("PREFIX is read in rank order, highest first")
	func prefixIsParsedInRankOrder() {
		let supportInfo = supportInfoWithConfiguration("PREFIX=(qaohv)~&@%+")

		#expect(supportInfo.userModePrefixPairs.map(\.modeSymbol) == ["q", "a", "o", "h", "v"])
		#expect(supportInfo.userModePrefixPairs.map(\.character) == ["~", "&", "@", "%", "+"])
		#expect(supportInfo.modeSymbol(forUserPrefix: "@") == "o")
		#expect(supportInfo.userPrefix(forModeSymbol: "v") == "+")

		#expect(supportInfo.characterIsUserPrefix("%"))

		#expect(supportInfo.characterIsUserPrefix("#") == false)

		#expect(supportInfo.rankForUserPrefix(withMode: "q") == IRCISupportUserModes.highestPrefixRank)

		#expect(supportInfo.rankForUserPrefix(withMode: "v") < supportInfo.rankForUserPrefix(withMode: "o"))
		/* Prefix modes always take a parameter. */
		#expect(supportInfo.modeHasParameter("o", whenModeIsSet: false))
	}

	@Test("Parsing a mode string consumes a parameter for each mode that takes one")
	func parseModesUsesChannelModeClasses() {
		let supportInfo = supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let modes = supportInfo.parseModes("+nt-k+l secret 10")

		#expect(modes.count == 4)

		#expect(modes[0].modeSymbol == "n")

		#expect(modes[0].modeIsSet)

		#expect(modes[2].modeSymbol == "k")

		#expect(modes[2].modeIsSet == false)

		#expect(modes[2].modeParameter == "secret")
		#expect(modes[3].modeSymbol == "l")
		#expect(modes[3].modeParameter == "10")
	}

	@Test("Unsetting a mode that needs no parameter leaves the next word for the next mode")
	func parseModesDoesNotConsumeParameterWhenUnsetModeDoesNotRequireOne() {
		let supportInfo = supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let modes = supportInfo.parseModes("-l leftover +t")

		#expect(modes.count == 2)

		#expect(modes[0].modeSymbol == "l")

		#expect(modes[0].modeIsSet == false)

		#expect(modes[0].modeParameter == nil)

		#expect(modes[1].modeSymbol == "t")

		#expect(modes[1].modeIsSet)
	}

	@Test("A mode whose parameter never arrived is still reported")
	func parseModesAllowsMissingRequiredParameter() {
		let supportInfo = supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let modes = supportInfo.parseModes("+k")

		#expect(modes.count == 1)

		#expect(modes[0].modeSymbol == "k")

		#expect(modes[0].modeIsSet)

		#expect(modes[0].modeParameter == nil)
	}

	@Test("The limit tokens set the channel, target and list ceilings, and chunking respects them")
	func limitTokensAndTargetChunking() {
		let supportInfo =
			supportInfoWithConfiguration("CHANLIMIT=#&:50,+: TARGMAX=privmsg:4,JOIN: MAXTARGETS=3 MAXLIST=beI:60")

		#expect(supportInfo.channelLimit(forChannelNamed: "#chat") == 50)
		#expect(supportInfo.channelLimit(forChannelNamed: "&local") == 50)
		#expect(supportInfo.channelLimit(forChannelNamed: "+modeless") == 0)
		#expect(supportInfo.maximumTargets(forCommand: "PRIVMSG") == 4)
		#expect(supportInfo.maximumTargets(forCommand: "notice") == 3)
		#expect(supportInfo.maximumTargets(forCommand: "join") == 0)
		#expect(supportInfo.maximumListEntries(forModeSymbol: ChannelModeSymbol("b")) == 60)
		#expect(supportInfo.maximumListEntries(forModeSymbol: ChannelModeSymbol("I")) == 60)

		let targets = ["a", "b", "c", "d", "e"]

		#expect(SupportInfo.chunkTargets(targets, limit: 2) == [["a", "b"], ["c", "d"], ["e"]])

		let conservativeChunks = SupportInfo.chunkTargets(["a", "b"], limit: 0)

		#expect(conservativeChunks == [["a"], ["b"]])
	}

	@Test("A wildcard client tag denial can still name its exceptions")
	func clientTagDenyAllowsExceptionsToWildcard() {
		let supportInfo = supportInfoWithConfiguration("CLIENTTAGDENY=*,-draft/typing,-example/allowed")

		#expect(supportInfo.isClientTagDenied("example/other"))
		#expect(supportInfo.isClientTagDenied("DRAFT/TYPING") == false)
		#expect(supportInfo.isClientTagDenied("example/allowed") == false)
	}

	@Test("EXTBAN splits into its prefix and the types the server offers")
	func extendedBanTokenSeparatesPrefixAndTypes() {
		let supportInfo = supportInfoWithConfiguration("EXTBAN=$,ac")

		#expect(supportInfo.extendedBanPrefix == "$")
		#expect(supportInfo.extendedBanTypes == ["a", "c"])

		#expect(supportInfo.descriptionForExtendedBanMask("$a:account") != nil)

		#expect(supportInfo.descriptionForExtendedBanMask("$q:quiet") == nil)
	}

	@Test("A PREFIX token that cannot be read leaves the defaults standing")
	func malformedPrefixDoesNotReplaceDefaults() {
		let supportInfo = supportInfoWithConfiguration("PREFIX=invalid")

		#expect(supportInfo.userPrefix(forModeSymbol: "o") == "@")
		#expect(supportInfo.userPrefix(forModeSymbol: "v") == "+")
	}

	@Test("Resetting SILENCE clears both the support flag and the limit")
	func resettingSilenceClearsSupportAndLimitTogether() {
		let supportInfo = supportInfoWithConfiguration("SILENCE=25")

		#expect(supportInfo.silenceSupported)
		#expect(supportInfo.maximumSilenceEntries == 25)

		supportInfo.resetSetting("silence")

		#expect(supportInfo.silenceSupported == false)
		#expect(supportInfo.maximumSilenceEntries == 0)
	}

	private func supportInfoWithConfiguration(_ configuration: String) -> SupportInfo {
		let client = GLTTestClient()
		let supportInfo = SupportInfo(client: client)

		supportInfo.processConfigurationData(configuration)

		return supportInfo
	}
}
