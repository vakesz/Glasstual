/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Objective-C compatibility surface")
struct CompatibilitySurfaceTests {
	/// A fresh client config reads its identity from the preferences rather
	/// than starting blank, and the away nickname is the one field that stays
	/// empty until the person fills it in.
	@Test("A fresh client config takes its identity from the preferences")
	func freshClientConfigReadsIdentityFromPreferences() {
		let clientConfig = ClientConfig()
		#expect(clientConfig.connectionName.isEmpty == false)
		#expect(clientConfig.nickname.isEmpty == false)
		#expect(clientConfig.channelList.isEmpty)
		#expect(clientConfig.awayNickname == "")
	}

	@Test("The nickname accessor returns the parsed component, or the whole string")
	func nsStringHostmaskAccessorsPreserveParsedComponents() {
		#expect(("nick!user@example.test" as NSString).nicknameFromHostmask == "nick")
		#expect(("not a hostmask" as NSString).nicknameFromHostmask == "not a hostmask")
	}

	@Test("A complete control sequence is removed by both formatting entry points")
	func sharedFormattingRemovesCompleteControlSequences() {
		let formatted = "\u{02}bold\u{02} \u{03}04,12palette \u{04}A1B2C3,001122hex\u{0F}"
		let expected = "bold palette hex"

		#expect(TextFormatting.removingControlCodes(from: formatted) == expected)
		#expect((formatted as NSString).stripIRCEffects == expected)
	}

	@Test("A malformed colour separator is left in the text")
	func sharedFormattingPreservesMalformedColorSeparatorsAndUnicode() {
		#expect(TextFormatting.removingControlCodes(from: "\u{03}04,text") == ",text")
		#expect(TextFormatting.removingControlCodes(from: "\u{04}AABBCC,no") == ",no")
		#expect(TextFormatting.removingControlCodes(from: "\u{03},plain 😀") == ",plain 😀")
	}

	@Test("The hostmask parser keeps its validation rules")
	func sharedHostmaskParserPreservesValidationRules() throws {
		let hostmask = try #require(Hostmask(parsing: "nick!user@example.test"))

		#expect(hostmask.nickname == "nick")
		#expect(hostmask.username == "user")
		#expect(hostmask.address == "example.test")
		#expect(Hostmask(parsing: "*!user@example.test") == nil)
		#expect(Hostmask(parsing: "nick!user name@example.test") == nil)
		#expect(Hostmask(parsing: "long-nickname!user@example.test", maximumNicknameLength: 4) == nil)
	}
}
