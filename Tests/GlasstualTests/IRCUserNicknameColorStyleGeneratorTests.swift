/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Nickname color styles")
struct IRCUserNicknameColorStyleGeneratorTests {
	/// The hash is what decides a nickname's color, so a change repaints every
	/// conversation the user has ever seen.
	@Test("The hash still reads the MD5 digest in the legacy byte order")
	func hashRemainsCompatibleWithLegacyMD5ByteOrder() {
		let hash = UserNicknameColorStyleGenerator.hash(for: "alice")

		#expect(hash.uint32Value == 2_746_080_018)
	}

	@Test("One hash gives the same color in light and dark, differing only in lightness")
	func lightAndDarkStylesRemainStable() {
		let hash: NSNumber = 2_746_080_018

		#expect(
			UserNicknameColorStyleGenerator.nicknameColorStyle(forHash: hash, colorStyle: .light) ==
				"hsl(18,45%,54%)"
		)
		#expect(
			UserNicknameColorStyleGenerator.nicknameColorStyle(forHash: hash, colorStyle: .dark) ==
				"hsl(18,45%,49%)"
		)
	}

	@Test("The per-hue saturation and lightness adjustments are unchanged")
	func hueSpecificAdjustmentsRemainStable() {
		#expect(
			UserNicknameColorStyleGenerator.nicknameColorStyle(forHash: 1_507_889_104, colorStyle: .dark) ==
				"hsl(304,47%,54%)"
		)
		#expect(
			UserNicknameColorStyleGenerator.nicknameColorStyle(forHash: 3_807_608_927, colorStyle: .light) ==
				"hsl(167,78%,34%)"
		)
	}
}
