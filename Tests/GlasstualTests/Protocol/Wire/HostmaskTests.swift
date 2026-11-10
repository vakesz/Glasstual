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

	@Test("A nickname of exactly the default limit is accepted and one byte more is not")
	func nicknameLengthBoundary() {
		let atLimit = String(repeating: "a", count: 50)
		let pastLimit = String(repeating: "a", count: 51)

		#expect(Hostmask(parsing: "\(atLimit)!user@example.test")?.nickname == atLimit)
		#expect(Hostmask(parsing: "\(pastLimit)!user@example.test") == nil)
		#expect(Hostmask.isValidNickname(atLimit))
		#expect(Hostmask.isValidNickname(pastLimit) == false)
	}

	@Test("The nickname limit counts UTF-8 bytes, not characters")
	func nicknameLimitCountsBytes() {
		let atLimit = String(repeating: "\u{00E9}", count: 25)
		let pastLimit = String(repeating: "\u{00E9}", count: 26)

		#expect(Hostmask.isValidNickname(atLimit))
		#expect(Hostmask.isValidNickname(pastLimit) == false)
	}

	@Test("The username limit is 40 UTF-16 units")
	func usernameLengthBoundary() {
		#expect(Hostmask.isValidWireUsername(String(repeating: "u", count: 40)))
		#expect(Hostmask.isValidWireUsername(String(repeating: "u", count: 41)) == false)
		#expect(Hostmask.isValidUsername(String(repeating: "u", count: 40)))
		#expect(Hostmask.isValidUsername(String(repeating: "u", count: 41)) == false)
	}

	/// A "!" or "@" in a username moves where the hostmask delimits, so the wire
	/// form refuses both. A person typing a username may use either: bouncer
	/// logins such as `user@client/network` are legitimate there.
	@Test("Separators inside a username are refused on the wire and allowed when typed")
	func separatorsInTheUsername() {
		#expect(Hostmask(parsing: "nick!us@er@host.test") == nil)
		#expect(Hostmask(parsing: "nick!us!er@host.test") == nil)
		#expect(Hostmask.isValidWireUsername("us!er") == false)
		#expect(Hostmask.isValidWireUsername("us@er") == false)

		#expect(Hostmask.isValidUsername("us!er"))
		#expect(Hostmask.isValidUsername("us@er"))
		#expect(Hostmask.isValidUsername("user@client/network"))
	}

	@Test("Ordinary identd values are still accepted on the wire", arguments: ["~user", "user-1", "[user]", "u_ser.x"])
	func ordinaryWireUsernames(username: String) throws {
		#expect(Hostmask.isValidWireUsername(username))
		let hostmask = try #require(Hostmask(parsing: "nick!\(username)@host.test"))

		#expect(hostmask.username == username)
	}

	@Test("An address cannot carry a separator")
	func addressRejectsSeparators() {
		#expect(Hostmask.isValidAddress("host@evil") == false)
		#expect(Hostmask.isValidAddress("host!evil") == false)
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
