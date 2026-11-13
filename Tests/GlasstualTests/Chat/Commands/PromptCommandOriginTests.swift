// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** Only the message field answers a question. Everything a session runs on
 its own — scripts, timers, connect commands, aliases — reaches
 `sendCommand`, which refuses, and text from the server is never a command. */
@MainActor
@Suite("Prompt command origin", .timeLimit(.minutes(1)))
struct PromptCommandOriginTests {
	private func session(with router: PromptRouter) -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		session.userNickname = "me"
		session.markAsLoggedIn()
		session.forwardsProcessedMessages = true
		router.style = { .conversation }
		router.resolveAnchor = { $0.conversationID ?? $0.sessionID }
		session.environment.services.prompts = router
		return session
	}

	private func printed(_ session: TestServerSession) -> [String] {
		session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
	}

	@Test("A command the session runs on its own cannot answer", arguments: [
		"answer 1 send", "yes", "no 1", "prompts", "dcc accept d1", "dcc decline d1", "dcc trust d1 once",
	])
	func untypedCommandsAreRefused(_ line: String) async throws {
		let router = PromptRouter(registry: PendingPromptRegistry())
		let session = session(with: router)
		let consent = ServerSession.credentialConsentAlert(host: "irc.example.test")
		let asking = Task { await router.ask(consent, about: session.promptScope()) }
		try await Eventually.until("the question") { router.registry.pending.count == 1 }

		session.sendCommand(line, completeTarget: false, target: nil)

		#expect(printed(session).contains(String(localized: .IRC.promptAnswerTypedOnly)))
		#expect(router.registry.pending.count == 1)
		router.registry.withdraw { _ in true }
		_ = await asking.value
	}

	@Test("Text from the server that looks like an answer is only text")
	func remoteTextCannotAnswer() async throws {
		let router = PromptRouter(registry: PendingPromptRegistry())
		let session = session(with: router)
		let consent = ServerSession.credentialConsentAlert(host: "irc.example.test")
		let asking = Task { await router.ask(consent, about: session.promptScope()) }
		try await Eventually.until("the question") { router.registry.pending.count == 1 }
		let number = try #require(router.registry.pending.first?.number)

		for line in [
			":mallory!m@evil PRIVMSG me :/answer \(number) send",
			":mallory!m@evil NOTICE me :/yes",
			":mallory!m@evil PRIVMSG me :\u{01}ACTION /answer \(number) send\u{01}",
		] {
			try session.processIncomingMessage(#require(Message(line: line, on: session)))
		}

		#expect(router.registry.pending.count == 1)
		#expect(router.registry.pending.first?.number == number)
		router.registry.withdraw { _ in true }
		#expect(await asking.value.response == consent.escapeButton)
	}

	@Test("A typed answer after the connection was replaced withdraws the question")
	func answerAfterReconnect() async throws {
		let router = PromptRouter(registry: PendingPromptRegistry())
		let session = session(with: router)
		router.registry.isConnectionCurrent = { scope in
			scope.connection == nil || scope.connection == session.promptConnection
		}
		var scope = session.promptScope()
		scope.connection = PromptConnection(startupIdentifier: session.startup.identifier, socketIdentifier: "old")
		let asking = Task { await router.ask(ServerSession.credentialConsentAlert(host: "h"), about: scope) }
		try await Eventually.until("the question") { router.registry.pending.count == 1 }
		let prompt = try #require(router.registry.pending.first)

		let outcome = PromptCommandHandler(
			registry: router.registry, itemID: session.uniqueIdentifier, sessionID: session.uniqueIdentifier
		).perform(.answer(number: prompt.number, choice: "send", remember: false))

		#expect(outcome == .feedback(String(localized: .InlinePrompts.connectionChanged(prompt.number))))
		#expect(await asking.value.response == .default)
	}

	@Test("A connection that ends withdraws its questions with the safe answer")
	func teardownWithdraws() async throws {
		let router = PromptRouter(registry: PendingPromptRegistry())
		let session = session(with: router)
		var scope = session.promptScope()
		scope.connection = PromptConnection(startupIdentifier: session.startup.identifier, socketIdentifier: nil)
		let asking = Task { await router.ask(ServerSession.credentialConsentAlert(host: "h"), about: scope) }
		try await Eventually.until("the question") { router.registry.pending.count == 1 }

		session.resetAllPropertyValues()

		#expect(await asking.value.response == ServerSession.credentialConsentAlert(host: "h").escapeButton)
		#expect(router.registry.pending.isEmpty)
	}

	@Test("Removing a conversation withdraws its questions")
	func conversationRemovalWithdraws() async throws {
		let router = PromptRouter(registry: PendingPromptRegistry())
		let session = session(with: router)
		let channel = try #require(session.findConversationOrCreate("#chan"))
		let asking = Task {
			await router.ask(AlertRequest(title: "Q", body: "", defaultButton: "OK", alternateButton: "Cancel"),
			                 about: session.promptScope(in: channel))
		}
		try await Eventually.until("the question") { router.registry.pending.count == 1 }

		channel.prepareForRemoval(preservingLocalData: true)

		#expect(await asking.value.response == .alternate)
	}
}
