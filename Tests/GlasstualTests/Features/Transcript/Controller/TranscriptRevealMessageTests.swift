// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// Finding the message a reply quotes: in storage, from the server, or not at all.
@MainActor
@Suite("Revealing a message", .serialized, .timeLimit(.minutes(1)))
struct TranscriptRevealMessageTests {
	private struct Fixture {
		let session: TestServerSession
		let conversation: Conversation
		let controller: TranscriptController
	}

	private func makeFixture(chatHistory: Bool) throws -> Fixture {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		session.setConnectionTransportForTesting(.connected)
		session.enableCapability([.batch, .serverTime, .messageTags, .labeledResponse])
		session.isLoggedIn = true
		session.forwardsProcessedMessages = true
		let conversation = try #require(session.findConversationOrCreate("#reveal"))
		conversation.activate()
		if chatHistory {
			session.enableCapability(.chatHistory)
		}
		session.sentLines.removeAllObjects()
		let window = MainWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
		                        styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(conversation: conversation, in: window, scrollback: Scrollback.shared)
		conversation.presentation = controller
		controller.loadsHistoryLazily = { false }
		controller.historyPageFetcher = { _ in .page([]) }
		return Fixture(session: session, conversation: conversation, controller: controller)
	}

	@Test("A message stored for the view is shown in a window of history")
	func storedMessageIsShown() async throws {
		let fixture = try makeFixture(chatHistory: false)
		defer {
			fixture.controller.tearDown(.preservingRemoval)
			fixture.session.stopAllTimers()
		}
		var original = ChatLine()
		original.lineType = .privateMessage
		original.nickname = "bob"
		original.messageBody = "the original"
		original.messageIdentifier = "orig"
		let entry = original.scrollbackEntry(forView: fixture.conversation.uniqueIdentifier)
		fixture.controller.historyPageFetcher = { request in
			if case .messageWindow = request.kind {
				return .page([entry])
			}
			return .page([])
		}
		_ = fixture.controller.ensureBackingView()
		await fixture.controller.drainRenderJobs()

		#expect(await fixture.controller.revealMessage(identifier: "orig") == .shown)
		#expect(fixture.controller.historyRecovery.isDetachedFromLive)
	}

	@Test("Nothing stored and no server lookup means it is unavailable")
	func unavailableWithoutHistory() async throws {
		let fixture = try makeFixture(chatHistory: false)
		defer {
			fixture.controller.tearDown(.preservingRemoval)
			fixture.session.stopAllTimers()
		}

		#expect(await fixture.controller.revealMessage(identifier: "gone") == .unavailable)
		#expect(fixture.controller.canRevealMessage(identifier: "gone") == false)
	}

	@Test("A message the server cannot find either is reported not found")
	func serverPathNotFound() async throws {
		let fixture = try makeFixture(chatHistory: true)
		defer {
			fixture.controller.tearDown(.preservingRemoval)
			fixture.session.stopAllTimers()
		}

		let reveal = Task { await fixture.controller.revealMessage(identifier: "gone") }
		try await Eventually.until("the AROUND request") {
			(fixture.session.sentLines as NSArray).compactMap { $0 as? String }
				.contains { $0.contains("CHATHISTORY AROUND #reveal msgid=gone") }
		}
		let line = try #require((fixture.session.sentLines as NSArray).compactMap { $0 as? String }.last)
		let label = try #require(line.split(separator: " ").first.map { String($0.dropFirst("@label=".count)) })
		let failure = try #require(Message(
			line: "@label=\(label) :irc.example.net FAIL CHATHISTORY INVALID_TARGET AROUND #reveal :No",
			on: fixture.session
		))
		fixture.session.receiveStandardReply(failure)

		#expect(await reveal.value == .notFound)
	}
}
