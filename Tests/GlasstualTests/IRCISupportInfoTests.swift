@testable import Glasstual
import XCTest

typealias SupportInfo = Glasstual.IRCISupportInfo

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "GLTTestClient.h"
/// #import "ModeInfo.h"
@objc
@MainActor
final class IRCISupportInfoTests: XCTestCase {
	@objc
	func supportInfoWithConfiguration(_ configuration: String) -> SupportInfo {
		let client = GLTTestClient()
		let supportInfo: SupportInfo! = SupportInfo(client: client)

		supportInfo.processConfigurationData(configuration)

		return supportInfo
	}

	@objc
	func testDefaultCaseMappingIsRFC1459() {
		let supportInfo = supportInfoWithConfiguration("NETWORK=Example")

		XCTAssertEqual(supportInfo.caseMapping, IRCISupportInfoCaseMapping.rfc1459)
		XCTAssertEqual(supportInfo.casefoldString("Nick[]\\~"), "nick{}|^")
	}

	@objc
	func testASCIICaseMappingLeavesBracketsAlone() {
		let supportInfo = supportInfoWithConfiguration("CASEMAPPING=ascii")

		XCTAssertEqual(supportInfo.caseMapping, IRCISupportInfoCaseMapping.ascii)
		XCTAssertEqual(supportInfo.casefoldString("Nick[]\\~"), "nick[]\\~")
	}

	@objc
	func testStrictRFC1459DoesNotFoldTilde() {
		let supportInfo = supportInfoWithConfiguration("CASEMAPPING=strict-rfc1459")

		XCTAssertEqual(supportInfo.caseMapping, IRCISupportInfoCaseMapping.strictRFC1459)
		XCTAssertEqual(supportInfo.casefoldString("A[]\\~"), "a{}|~")
	}

	@objc
	func testNonASCIICharactersAreNotFolded() {
		let rfc = supportInfoWithConfiguration("CASEMAPPING=rfc1459")
		let ascii = supportInfoWithConfiguration("CASEMAPPING=ascii")

		XCTAssertEqual(rfc.casefoldString("ÄbÇ"), "ÄbÇ")
		XCTAssertEqual(rfc.casefoldString("ÄB[Ç]"), "Äb{Ç}")
		XCTAssertEqual(ascii.casefoldString("ÄbÇ"), "ÄbÇ")
		XCTAssertEqual(ascii.casefoldString("ŞİRİN"), "Şİrİn")
	}

	@objc
	func testChannelModesAreParsedIntoParameterClasses() {
		let supportInfo = supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst")

		XCTAssertEqual(supportInfo.channelModes["b"], 1)
		XCTAssertEqual(supportInfo.channelModes["k"], 2)
		XCTAssertEqual(supportInfo.channelModes["l"], 3)
		XCTAssertEqual(supportInfo.channelModes["t"], 4)

		XCTAssertTrue(supportInfo.modeHasParameter("b", whenModeIsSet: true))
		XCTAssertTrue(supportInfo.modeHasParameter("b", whenModeIsSet: false))
		XCTAssertTrue(supportInfo.modeHasParameter("k", whenModeIsSet: false))
		XCTAssertTrue(supportInfo.modeHasParameter("l", whenModeIsSet: true))

		XCTAssertFalse(supportInfo.modeHasParameter("l", whenModeIsSet: false))
		XCTAssertFalse(supportInfo.modeHasParameter("t", whenModeIsSet: true))
	}

	@objc
	func testPrefixIsParsedInRankOrder() {
		let supportInfo = supportInfoWithConfiguration("PREFIX=(qaohv)~&@%+")

		XCTAssertEqual(supportInfo.userModeSymbols[IRCISupportUserModes.symbolsKey], ["q", "a", "o", "h", "v"])
		XCTAssertEqual(supportInfo.userModeSymbols[IRCISupportUserModes.charactersKey], ["~", "&", "@", "%", "+"])
		XCTAssertEqual(supportInfo.modeSymbol(forUserPrefix: "@"), "o")
		XCTAssertEqual(supportInfo.userPrefix(forModeSymbol: "v"), "+")

		XCTAssertTrue(supportInfo.characterIsUserPrefix("%"))

		XCTAssertFalse(supportInfo.characterIsUserPrefix("#"))

		XCTAssertEqual(supportInfo.rankForUserPrefix(withMode: "q"), IRCISupportUserModes.highestPrefixRank)

		XCTAssertTrue(supportInfo.rankForUserPrefix(withMode: "v") < supportInfo.rankForUserPrefix(withMode: "o"))
		/* Prefix modes always take a parameter. */
		XCTAssertTrue(supportInfo.modeHasParameter("o", whenModeIsSet: false))
	}

