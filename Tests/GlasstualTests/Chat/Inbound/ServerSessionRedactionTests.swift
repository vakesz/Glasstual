// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Records the deletions a conversation's view was told about.
@MainActor
private final class RedactionRecordingPresentation: ChatItemPresenting {
	private(set) var redactedIdentifiers: [String] = []

	let presentationIdentifier = "redaction-recording-presentation"

	func print(_: ChatLine, completionBlock _: PrintedLineCompletion?) {}
	func lastPrintedLine() -> ChatLine? {
		nil
	}

	nonisolated func setTopic(_: String?) {} // nonisolated: pure
	func mark() {}
	func mark(at _: Date) {}
	func noteReaction(_: String, fromNickname _: String, toMessageIdentifier _: String) {}
	func noteRedaction(ofMessageIdentifier identifier: String) {
		redactedIdentifiers.append(identifier)
	}

	func updateDeliveryState(
		forLineNumber _: String,
		state _: ChatLineDeliveryState,
		messageIdentifier _: String?,
		reason _: String?
	) {}
	func prependEarlierChatLines(_: [ChatLine]) {}
	func tearDown(_: ChatItemTeardown) {}
}

/// `draft/message-redaction`: `REDACT` in both directions.
@MainActor
@Suite("Message redaction")
struct ServerSessionRedactionTests {
	private func session() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.setConnectionTransportForTesting(.connected)
		session.userNickname = "me"
		session.markAsLoggedIn()
		return session
	}

	private func redact(_ line: String, on session: TestServerSession) throws {
		try session.receiveRedact(#require(Message(line: line, on: session)))
	}

	private func redactLines(of session: TestServerSession) -> [String] {
		session.sentLines.compactMap { $0 as? String }.filter { $0.hasPrefix("REDACT") }
	}

	@Test("A relayed REDACT reaches the view of the channel it names")
	func channelRedactionReachesTheView() throws {
		let session = session()
		session.enableCapability([.messageTags, .messageRedaction])
		let channel = try #require(session.findConversationOrCreate("#chan"))
		let presentation = RedactionRecordingPresentation()
		channel.presentation = presentation

		try redact(":alice!u@h REDACT #chan msg-1 :spam", on: session)

		#expect(presentation.redactedIdentifiers == ["msg-1"])
	}

	@Test("A direct-message REDACT addressed to us belongs to the sender's conversation")
	func directRedactionResolvesTheSender() throws {
		let session = session()
		session.enableCapability([.messageTags, .messageRedaction])
		let conversation = try #require(session.findConversationOrCreate("alice"))
		let presentation = RedactionRecordingPresentation()
		conversation.presentation = presentation

		try redact(":alice!u@h REDACT me msg-2", on: session)

		#expect(presentation.redactedIdentifiers == ["msg-2"])
	}

	@Test("Our own REDACT echoed back belongs to the recipient's conversation")
	func echoedRedactionResolvesTheTarget() throws {
		let session = session()
		session.enableCapability([.messageTags, .messageRedaction])
		let conversation = try #require(session.findConversationOrCreate("alice"))
		let presentation = RedactionRecordingPresentation()
		conversation.presentation = presentation

		try redact(":me!u@h REDACT alice msg-3", on: session)

		#expect(presentation.redactedIdentifiers == ["msg-3"])
	}

	@Test("Without the capability a REDACT is not evidence of anything")
	func redactionIsIgnoredWithoutTheCapability() throws {
		let session = session()
		let channel = try #require(session.findConversationOrCreate("#chan"))
		let presentation = RedactionRecordingPresentation()
		channel.presentation = presentation

		try redact(":alice!u@h REDACT #chan msg-1", on: session)

		#expect(presentation.redactedIdentifiers.isEmpty)
	}

	@Test("A REDACT with no message identifier or no conversation does nothing")
	func malformedRedactionIsIgnored() throws {
		let session = session()
		session.enableCapability([.messageTags, .messageRedaction])
		let channel = try #require(session.findConversationOrCreate("#chan"))
		let presentation = RedactionRecordingPresentation()
		channel.presentation = presentation

		try redact(":alice!u@h REDACT #chan", on: session)
		try redact(":alice!u@h REDACT #unknown msg-1", on: session)

		#expect(presentation.redactedIdentifiers.isEmpty)
	}

	@Test("Deleting a message sends REDACT with the target, identifier and reason")
	func sendsRedact() throws {
		let session = session()
		session.enableCapability([.messageTags, .messageRedaction])
		let channel = try #require(session.findConversationOrCreate("#chan"))

		#expect(session.redactMessage(withIdentifier: "msg-1", in: channel, reason: "  spam  "))
		#expect(session.redactMessage(withIdentifier: "msg-2", in: channel, reason: ""))
		#expect(session.redactMessage(withIdentifier: "msg-3", in: channel, reason: nil))

		#expect(redactLines(of: session) == [
			"REDACT #chan msg-1 :spam",
			"REDACT #chan msg-2",
			"REDACT #chan msg-3",
		])
	}

	@Test("Nothing is sent without the capability or without an identifier")
	func sendsNothingWhenUnsupported() throws {
		let session = session()
		let channel = try #require(session.findConversationOrCreate("#chan"))

		#expect(session.redactMessage(withIdentifier: "msg-1", in: channel, reason: nil) == false)

		session.enableCapability([.messageTags, .messageRedaction])

		#expect(session.redactMessage(withIdentifier: "", in: channel, reason: nil) == false)
		#expect(redactLines(of: session).isEmpty)
	}

	@Test("The /redact command takes the identifier first and the rest as the reason")
	func redactCommandSplitsItsArguments() throws {
		#expect(LocalCommand(typedName: "REDACT") == .redact)
		#expect(LocalCommand.redact.arity == CommandArity(required: 1, optional: 1))
		#expect(LocalCommand.redact.group == .request)
		#expect(RemoteCommand.redact.wireName == "REDACT")
		#expect(
			try SendingMessage.string(command: .redact, arguments: ["#chan", "msg-1", "bad words here"])
				== "REDACT #chan msg-1 :bad words here"
		)
	}

	@Test("The draft capability is negotiated under its prefixed name")
	func capabilityIsRegistered() throws {
		let capability = try #require(CapabilityRegistry.defaultRegistry.capability(named: "draft/message-redaction"))

		#expect(capability.identifier == .messageRedaction)
		#expect(capability.specification != nil)
	}
}
