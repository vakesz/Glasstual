// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Hostmask parsing")
struct HostmaskTests {
	/// Searching backwards for "@" let a server craft a prefix that parsed
	/// with a different address than the operator's rule expected.
	@Test
	func aSecondAtSignDoesNotMoveTheAddress() {
		#expect(Hostmask(parsing: "nick!user@host@evil") == nil)
	}

	@Test
	func theFirstAtSignAfterTheBangDelimitsTheAddress() throws {
		let hostmask = try #require(Hostmask(parsing: "nick!user@example.test"))

		#expect(hostmask.nickname == "nick")
		#expect(hostmask.username == "user")
		#expect(hostmask.address == "example.test")
	}

	@Test
	func anAtSignBeforeTheBangIsNotASeparator() {
		#expect(Hostmask(parsing: "ni@ck!user@example.test") == nil)
		#expect(Hostmask(parsing: "user@example.test") == nil)
	}

	@Test("The nickname accessor returns the parsed component, or the whole string")
	func theNicknameAccessorReturnsTheParsedComponentOrTheWholeString() {
		#expect("nick!user@example.test".nicknameFromHostmask == "nick")
		#expect("not a hostmask".nicknameFromHostmask == "not a hostmask")
	}

	@Test("The hostmask parser keeps its validation rules")
	func theParserKeepsItsValidationRules() throws {
		let hostmask = try #require(Hostmask(parsing: "nick!user@example.test"))

		#expect(hostmask.nickname == "nick")
		#expect(hostmask.username == "user")
		#expect(hostmask.address == "example.test")
		#expect(Hostmask(parsing: "*!user@example.test") == nil)
		#expect(Hostmask(parsing: "nick!user name@example.test") == nil)
		#expect(Hostmask(parsing: "long-nickname!user@example.test", maximumNicknameLength: 4) == nil)
	}

	@Test
	func missingSeparatorsAndEmptyPartsAreRejected() {
		#expect(Hostmask(parsing: "") == nil)
		#expect(Hostmask(parsing: "nick!") == nil)
		#expect(Hostmask(parsing: "nick!user") == nil)
		#expect(Hostmask(parsing: "!user@host") == nil)
		#expect(Hostmask(parsing: "nick!@host") == nil)
		#expect(Hostmask(parsing: "nick!user@") == nil)
	}

	@Test
	func multibyteComponentsSurviveSlicing() throws {
		let hostmask = try #require(Hostmask(parsing: "n\u{00EF}ck!us\u{00E9}r@h\u{00F6}st.test"))

		#expect(hostmask.nickname == "n\u{00EF}ck")
		#expect(hostmask.username == "us\u{00E9}r")
		#expect(hostmask.address == "h\u{00F6}st.test")
	}

	@Test
	func aCombiningMarkAfterASeparatorDoesNotHideIt() throws {
		let hostmask = try #require(Hostmask(parsing: "nick!\u{0301}user@host.test"))

		#expect(hostmask.nickname == "nick")
		#expect(hostmask.username == "\u{0301}user")
	}
}
