import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCISupportInfoPrivate.h"
// #import "IRCModeInfo.h"
@objc
class IRCISupportInfoTests: XCTestCase {
    @objc
    func supportInfoWithConfiguration(_ configuration: String) -> IRCISupportInfo {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        let supportInfo: IRCISupportInfo! = IRCISupportInfo(client: client)

        supportInfo.processConfigurationData(configuration)

        return supportInfo
    }
    @objc
    func testDefaultCaseMappingIsRFC1459() {
        let supportInfo = self.supportInfoWithConfiguration("NETWORK=Example")

        XCTAssertEqual(supportInfo.caseMapping, IRCISupportInfoCaseMappingRFC1459)
        XCTAssertEqualObjects(supportInfo.casefoldString("Nick[]\\\\~"), "nick{}|^")
    }
    @objc
    func testASCIICaseMappingLeavesBracketsAlone() {
        let supportInfo = self.supportInfoWithConfiguration("CASEMAPPING=ascii")

        XCTAssertEqual(supportInfo.caseMapping, IRCISupportInfoCaseMappingASCII)
        XCTAssertEqualObjects(supportInfo.casefoldString("Nick[]\\\\~"), "nick[]\\\\~")
    }
    @objc
    func testStrictRFC1459DoesNotFoldTilde() {
        let supportInfo = self.supportInfoWithConfiguration("CASEMAPPING=strict-rfc1459")

        XCTAssertEqual(supportInfo.caseMapping, IRCISupportInfoCaseMappingStrictRFC1459)
        XCTAssertEqualObjects(supportInfo.casefoldString("A[]\\\\~"), "a{}|~")
    }
    @objc
    func testNonASCIICharactersAreNotFolded() {
        let rfc = self.supportInfoWithConfiguration("CASEMAPPING=rfc1459")
        let ascii = self.supportInfoWithConfiguration("CASEMAPPING=ascii")

        XCTAssertEqualObjects(rfc.casefoldString("ÄbÇ"), "ÄbÇ")
        XCTAssertEqualObjects(rfc.casefoldString("ÄB[Ç]"), "Äb{Ç}")
        XCTAssertEqualObjects(ascii.casefoldString("ÄbÇ"), "ÄbÇ")
        XCTAssertEqualObjects(ascii.casefoldString("ŞİRİN"), "Şİrİn")
    }
    @objc
    func testChannelModesAreParsedIntoParameterClasses() {
        let supportInfo = self.supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst")

        XCTAssertEqualObjects(supportInfo.channelModes["b"], 1)
        XCTAssertEqualObjects(supportInfo.channelModes["k"], 2)
        XCTAssertEqualObjects(supportInfo.channelModes["l"], 3)
        XCTAssertEqualObjects(supportInfo.channelModes["t"], 4)

        XCTAssertTrue(supportInfo.modeHasParameter("b", whenModeIsSet: true))
        XCTAssertTrue(supportInfo.modeHasParameter("b", whenModeIsSet: false))
        XCTAssertTrue(supportInfo.modeHasParameter("k", whenModeIsSet: false))
        XCTAssertTrue(supportInfo.modeHasParameter("l", whenModeIsSet: true))

        XCTAssertFalse(supportInfo.modeHasParameter("l", whenModeIsSet: false))
        XCTAssertFalse(supportInfo.modeHasParameter("t", whenModeIsSet: true))
    }
    @objc
    func testPrefixIsParsedInRankOrder() {
        let supportInfo = self.supportInfoWithConfiguration("PREFIX=(qaohv)~&@%+")

        XCTAssertEqualObjects(supportInfo.userModeSymbols[IRCISupportUserModeSymbolsSymbolsKey], ["q", "a", "o", "h", "v"])
        XCTAssertEqualObjects(supportInfo.userModeSymbols[IRCISupportUserModeSymbolsCharactersKey], ["~", "&", "@", "%", "+"])
        XCTAssertEqualObjects(supportInfo.modeSymbolForUserPrefix("@"), "o")
        XCTAssertEqualObjects(supportInfo.userPrefixForModeSymbol("v"), "+")

        XCTAssertTrue(supportInfo.characterIsUserPrefix("%"))

        XCTAssertFalse(supportInfo.characterIsUserPrefix("#"))

        XCTAssertEqual(supportInfo.rankForUserPrefixWithMode("q"), IRCISupportInfoHighestUserPrefixRank)

        XCTAssertTrue(supportInfo.rankForUserPrefixWithMode("v") < supportInfo.rankForUserPrefixWithMode("o"))
        /* Prefix modes always take a parameter. */
        XCTAssertTrue(supportInfo.modeHasParameter("o", whenModeIsSet: false))
    }
    @objc
    func testParseModesUsesChannelModeClasses() {
        let supportInfo = self.supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
        let modes: [IRCModeInfo]! = supportInfo.parseModes("+nt-k+l secret 10")

        XCTAssertEqual(modes.count, 4)

        XCTAssertEqualObjects(modes[0].modeSymbol, "n")

        XCTAssertTrue(modes[0].modeIsSet)

        XCTAssertEqualObjects(modes[2].modeSymbol, "k")

        XCTAssertFalse(modes[2].modeIsSet)

        XCTAssertEqualObjects(modes[2].modeParameter, "secret")
        XCTAssertEqualObjects(modes[3].modeSymbol, "l")
        XCTAssertEqualObjects(modes[3].modeParameter, "10")
    }
    @objc
    func testParseModesDoesNotConsumeParameterWhenUnsetModeDoesNotRequireOne() {
        let supportInfo = self.supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
        let modes: [IRCModeInfo]! = supportInfo.parseModes("-l leftover +t")

        XCTAssertEqual(modes.count, 2)

        XCTAssertEqualObjects(modes[0].modeSymbol, "l")

        XCTAssertFalse(modes[0].modeIsSet)

        XCTAssertNil(modes[0].modeParameter)

        XCTAssertEqualObjects(modes[1].modeSymbol, "t")

        XCTAssertTrue(modes[1].modeIsSet)
    }
    @objc
    func testParseModesAllowsMissingRequiredParameter() {
        let supportInfo = self.supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
        let modes: [IRCModeInfo]! = supportInfo.parseModes("+k")

        XCTAssertEqual(modes.count, 1)

        XCTAssertEqualObjects(modes[0].modeSymbol, "k")

        XCTAssertTrue(modes[0].modeIsSet)

        XCTAssertNil(modes[0].modeParameter)
    }
    @objc
    func testLimitTokensAndTargetChunking() {
        let supportInfo = self.supportInfoWithConfiguration("CHANLIMIT=#&:50,+: TARGMAX=privmsg:4,JOIN: MAXTARGETS=3 MAXLIST=beI:60")

        XCTAssertEqual(supportInfo.channelLimitForChannelNamed("#chat"), 50)
        XCTAssertEqual(supportInfo.channelLimitForChannelNamed("&local"), 50)
        XCTAssertEqual(supportInfo.channelLimitForChannelNamed("+modeless"), 0)
        XCTAssertEqual(supportInfo.maximumTargetsForCommand("PRIVMSG"), 4)
        XCTAssertEqual(supportInfo.maximumTargetsForCommand("notice"), 3)
        XCTAssertEqual(supportInfo.maximumTargetsForCommand("join"), 0)
        XCTAssertEqual(supportInfo.maximumListEntriesForModeSymbol("b"), 60)
        XCTAssertEqual(supportInfo.maximumListEntriesForModeSymbol("I"), 60)

        let targets: NSArray = ["a", "b", "c", "d", "e"]

        XCTAssertEqualObjects(IRCISupportInfo.chunkTargets(targets, limit: 2), [["a", "b"], ["c", "d"], ["e"]])

        let conservativeChunks: NSArray! = IRCISupportInfo.chunkTargets(["a", "b"], limit: 0)

        XCTAssertEqualObjects(conservativeChunks, [["a"], ["b"]])
    }
    @objc
    func testClientTagDenyAllowsExceptionsToWildcard() {
        let supportInfo = self.supportInfoWithConfiguration("CLIENTTAGDENY=*,-draft/typing,-example/allowed")

        XCTAssertTrue(supportInfo.isClientTagDenied("example/other"))
        XCTAssertFalse(supportInfo.isClientTagDenied("DRAFT/TYPING"))
        XCTAssertFalse(supportInfo.isClientTagDenied("example/allowed"))
    }
    @objc
    func testExtendedBanTokenSeparatesPrefixAndTypes() {
        let supportInfo = self.supportInfoWithConfiguration("EXTBAN=$,ac")

        XCTAssertEqualObjects(supportInfo.extendedBanPrefix, "$")
        XCTAssertEqualObjects(supportInfo.extendedBanTypes, ["a", "c"])

        XCTAssertNotNil(supportInfo.descriptionForExtendedBanMask("$a:account"))

        XCTAssertNil(supportInfo.descriptionForExtendedBanMask("$q:quiet"))
    }
    @objc
    func testMalformedPrefixDoesNotReplaceDefaults() {
        let supportInfo = self.supportInfoWithConfiguration("PREFIX=invalid")

        XCTAssertEqualObjects(supportInfo.userPrefixForModeSymbol("o"), "@")
        XCTAssertEqualObjects(supportInfo.userPrefixForModeSymbol("v"), "+")
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
@objc
extension IRCISupportInfo {
    @objc
    func modeHasParameter(_ modeSymbol: String, whenModeIsSet: Bool) -> Bool {
    }
}