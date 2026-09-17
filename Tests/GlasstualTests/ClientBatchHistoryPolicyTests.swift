// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Batch and chat history policy")
struct ClientBatchHistoryPolicyTests {
	@Test("A batch token carries its direction, and an unsigned or spaced token is rejected")
	func batchTokenValidationPreservesOpeningAndClosingDirection() {
		#expect(BatchPolicy.normalizedToken("+history")?.token == "history")
		#expect(BatchPolicy.normalizedToken("+history")?.opens == true)
		#expect(BatchPolicy.normalizedToken("-history")?.opens == false)
		#expect(BatchPolicy.normalizedToken("history") == nil)
		#expect(BatchPolicy.normalizedToken("+bad token") == nil)
	}

	@Test("The draft spellings of a batch type are recognized alongside the ratified ones")
	func batchTypeAliasesAreRecognized() {
		#expect(BatchPolicy.isChatHistory("chathistory"))
		#expect(BatchPolicy.isChatHistory("draft/chathistory"))
		#expect(BatchPolicy.isNetsplit("netsplit"))
		#expect(BatchPolicy.isNetsplit("netjoin"))
		#expect(BatchPolicy.isNetsplit("znc.in/playback") == false)
	}

	@Test("The server maximum caps the request only when it is stricter than the local one")
	func historyLimitUsesServerMaximumOnlyWhenItIsStricter() {
		#expect(ChatHistoryPolicy.requestLimit(serverMaximum: 0) == 100)
		#expect(ChatHistoryPolicy.requestLimit(serverMaximum: 25) == 25)
		#expect(ChatHistoryPolicy.requestLimit(serverMaximum: 250) == 100)
	}

	@Test("A target that already failed is not asked for history again")
	func historyAvailabilityRejectsUnsupportedTargetsAndFailures() {
		#expect(ChatHistoryPolicy.canUseServerHistory(
			isLoggedIn: true,
			capabilityEnabled: true,
			isUtility: false,
			isDirectChat: false,
			isZNCQuery: false,
			targetFailed: false
		))
		#expect(ChatHistoryPolicy.canUseServerHistory(
			isLoggedIn: true,
			capabilityEnabled: true,
			isUtility: false,
			isDirectChat: false,
			isZNCQuery: false,
			targetFailed: true
		) == false)
	}

	@Test("The read marker only moves forward in time")
	func readMarkerAdvancesOnlyToANewerDate() {
		let previous = Date(timeIntervalSince1970: 100)
		#expect(ChatHistoryPolicy.shouldAdvanceMarker(
			candidate: Date(timeIntervalSince1970: 101),
			previous: previous
		))
		#expect(ChatHistoryPolicy.shouldAdvanceMarker(candidate: previous, previous: previous) == false)
	}

	@Test("A netsplit summary names a second server even when the batch gave only one")
	func netsplitPolicyProvidesFallbackServersAndCommandFilter() {
		let servers = NetsplitSummaryPolicy.servers(from: ["irc-a"])
		#expect(servers.0 == "irc-a")
		#expect(servers.1 == "?")
		#expect(NetsplitSummaryPolicy.accepts(command: "quit"))
		#expect(NetsplitSummaryPolicy.accepts(command: "PRIVMSG") == false)
	}
}
