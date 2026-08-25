import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "IRCUserNicknameColorStyleGeneratorPrivate.h"
/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class IRCUserNicknameColorStyleGeneratorTests: XCTestCase {
    @objc
    func testHashRemainsCompatibleWithLegacyMD5ByteOrder() {
        let hash: NSNumber! = IRCUserNicknameColorStyleGenerator.hashForString("alice", colorStyle: TPCThemeSettingsNicknameColorStyleLight)

        XCTAssertEqual(hash.unsignedIntValue, 2746080018)
    }
    @objc
    func testLightAndDarkStylesRemainStable() {
        let hash: NSNumber = 2746080018

        XCTAssertEqualObjects(IRCUserNicknameColorStyleGenerator.nicknameColorStyleForHash(hash, colorStyle: TPCThemeSettingsNicknameColorStyleLight), "hsl(18,45%,54%)")
        XCTAssertEqualObjects(IRCUserNicknameColorStyleGenerator.nicknameColorStyleForHash(hash, colorStyle: TPCThemeSettingsNicknameColorStyleDark), "hsl(18,45%,49%)")
    }
    @objc
    func testHueSpecificAdjustmentsRemainStable() {
        XCTAssertEqualObjects(IRCUserNicknameColorStyleGenerator.nicknameColorStyleForHash(1507889104, colorStyle: TPCThemeSettingsNicknameColorStyleDark), "hsl(304,47%,54%)")
        XCTAssertEqualObjects(IRCUserNicknameColorStyleGenerator.nicknameColorStyleForHash(3807608927, colorStyle: TPCThemeSettingsNicknameColorStyleLight), "hsl(167,78%,34%)")
    }
}