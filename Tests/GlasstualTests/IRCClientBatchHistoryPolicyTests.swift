/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

final class IRCClientBatchHistoryPolicyTests: XCTestCase {
	func testBatchTokenValidationPreservesOpeningAndClosingDirection() {
		XCTAssertEqual(IRCBatchPolicy.normalizedToken("+history")?.token, "history")
		XCTAssertEqual(IRCBatchPolicy.normalizedToken("+history")?.opens, true)
		XCTAssertEqual(IRCBatchPolicy.normalizedToken("-history")?.opens, false)
		XCTAssertNil(IRCBatchPolicy.normalizedToken("history"))
		XCTAssertNil(IRCBatchPolicy.normalizedToken("+bad token"))
	}

	func testBatchTypeAliasesAreRecognized() {
		XCTAssertTrue(IRCBatchPolicy.isChatHistory("chathistory"))
		XCTAssertTrue(IRCBatchPolicy.isChatHistory("draft/chathistory"))
		XCTAssertTrue(IRCBatchPolicy.isNetsplit("netsplit"))
		XCTAssertTrue(IRCBatchPolicy.isNetsplit("netjoin"))
		XCTAssertFalse(IRCBatchPolicy.isNetsplit("znc.in/playback"))
	}

	func testHistoryLimitUsesServerMaximumOnlyWhenItIsStricter() {
		XCTAssertEqual(IRCChatHistoryPolicy.requestLimit(serverMaximum: 0), 100)
		XCTAssertEqual(IRCChatHistoryPolicy.requestLimit(serverMaximum: 25), 25)
		XCTAssertEqual(IRCChatHistoryPolicy.requestLimit(serverMaximum: 250), 100)
	}

	func testHistoryAvailabilityRejectsUnsupportedTargetsAndFailures() {
		XCTAssertTrue(IRCChatHistoryPolicy.canUseServerHistory(
			isLoggedIn: true,
			capabilityEnabled: true,
			isUtility: false,
			isDirectChat: false,
			isZNCQuery: false,
			targetFailed: false
		))
		XCTAssertFalse(IRCChatHistoryPolicy.canUseServerHistory(
			isLoggedIn: true,
			capabilityEnabled: true,
			isUtility: false,
			isDirectChat: false,
			isZNCQuery: false,
			targetFailed: true
		))
	}

	func testReadMarkerAdvancesOnlyToANewerDate() {
		let previous = Date(timeIntervalSince1970: 100)
		XCTAssertTrue(IRCChatHistoryPolicy.shouldAdvanceMarker(
			candidate: Date(timeIntervalSince1970: 101),
			previous: previous
		))
		XCTAssertFalse(IRCChatHistoryPolicy.shouldAdvanceMarker(candidate: previous, previous: previous))
	}

	func testLabeledResponseClassification() {
		XCTAssertEqual(IRCLabeledResponsePolicy.responseKind(command: "FAIL", commandNumeric: 0), .failure)
		XCTAssertEqual(IRCLabeledResponsePolicy.responseKind(command: "ack", commandNumeric: 0), .acknowledgement)
		XCTAssertEqual(
			IRCLabeledResponsePolicy.responseKind(
				command: "PRIVMSG",
				commandNumeric: IRCRemoteCommand.privmsg.rawValue
			),
			.echo
		)
		XCTAssertEqual(IRCLabeledResponsePolicy.responseKind(command: "NOTE", commandNumeric: 0), .unrelated)
	}

	func testNetsplitPolicyProvidesFallbackServersAndCommandFilter() {
		let servers = IRCNetsplitSummaryPolicy.servers(from: ["irc-a"])
		XCTAssertEqual(servers.0, "irc-a")
		XCTAssertEqual(servers.1, "?")
		XCTAssertTrue(IRCNetsplitSummaryPolicy.accepts(command: "quit"))
		XCTAssertFalse(IRCNetsplitSummaryPolicy.accepts(command: "PRIVMSG"))
	}
}
