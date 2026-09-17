// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
struct HighlightHealthCheckTests {
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
		let config = PropertyListModel.decode(ClientConfig.self, from: [
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
struct UserClientReferenceTests {
	/** A user used to hold a weak client and a member reached its own client
	 through it, so both read live state that could already have gone. Neither
	 holds a client now: a user is a value, and a member carries the prefix table
	 the list stamped it with. */
	@Test
	func aUserAndItsMemberOutliveTheirClient() throws {
		var client: TestClient? = TestClient()
		let user = User(nickname: "nick")
		var member = try ChannelUser(user: user, prefixes: #require(client).currentUserPrefixes)
		member.modes = ChannelModeSymbolSet(letters: "o")

		#expect(member.mark == "@")

		client = nil

		#expect(member.mark == "@")
		#expect(member.user.nickname == "nick")
	}
}
