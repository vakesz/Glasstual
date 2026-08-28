@testable import Glasstual
import XCTest

/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@MainActor
class IRCUserNicknameColorStyleGeneratorTests: XCTestCase {
	func testHashRemainsCompatibleWithLegacyMD5ByteOrder() {
		let hash = UserNicknameColorStyleGenerator.hash(for: "alice")

		XCTAssertEqual(hash.uint32Value, 2_746_080_018)
	}

	func testLightAndDarkStylesRemainStable() {
		let hash: NSNumber = 2_746_080_018

		XCTAssertEqual(
			UserNicknameColorStyleGenerator.nicknameColorStyle(forHash: hash, colorStyle: .light),
			"hsl(18,45%,54%)"
		)
		XCTAssertEqual(
			UserNicknameColorStyleGenerator.nicknameColorStyle(forHash: hash, colorStyle: .dark),
			"hsl(18,45%,49%)"
		)
	}

	func testHueSpecificAdjustmentsRemainStable() {
		XCTAssertEqual(
			UserNicknameColorStyleGenerator.nicknameColorStyle(forHash: 1_507_889_104, colorStyle: .dark),
			"hsl(304,47%,54%)"
		)
		XCTAssertEqual(
			UserNicknameColorStyleGenerator.nicknameColorStyle(forHash: 3_807_608_927, colorStyle: .light),
			"hsl(167,78%,34%)"
		)
	}
}
