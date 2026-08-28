/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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

import Foundation
@testable import Glasstual
import Testing

struct IRCHostmaskGlobTests {
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
