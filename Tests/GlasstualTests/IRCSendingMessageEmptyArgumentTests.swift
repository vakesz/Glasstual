/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct IRCSendingMessageEmptyArgumentTests {
	@Test("An empty argument does not truncate the arguments that follow it")
	func emptyArgumentDoesNotTruncateTheLine() {
		let line = SendingMessage.string(command: "MODE", arguments: ["#chat", "", "+o", "nick"])

		#expect(line == "MODE #chat +o nick")
	}

	/// RFC 1459 2.3.1 allows an empty trailing parameter, and the `ircdocs`
	/// msg-join vectors expect one to be written as a bare colon. Dropping it
	/// changes the command: "AWAY :" clears an away message, "AWAY" asks for
	/// nothing.
	@Test("A trailing empty argument is written as a bare colon")
	func trailingEmptyArgumentIsWrittenAsAColon() {
		let line = SendingMessage.string(command: "KILL", arguments: ["nick", ""])

		#expect(line == "KILL nick :")
	}

	@Test("A command whose only argument is empty still writes the colon")
	func aLoneEmptyArgumentIsWrittenAsAColon() {
		#expect(SendingMessage.string(command: "AWAY", arguments: [""]) == "AWAY :")
	}

	@Test("A command with no arguments at all writes no colon")
	func noArgumentsWritesNoColon() {
		#expect(SendingMessage.string(command: "AWAY", arguments: []) == "AWAY")
		#expect(SendingMessage.string(command: "AWAY", arguments: nil) == "AWAY")
	}

	@Test("Non-empty arguments are unaffected")
	func nonEmptyArgumentsAreUnaffected() {
		let line = SendingMessage.string(command: "KILL", arguments: ["nick", "because reasons"])

		#expect(line == "KILL nick :because reasons")
	}
}
