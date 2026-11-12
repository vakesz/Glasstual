// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** Where a question a session asks is placed.

 A command the reader typed raises its question in the conversation they
 typed it in. A question with no typed command behind it stays where it
 was: in the conversation it is about, or in the server console. */
@MainActor
@Suite("Typed command prompt placement", .timeLimit(.minutes(1)))
struct TypedCommandPromptPlacementTests {
	@Test("A question is placed in the conversation it is about, else where its command was typed, else the console")
	func placementOrder() {
		#expect(ServerSession.promptConversationID(about: "about", commandTypedIn: "typed") == "about")
		#expect(ServerSession.promptConversationID(about: nil, commandTypedIn: "typed") == "typed")
		#expect(ServerSession.promptConversationID(about: nil, commandTypedIn: nil) == nil)
	}

	@Test("/register typed in a channel asks for the password in that channel")
	func typedInAChannel() async throws {
		let session = makeRegistrationSession()
		try session.receive(":irc.example.net 001 ada :Welcome")
		let channel = try #require(session.findConversationOrCreate("#swift"))
		channel.activate()
		session.recordedOutput.responseAnswer = .alternate

		session.inputText("/register * ada@example.org", destination: channel)
		try await Eventually.until("the question") { session.recordedOutput.presentedScopes.count == 1 }

		let scope = try #require(session.recordedOutput.presentedScopes.first)
		#expect(scope.sessionID == session.uniqueIdentifier)
		#expect(scope.conversationID == channel.uniqueIdentifier)
		#expect(session.commandConversation == nil)
	}

	@Test("/register typed in the server console asks there")
	func typedInTheConsole() async throws {
		let session = makeRegistrationSession()
		try session.receive(":irc.example.net 001 ada :Welcome")
		session.recordedOutput.responseAnswer = .alternate

		session.inputText("/register * ada@example.org", destination: session)
		try await Eventually.until("the question") { session.recordedOutput.presentedScopes.count == 1 }

		#expect(session.recordedOutput.presentedScopes.first?.conversationID == nil)
	}

	/// A script, a timer or a connect command reaches `sendCommand` directly:
	/// nobody typed it, so its question does not follow the selection.
	@Test("A command nobody typed asks in the server console even when it names a conversation")
	func untypedCommand() async throws {
		let session = makeRegistrationSession()
		try session.receive(":irc.example.net 001 ada :Welcome")
		try #require(session.findConversationOrCreate("#swift")).activate()
		session.recordedOutput.responseAnswer = .alternate

		session.sendCommand("register * ada@example.org", target: "#swift")
		try await Eventually.until("the question") { session.recordedOutput.presentedScopes.count == 1 }

		#expect(session.recordedOutput.presentedScopes.first?.conversationID == nil)
	}

	@Test("A question the session raises by itself stays in the server console")
	func serverInitiatedQuestion() {
		let session = makeRegistrationSession()
		#expect(session.promptScope().conversationID == nil)
		#expect(session.promptScope().sessionID == session.uniqueIdentifier)
	}
}
