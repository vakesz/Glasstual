/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Batch and chat history policy")
struct IRCClientBatchHistoryPolicyTests {
	@Test("A batch token carries its direction, and an unsigned or spaced token is rejected")
	func batchTokenValidationPreservesOpeningAndClosingDirection() {
		#expect(IRCBatchPolicy.normalizedToken("+history")?.token == "history")
		#expect(IRCBatchPolicy.normalizedToken("+history")?.opens == true)
		#expect(IRCBatchPolicy.normalizedToken("-history")?.opens == false)
		#expect(IRCBatchPolicy.normalizedToken("history") == nil)
		#expect(IRCBatchPolicy.normalizedToken("+bad token") == nil)
	}

	@Test("The draft spellings of a batch type are recognized alongside the ratified ones")
	func batchTypeAliasesAreRecognized() {
		#expect(IRCBatchPolicy.isChatHistory("chathistory"))
		#expect(IRCBatchPolicy.isChatHistory("draft/chathistory"))
		#expect(IRCBatchPolicy.isNetsplit("netsplit"))
		#expect(IRCBatchPolicy.isNetsplit("netjoin"))
		#expect(IRCBatchPolicy.isNetsplit("znc.in/playback") == false)
	}

	@Test("The server maximum caps the request only when it is stricter than the local one")
	func historyLimitUsesServerMaximumOnlyWhenItIsStricter() {
		#expect(IRCChatHistoryPolicy.requestLimit(serverMaximum: 0) == 100)
		#expect(IRCChatHistoryPolicy.requestLimit(serverMaximum: 25) == 25)
		#expect(IRCChatHistoryPolicy.requestLimit(serverMaximum: 250) == 100)
	}

	@Test("A target that already failed is not asked for history again")
	func historyAvailabilityRejectsUnsupportedTargetsAndFailures() {
		#expect(IRCChatHistoryPolicy.canUseServerHistory(
			isLoggedIn: true,
			capabilityEnabled: true,
			isUtility: false,
			isDirectChat: false,
			isZNCQuery: false,
			targetFailed: false
		))
		#expect(IRCChatHistoryPolicy.canUseServerHistory(
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
		#expect(IRCChatHistoryPolicy.shouldAdvanceMarker(
			candidate: Date(timeIntervalSince1970: 101),
			previous: previous
		))
		#expect(IRCChatHistoryPolicy.shouldAdvanceMarker(candidate: previous, previous: previous) == false)
	}

	@Test("A labeled response is classified by its command and numeric")
	func labeledResponseClassification() {
		#expect(IRCLabeledResponsePolicy.responseKind(command: "FAIL", commandNumeric: 0) == .failure)
		#expect(IRCLabeledResponsePolicy.responseKind(command: "ack", commandNumeric: 0) == .acknowledgement)
		#expect(
			IRCLabeledResponsePolicy.responseKind(
				command: "PRIVMSG",
				commandNumeric: IRCRemoteCommand.privmsg.rawValue
			) == .echo
		)
		#expect(IRCLabeledResponsePolicy.responseKind(command: "NOTE", commandNumeric: 0) == .unrelated)
	}

	@Test("A netsplit summary names a second server even when the batch gave only one")
	func netsplitPolicyProvidesFallbackServersAndCommandFilter() {
		let servers = IRCNetsplitSummaryPolicy.servers(from: ["irc-a"])
		#expect(servers.0 == "irc-a")
		#expect(servers.1 == "?")
		#expect(IRCNetsplitSummaryPolicy.accepts(command: "quit"))
		#expect(IRCNetsplitSummaryPolicy.accepts(command: "PRIVMSG") == false)
	}
}
