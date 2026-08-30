/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Command index")
struct IRCCommandIndexTests {
	init() {
		CommandIndex.populateCommandIndex()
	}

	@Test("A command is found whatever case it is typed in")
	func commandIndexesAreCaseInsensitive() {
		#expect(CommandIndex.index(ofRemoteCommand: "privmsg") == 1035)
		#expect(CommandIndex.index(ofRemoteCommand: "PRIVMSG") == 1035)
		#expect(CommandIndex.index(ofLocalCommand: "join") == 5032)
		#expect(CommandIndex.index(ofLocalCommand: "JOIN") == 5032)
	}

	@Test("A command that does not exist reports not found rather than a default index")
	func unknownCommandsReturnNotFound() {
		#expect(CommandIndex.index(ofRemoteCommand: "not-a-command") == UInt(NSNotFound))
		#expect(CommandIndex.index(ofLocalCommand: "not-a-command") == UInt(NSNotFound))
		#expect(CommandIndex.colonPosition(forRemoteCommand: "not-a-command") == UInt(NSNotFound))
	}

	@Test("The colon position of an outgoing command comes from the remote command metadata")
	func outgoingColonPositionsComeFromRemoteCommandMetadata() {
		#expect(CommandIndex.colonPosition(forRemoteCommand: "PRIVMSG") == 1)
		#expect(CommandIndex.colonPosition(forRemoteCommand: "FAIL") == 2)
		#expect(CommandIndex.colonPosition(forRemoteCommand: "PASS") == UInt(NSNotFound))
	}

	@Test("Local commands carry their syntax, and only real commands are offered for completion")
	func localCommandSyntaxAndCompletionList() {
		#expect(CommandIndex.syntax(forLocalCommand: "away") == "AWAY [comment]")
		#expect(CommandIndex.syntax(forLocalCommand: "back") == "BACK")
		#expect(CommandIndex.syntax(forLocalCommand: "not-a-command") == nil)

		let commands = CommandIndex.localCommandList()

		#expect(commands.contains("JOIN"))
		#expect(commands.contains("Reserved Information") == false)
	}
}
