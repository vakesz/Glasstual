// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Netsplit collapse")
struct NetsplitCollapseTests {
	@Test("A netsplit summary names a second server even when the batch gave only one")
	func summaryProvidesFallbackServersAndCommandFilter() {
		let servers = NetsplitSummaryPolicy.servers(from: ["irc-a"])

		#expect(servers.0 == "irc-a")
		#expect(servers.1 == "?")
		#expect(NetsplitSummaryPolicy.accepts(command: .quit))
		#expect(NetsplitSummaryPolicy.accepts(command: .privmsg) == false)
	}

	@Test("A netsplit nickname list under the limit keeps its order")
	func shortNicknameListsRetainOrder() {
		#expect(
			NetsplitSummaryPolicy.nicknameList(["alice", "bob", "carol"], limit: 10)
				== "alice, bob, carol"
		)
	}
}
