// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Chat session intent actions")
struct ChatSessionIntentActionsTests {
	private struct Fixture {
		let chatSession: ChatSession
		let session: TestServerSession
		let actions: ChatSessionIntentActions
		let openedLinks: LinkRecorder
	}

	private final class LinkRecorder {
		var links: [String] = []
	}

	private func makeFixture() throws -> Fixture {
		let fixture = ChatEnvironmentFixture(settings: ChatSettings())
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		session.isLoggedIn = true
		_ = try #require(session.findConversationOrCreate("#swift"))
		_ = try #require(session.findConversationOrCreate("alice", isDirect: true))
		let chatSession = ChatSession(environment: fixture.environment)
		chatSession.sessions = [session]
		let recorder = LinkRecorder()
		let actions = ChatSessionIntentActions(
			chatSession: { chatSession },
			openLink: { recorder.links.append($0) }
		)
		return Fixture(chatSession: chatSession, session: session, actions: actions, openedLinks: recorder)
	}

	@Test("Servers and conversations are reported as snapshots, without the console")
	func snapshots() throws {
		let fixture = try makeFixture()

		#expect(fixture.actions.servers().map(\.id) == [fixture.session.uniqueIdentifier])
		let conversations = fixture.actions.conversations()
		#expect(conversations.map(\.name).contains("#swift"))
		#expect(conversations.first { $0.name == "#swift" }?.kind == .channel)
		#expect(conversations.first { $0.name == "alice" }?.kind == .directMessage)
		#expect(conversations.allSatisfy { $0.serverID == fixture.session.uniqueIdentifier })
	}

	@Test("Opening a conversation hands a goto link to the application")
	func opensThroughALink() throws {
		let fixture = try makeFixture()
		let channel = try #require(fixture.session.findConversation("#swift"))

		try fixture.actions.openConversation(id: channel.uniqueIdentifier)

		#expect(fixture.openedLinks.links == ["glasstual://goto/" + channel.uniqueIdentifier])
	}

	@Test("An unknown conversation or server is an error, not a no-op")
	func unknownTargets() async throws {
		let fixture = try makeFixture()

		#expect(throws: IntentActionError.conversationNotFound) { try fixture.actions.openConversation(id: "nope") }
		#expect(throws: IntentActionError.serverNotFound) { try fixture.actions.connect(server: "nope") }
		#expect(throws: IntentActionError.serverNotFound) { try fixture.actions.disconnect(server: "nope") }
		await #expect(throws: IntentActionError.conversationNotFound) {
			try await fixture.actions.sendMessage("hi", toConversation: "nope")
		}
		await #expect(throws: IntentActionError.serverNotFound) {
			try await fixture.actions.joinChannel("#swift", onServer: "nope")
		}
	}

	@Test("Text is validated before anything else, and a disconnected server is refused")
	func validationAndReadiness() async throws {
		let fixture = try makeFixture()
		let channel = try #require(fixture.session.findConversation("#swift"))

		await #expect(throws: IntentActionError.emptyMessage) {
			try await fixture.actions.sendMessage("  ", toConversation: channel.uniqueIdentifier)
		}
		await #expect(throws: IntentActionError.invalidChannelName) {
			try await fixture.actions.joinChannel("two words", onServer: fixture.session.uniqueIdentifier)
		}

		fixture.session.isLoggedIn = false
		await #expect(throws: IntentActionError.notConnected) {
			try await fixture.actions.sendMessage("hi", toConversation: channel.uniqueIdentifier)
		}
	}

	@Test("Nothing works before the chat session exists")
	func notReady() async {
		let actions = ChatSessionIntentActions(chatSession: { nil }, openLink: { _ in })

		#expect(actions.servers().isEmpty)
		#expect(actions.conversations().isEmpty)
		#expect(throws: IntentActionError.applicationNotReady) { try actions.connect(server: "x") }
		await #expect(throws: IntentActionError.applicationNotReady) {
			try await actions.sendMessage("hi", toConversation: "x")
		}
	}
}
