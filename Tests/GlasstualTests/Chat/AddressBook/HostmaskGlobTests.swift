// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct HostmaskGlobTests {
	private func matcher(_ hostmask: String) -> AddressBookEntryMatcher {
		AddressBookEntryMatcher(entryType: .ignore, hostmask: hostmask)
	}

	/// `*a*a*a*a*a*b` compiled to `^.*?a.*?a.*?a.*?a.*?a.*?b$` and took
	/// seconds against a 70 character hostmask; nine wildcards took minutes.
	/// The two-pointer matcher is linear.
	@Test(.timeLimit(.minutes(1)))
	func pathologicalWildcardMasksMatchQuickly() {
		let hostmask = String(repeating: "a", count: 70)
		let pattern = "*" + String(repeating: "a*", count: 12) + "b"

		#expect(matcher(pattern).matches(hostmask: hostmask) == false)
	}

	@Test
	func wildcardsAnchorAndMatchAsBefore() {
		#expect(matcher("n?ck!*@*.example").matches(hostmask: "nick!user@irc.example"))
		#expect(matcher("n?ck!*@*.example").matches(hostmask: "prefix-nick!user@irc.example") == false)
		#expect(matcher("n?ck!*@*.example").matches(hostmask: "noock!user@irc.example") == false)
		#expect(matcher("nick[1]!*@example.com").matches(hostmask: "NICK[1]!user@example.com"))
		#expect(matcher("nick[1]!*@example.com").matches(hostmask: "nick1!user@example.com") == false)
	}

	@Test
	func matchingIsCaseInsensitive() {
		#expect(matcher("Nick!*@*").matches(hostmask: "NICK!user@host"))
		#expect(matcher("*!*@EXAMPLE.com").matches(hostmask: "nick!user@example.COM"))
	}

	@Test
	func adjacentWildcardsCollapse() {
		#expect(matcher("****").matches(hostmask: "anything at all"))
		#expect(matcher("a***b").matches(hostmask: "ab"))
		#expect(matcher("a***b").matches(hostmask: "axyzb"))
	}

	/// A backslash escapes the character after it, so a mask can contain a
	/// literal wildcard. A trailing backslash is an ordinary character.
	@Test
	func backslashEscapesTheFollowingWildcard() {
		#expect(matcher(#"a\*b"#).matches(hostmask: "a*b"))
		#expect(matcher(#"a\*b"#).matches(hostmask: "axyzb") == false)
		#expect(matcher(#"a\?b"#).matches(hostmask: "a?b"))
		#expect(matcher(#"a\?b"#).matches(hostmask: "axb") == false)
		#expect(matcher(#"a\"#).matches(hostmask: #"a\"#))
	}

	@Test
	func questionMarkNeedsExactlyOneCharacter() {
		#expect(matcher("a?c").matches(hostmask: "abc"))
		#expect(matcher("a?c").matches(hostmask: "ac") == false)
		#expect(matcher("a?c").matches(hostmask: "abbc") == false)
	}

	@Test
	func literalMasksStillAnchorAtBothEnds() {
		#expect(matcher("nick!user@host").matches(hostmask: "nick!user@host"))
		#expect(matcher("nick!user@host").matches(hostmask: "xnick!user@host") == false)
		#expect(matcher("nick!user@host").matches(hostmask: "nick!user@hostx") == false)
	}

	/// The pattern is still published for display.
	@Test
	func displayPatternIsStillProduced() {
		#expect(matcher("nick[1]!*@example.com").regularExpressionPattern == #"^nick\[1]!.*?@example\.com$"#)
	}
}