	@objc
	func testParseModesUsesChannelModeClasses() {
		let supportInfo = supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let modes: [ModeInfo]! = supportInfo.parseModes("+nt-k+l secret 10")

		XCTAssertEqual(modes.count, 4)

		XCTAssertEqual(modes[0].modeSymbol, "n")

		XCTAssertTrue(modes[0].modeIsSet)

		XCTAssertEqual(modes[2].modeSymbol, "k")

		XCTAssertFalse(modes[2].modeIsSet)

		XCTAssertEqual(modes[2].modeParameter, "secret")
		XCTAssertEqual(modes[3].modeSymbol, "l")
		XCTAssertEqual(modes[3].modeParameter, "10")
	}

	@objc
	func testParseModesDoesNotConsumeParameterWhenUnsetModeDoesNotRequireOne() {
		let supportInfo = supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let modes: [ModeInfo]! = supportInfo.parseModes("-l leftover +t")

		XCTAssertEqual(modes.count, 2)

		XCTAssertEqual(modes[0].modeSymbol, "l")

		XCTAssertFalse(modes[0].modeIsSet)

		XCTAssertNil(modes[0].modeParameter)

		XCTAssertEqual(modes[1].modeSymbol, "t")

		XCTAssertTrue(modes[1].modeIsSet)
	}

	@objc
	func testParseModesAllowsMissingRequiredParameter() {
		let supportInfo = supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let modes: [ModeInfo]! = supportInfo.parseModes("+k")

		XCTAssertEqual(modes.count, 1)

		XCTAssertEqual(modes[0].modeSymbol, "k")

		XCTAssertTrue(modes[0].modeIsSet)

		XCTAssertNil(modes[0].modeParameter)
	}

	@objc
	func testLimitTokensAndTargetChunking() {
		let supportInfo =
			supportInfoWithConfiguration("CHANLIMIT=#&:50,+: TARGMAX=privmsg:4,JOIN: MAXTARGETS=3 MAXLIST=beI:60")

		XCTAssertEqual(supportInfo.channelLimit(forChannelNamed: "#chat"), 50)
		XCTAssertEqual(supportInfo.channelLimit(forChannelNamed: "&local"), 50)
		XCTAssertEqual(supportInfo.channelLimit(forChannelNamed: "+modeless"), 0)
		XCTAssertEqual(supportInfo.maximumTargets(forCommand: "PRIVMSG"), 4)
		XCTAssertEqual(supportInfo.maximumTargets(forCommand: "notice"), 3)
		XCTAssertEqual(supportInfo.maximumTargets(forCommand: "join"), 0)
		XCTAssertEqual(supportInfo.maximumListEntries(forModeSymbol: "b"), 60)
		XCTAssertEqual(supportInfo.maximumListEntries(forModeSymbol: "I"), 60)

		let targets = ["a", "b", "c", "d", "e"]

		XCTAssertEqual(SupportInfo.chunkTargets(targets, limit: 2), [["a", "b"], ["c", "d"], ["e"]])

		let conservativeChunks = SupportInfo.chunkTargets(["a", "b"], limit: 0)

		XCTAssertEqual(conservativeChunks, [["a"], ["b"]])
	}

	@objc
	func testClientTagDenyAllowsExceptionsToWildcard() {
		let supportInfo = supportInfoWithConfiguration("CLIENTTAGDENY=*,-draft/typing,-example/allowed")

		XCTAssertTrue(supportInfo.isClientTagDenied("example/other"))
		XCTAssertFalse(supportInfo.isClientTagDenied("DRAFT/TYPING"))
		XCTAssertFalse(supportInfo.isClientTagDenied("example/allowed"))
	}

	@objc
	func testExtendedBanTokenSeparatesPrefixAndTypes() {
		let supportInfo = supportInfoWithConfiguration("EXTBAN=$,ac")

		XCTAssertEqual(supportInfo.extendedBanPrefix, "$")
		XCTAssertEqual(supportInfo.extendedBanTypes, ["a", "c"])

		XCTAssertNotNil(supportInfo.descriptionForExtendedBanMask("$a:account"))

		XCTAssertNil(supportInfo.descriptionForExtendedBanMask("$q:quiet"))
	}

	@objc
	func testMalformedPrefixDoesNotReplaceDefaults() {
		let supportInfo = supportInfoWithConfiguration("PREFIX=invalid")

		XCTAssertEqual(supportInfo.userPrefix(forModeSymbol: "o"), "@")
		XCTAssertEqual(supportInfo.userPrefix(forModeSymbol: "v"), "+")
	}

	@objc
	func testResettingSilenceClearsSupportAndLimitTogether() {
		let supportInfo = supportInfoWithConfiguration("SILENCE=25")

		XCTAssertTrue(supportInfo.silenceSupported)
		XCTAssertEqual(supportInfo.maximumSilenceEntries, 25)

		supportInfo.resetSetting("silence")

		XCTAssertFalse(supportInfo.silenceSupported)
		XCTAssertEqual(supportInfo.maximumSilenceEntries, 0)
	}
}

// MARK: - GLTTestAccess

/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
