/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
final class IRCClientOutboundPolicyTests: XCTestCase {
	func testTypingFinishesForEmptyCommandsAndDisabledNotifications() {
		XCTAssertTrue(OutboundTypingPolicy.shouldFinish(text: "", notificationsEnabled: true))
		XCTAssertTrue(OutboundTypingPolicy.shouldFinish(text: "/join #glasstual", notificationsEnabled: true))
		XCTAssertTrue(OutboundTypingPolicy.shouldFinish(text: "hello", notificationsEnabled: false))
		XCTAssertFalse(OutboundTypingPolicy.shouldFinish(text: "hello", notificationsEnabled: true))
	}

	func testTypingActiveNotificationIsRateLimitedAtBoundary() {
		let now = Date(timeIntervalSince1970: 100)
		XCTAssertTrue(OutboundTypingPolicy.shouldSendActive(previousState: nil, lastSentAt: nil, now: now))
		XCTAssertFalse(OutboundTypingPolicy.shouldSendActive(
			previousState: .active,
			lastSentAt: now.addingTimeInterval(-(OutboundTypingPolicy.activeInterval - 0.01)),
			now: now
		))
		XCTAssertTrue(OutboundTypingPolicy.shouldSendActive(
			previousState: .active,
			lastSentAt: now.addingTimeInterval(-OutboundTypingPolicy.activeInterval),
			now: now
		))
	}

	func testCTCPPayloadFramesAndSanitizesUserText() {
		XCTAssertEqual(
			CTCPPayload.framed(command: "VERSION", text: nil, sanitizingLineBreaks: true),
			"\u{01}VERSION\u{01}"
		)
		XCTAssertEqual(
			CTCPPayload.framed(command: "ACTION", text: "first\r\nsecond", sanitizingLineBreaks: true),
			"\u{01}ACTION first  second\u{01}"
		)
	}

	func testCommandParserPreservesAttributedArgumentsAfterRemovingCommand() throws {
		let input = NSMutableAttributedString(string: "/MSG nickname hello")
		input.addAttribute(.init("OutboundPolicyTest"), value: true, range: NSRange(location: 14, length: 5))

		let parsed = try XCTUnwrap(ParsedUserCommand(input))

		XCTAssertEqual(parsed.command, "MSG")
		XCTAssertEqual(parsed.arguments.rest, "nickname hello")
		XCTAssertEqual(
			parsed.arguments.attributedRest
				.attribute(.init("OutboundPolicyTest"), at: 9, effectiveRange: nil) as? Bool,
			true
		)
	}

	func testMessageCommandPolicyPreservesSecretAndOperatorAliases() throws {
		let secretMessage = try XCTUnwrap(
			OutboundMessageCommandPolicy(command: .smsg, silentlyConnecting: false)
		)
		XCTAssertEqual(secretMessage.remoteCommand, .privmsg)
		XCTAssertTrue(secretMessage.isSecretMessage)
		XCTAssertFalse(secretMessage.isOperatorMessage)

		let operatorNotice = try XCTUnwrap(
			OutboundMessageCommandPolicy(command: .onotice, silentlyConnecting: false)
		)
		XCTAssertEqual(operatorNotice.remoteCommand, .notice)
		XCTAssertFalse(operatorNotice.isSecretMessage)
		XCTAssertTrue(operatorNotice.isOperatorMessage)
	}

	func testSilentConnectOnlyMakesMessageAliasesSecret() throws {
		let message = try XCTUnwrap(
			OutboundMessageCommandPolicy(command: .msg, silentlyConnecting: true)
		)
		let action = try XCTUnwrap(
			OutboundMessageCommandPolicy(command: .me, silentlyConnecting: true)
		)
		XCTAssertTrue(message.isSecretMessage)
		XCTAssertFalse(action.isSecretMessage)
	}
}
