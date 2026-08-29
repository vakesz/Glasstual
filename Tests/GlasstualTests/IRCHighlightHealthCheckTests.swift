/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
struct IRCHighlightHealthCheckTests {
	/// The Objective-C original used NSParameterAssert, which compiles out in
	/// release; `precondition` turned a hand-edited plist into a crash.
	@Test
	func aConditionMissingItsKeywordLoadsAndIsFlagged() {
		let condition = HighlightMatchCondition(matchIsExcluded: true)

		#expect(condition.isWellFormed == false)
		#expect(condition.matchKeyword.isEmpty)
	}

	@Test
	func aCompleteConditionIsWellFormed() {
		let condition = HighlightMatchCondition(matchKeyword: "hello")

		#expect(condition.isWellFormed)
		#expect(condition.matchKeyword == "hello")
	}

	/// A malformed persisted entry is skipped rather than carried forward.
	@Test
	func malformedHighlightEntriesAreSkippedOnLoad() {
		let config = PropertyListModel.decode(IRCClientConfig.self, from: [
			"highlightList": [
				["matchKeyword": "keep"],
				["matchIsExcluded": true],
			],
		])

		#expect(config?.highlightList.count == 1)
		#expect(config?.highlightList.first?.matchKeyword == "keep")
	}
}

@MainActor
struct IRCUserClientReferenceTests {
	/** A user used to hold a weak client and a member reached its own client
	 through it, so both read live state that could already have gone. Neither
	 holds a client now: a user is a value, and a member carries the prefix table
	 the list stamped it with. */
	@Test
	func aUserAndItsMemberOutliveTheirClient() throws {
		var client: GLTTestClient? = GLTTestClient()
		let user = User(nickname: "nick")
		var member = try ChannelUser(user: user, prefixes: #require(client).currentUserPrefixes)
		member.modes = ChannelModeSymbolSet(letters: "o")

		#expect(member.mark == "@")

		client = nil

		#expect(member.mark == "@")
		#expect(member.user.nickname == "nick")
	}
}
