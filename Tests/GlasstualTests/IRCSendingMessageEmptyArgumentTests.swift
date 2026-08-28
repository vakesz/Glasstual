/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

struct IRCSendingMessageEmptyArgumentTests {
	@Test("An empty argument does not truncate the arguments that follow it")
	func emptyArgumentDoesNotTruncateTheLine() {
		let line = SendingMessage.string(command: "MODE", arguments: ["#chat", "", "+o", "nick"])

		#expect(line == "MODE #chat +o nick")
	}

	@Test("A trailing empty argument is simply omitted")
	func trailingEmptyArgumentIsOmitted() {
		let line = SendingMessage.string(command: "KILL", arguments: ["nick", ""])

		#expect(line == "KILL nick")
	}

	@Test("Non-empty arguments are unaffected")
	func nonEmptyArgumentsAreUnaffected() {
		let line = SendingMessage.string(command: "KILL", arguments: ["nick", "because reasons"])

		#expect(line == "KILL nick :because reasons")
	}
}
