/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
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

	@Test("The same nickname produces the same native colour")
	func colorIsStable() {
		let first = UserNicknameColorStyleGenerator.color(for: "alice")
		let second = UserNicknameColorStyleGenerator.color(for: "Alice")

		#expect(first.textualHexadecimalValue == second.textualHexadecimalValue)
	}
}
