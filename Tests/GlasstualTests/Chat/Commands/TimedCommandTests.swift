// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Timed commands")
struct TimedCommandTests {
	@Test("A timed command records the session and channel it was made for")
	func initializationCapturesCommandContextAndUniqueIdentifiers() {
		let session = TestServerSession()
		let channel = Conversation(config: ConversationConfig(name: "#chat"))

		let first = TimedCommand(command: "WHO #chat", onSession: session, in: channel)
		let second = TimedCommand(command: "PING", onSession: session)

		#expect(first.command == "WHO #chat")
		#expect(first.sessionId == session.uniqueIdentifier)
		#expect(first.conversationId == channel.uniqueIdentifier)
		#expect(second.conversationId == nil)
		#expect(first.identifier != second.identifier)
	}

	@Test("Restarting needs a previous start and reuses that timer's configuration")
	func restartRequiresPreviousStartAndPreservesTimerConfiguration() {
		let session = TestServerSession()
		let command = TimedCommand(command: "PING", onSession: session)

		#expect(command.restart() == false)

		command.start(30, onRepeat: true, iterations: 3)

		#expect(command.timer.isActive)
		#expect(command.timer.interval == 30)
		#expect(command.timer.repeats)
		#expect(command.timer.iterations == 3)

		command.stop()

		#expect(command.timer.isActive == false)

		#expect(command.restart())
		#expect(command.timer.isActive)

		command.stop()
	}

	@Test("A timed command made in a channel that has since closed is removed rather than run elsewhere")
	func timedCommandForAClosedChannelIsRemoved() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		session.isConnected = true
		session.markAsLoggedIn()
		let closed = try #require(session.findConversationOrCreate("#closed"))
		let selected = try #require(session.findConversationOrCreate("#selected"))
		closed.activate()
		selected.activate()
		session.recordedOutput.selectedSession = session
		session.recordedOutput.selectedConversation = selected

		let timedCommand = TimedCommand(command: "me waves", onSession: session, in: closed)
		session.addTimedCommand(timedCommand)
		session.conversationList.removeAll { $0 === closed }

		session.onTimedCommand(timedCommand)

		#expect(session.sentLines.count == 0)
		#expect(session.timedCommand(withIdentifier: timedCommand.identifier) == nil)
	}

	@Test("A timed command runs in the channel it was made in, not the one selected when it fires")
	func timedCommandRunsInItsOwnChannel() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		session.isConnected = true
		session.markAsLoggedIn()
		let origin = try #require(session.findConversationOrCreate("#origin"))
		let selected = try #require(session.findConversationOrCreate("#selected"))
		origin.activate()
		selected.activate()
		session.recordedOutput.selectedSession = session
		session.recordedOutput.selectedConversation = selected

		let inConversation = TimedCommand(command: "me waves", onSession: session, in: origin)
		let inConsole = TimedCommand(command: "me waves", onSession: session)

		session.onTimedCommand(inConversation)
		session.onTimedCommand(inConsole)

		let sent = session.sentLines.compactMap { $0 as? String }
		#expect(sent.first == "PRIVMSG #origin :\u{01}ACTION waves\u{01}")
		#expect(sent.contains { $0.hasPrefix("PRIVMSG #selected") } == false)
	}

	@Test("The session owns its timed commands and hands them back by identifier")
	func sessionOwnsTimedCommandsThroughTheSwiftStore() {
		let session = TestServerSession()
		let first = TimedCommand(command: "PING", onSession: session)
		let second = TimedCommand(command: "WHO #chat", onSession: session)

		session.addTimedCommand(first)
		session.addTimedCommand(second)

		#expect(session.timedCommand(withIdentifier: first.identifier) === first)
		#expect(Set(session.listOfTimedCommands().map(\.identifier)) == [first.identifier, second.identifier])

		session.removeTimedCommand(first)
		#expect(session.timedCommand(withIdentifier: first.identifier) == nil)
		#expect(session.listOfTimedCommands().map(\.identifier) == [second.identifier])

		session.removeTimedCommands()
		#expect(session.listOfTimedCommands().isEmpty)
	}
}
