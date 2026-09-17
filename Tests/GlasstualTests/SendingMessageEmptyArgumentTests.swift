// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Sending message arguments")
struct SendingMessageEmptyArgumentTests {
	/// Skipping an empty middle argument moved every later one up a place, and
	/// one holding a space or opening with a colon went out as a different
	/// number of parameters. Neither has a wire spelling, so both are refused.
	@Test("A malformed argument before the last is refused rather than sent shifted", arguments: [
		(arguments: ["#chat", "", "+o", "nick"], index: 1),
		(arguments: ["#chat two", "+o", "nick"], index: 0),
		(arguments: ["#chat", ":+o", "nick"], index: 1),
	])
	func malformedMiddleArgumentIsRefused(arguments: [String], index: Int) {
		#expect(throws: SendingMessage.ArgumentError.malformedMiddleArgument(index: index)) {
			try SendingMessage.string(command: "MODE", arguments: arguments)
		}
	}

	/// `/nick :foo` used to trip a debug assertion: the last argument opens
	/// with a colon on a command that declares no trailing parameter.
	@Test("A last argument that opens with a colon is sent as the trailing parameter whatever the command")
	func colonLastArgumentOnAnyCommandIsTrailing() throws {
		#expect(try SendingMessage.string(command: "NICK", arguments: [":foo"]) == "NICK ::foo")
		#expect(try SendingMessage.string(command: "MODE", arguments: ["#chat", "+b", "a b"]) == "MODE #chat +b :a b")
	}

	@Test("A refused argument list sends nothing and says so")
	func refusedArgumentsSendNothing() {
		let client = TestClient(configDictionary: ["nickname": "me"])
		client.isConnected = true
		client.markAsLoggedIn()

		client.send("MODE", arguments: ["#chat", "", "nick"])

		#expect(client.sentLines.count == 0)
		let bodies = client.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(bodies.contains(String(localized: .IRC.oneOrMoreArgumentsAreNot)))
	}

	/// RFC 1459 2.3.1 allows an empty trailing parameter, and the `ircdocs`
	/// msg-join vectors expect one to be written as a bare colon. Dropping it
	/// changes the command: "AWAY :" clears an away message, "AWAY" asks for
	/// nothing.
	@Test("A trailing empty argument is written as a bare colon")
	func trailingEmptyArgumentIsWrittenAsAColon() throws {
		let line = try SendingMessage.string(command: "KILL", arguments: ["nick", ""])

		#expect(line == "KILL nick :")
	}

	@Test("A command whose only argument is empty still writes the colon")
	func aLoneEmptyArgumentIsWrittenAsAColon() throws {
		#expect(try SendingMessage.string(command: "AWAY", arguments: [""]) == "AWAY :")
	}

	@Test("A command with no arguments at all writes no colon")
	func noArgumentsWritesNoColon() throws {
		#expect(try SendingMessage.string(command: "AWAY", arguments: []) == "AWAY")
		#expect(try SendingMessage.string(command: "AWAY", arguments: nil) == "AWAY")
	}

	@Test("Non-empty arguments are unaffected")
	func nonEmptyArgumentsAreUnaffected() throws {
		let line = try SendingMessage.string(command: "KILL", arguments: ["nick", "because reasons"])

		#expect(line == "KILL nick :because reasons")
	}
}
