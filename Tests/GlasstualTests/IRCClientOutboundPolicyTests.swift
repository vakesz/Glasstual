/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Outbound client policies")
struct IRCClientOutboundPolicyTests {
	@Test("Typing finishes for an empty line, a command, and a network that does not want notifications")
	func typingFinishesForEmptyCommandsAndDisabledNotifications() {
		#expect(OutboundTypingPolicy.shouldFinish(text: "", notificationsEnabled: true))
		#expect(OutboundTypingPolicy.shouldFinish(text: "/join #glasstual", notificationsEnabled: true))
		#expect(OutboundTypingPolicy.shouldFinish(text: "hello", notificationsEnabled: false))
		#expect(OutboundTypingPolicy.shouldFinish(text: "hello", notificationsEnabled: true) == false)
	}

	@Test("The active notification is resent only once the interval has fully elapsed")
	func typingActiveNotificationIsRateLimitedAtBoundary() {
		let now = Date(timeIntervalSince1970: 100)

		#expect(OutboundTypingPolicy.shouldSendActive(previousState: nil, lastSentAt: nil, now: now))
		#expect(OutboundTypingPolicy.shouldSendActive(
			previousState: .active,
			lastSentAt: now.addingTimeInterval(-(OutboundTypingPolicy.activeInterval - 0.01)),
			now: now
		) == false)
		#expect(OutboundTypingPolicy.shouldSendActive(
			previousState: .active,
			lastSentAt: now.addingTimeInterval(-OutboundTypingPolicy.activeInterval),
			now: now
		))
	}

	@Test("A CTCP payload is framed and its line breaks flattened")
	func ctcpPayloadFramesAndSanitizesUserText() {
		#expect(
			CTCPPayload.framed(command: "VERSION", text: nil, sanitizingLineBreaks: true) ==
				"\u{01}VERSION\u{01}"
		)
		#expect(
			CTCPPayload.framed(command: "ACTION", text: "first\r\nsecond", sanitizingLineBreaks: true) ==
				"\u{01}ACTION first  second\u{01}"
		)
	}

	@Test("Removing the command from a typed line leaves the attributed arguments intact")
	func commandParserPreservesAttributedArgumentsAfterRemovingCommand() throws {
		let input = NSMutableAttributedString(string: "/MSG nickname hello")
		input.addAttribute(.init("OutboundPolicyTest"), value: true, range: NSRange(location: 14, length: 5))

		let parsed = try #require(ParsedUserCommand(input))

		#expect(parsed.command == "MSG")
		#expect(parsed.arguments.rest == "nickname hello")
		#expect(
			parsed.arguments.attributedRest
				.attribute(.init("OutboundPolicyTest"), at: 9, effectiveRange: nil) as? Bool == true
		)
	}

	@Test("The secret and operator aliases keep the remote command they stand for")
	func messageCommandPolicyPreservesSecretAndOperatorAliases() throws {
		let secretMessage = try #require(
			OutboundMessageCommandPolicy(command: .smsg, silentlyConnecting: false)
		)
		#expect(secretMessage.remoteCommand == .privmsg)
		#expect(secretMessage.isSecretMessage)
		#expect(secretMessage.isOperatorMessage == false)

		let operatorNotice = try #require(
			OutboundMessageCommandPolicy(command: .onotice, silentlyConnecting: false)
		)
		#expect(operatorNotice.remoteCommand == .notice)
		#expect(operatorNotice.isSecretMessage == false)
		#expect(operatorNotice.isOperatorMessage)
	}

	@Test("Connecting silently makes a message secret but leaves an action alone")
	func silentConnectOnlyMakesMessageAliasesSecret() throws {
		let message = try #require(
			OutboundMessageCommandPolicy(command: .msg, silentlyConnecting: true)
		)
		let action = try #require(
			OutboundMessageCommandPolicy(command: .me, silentlyConnecting: true)
		)

		#expect(message.isSecretMessage)
		#expect(action.isSecretMessage == false)
	}
}
