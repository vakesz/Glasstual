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
@Suite("Command catalog")
struct CommandIndexTests {
	@Test("A command that does not exist resolves to nothing")
	func unknownCommandsResolveToNil() {
		#expect(RemoteCommand(wireName: "not-a-command") == nil)
		#expect(LocalCommand(typedName: "not-a-command") == nil)
	}

	@Test("A command declares where its trailing parameter starts")
	func trailingParameterPositionsComeFromTheCommand() {
		#expect(RemoteCommand.privmsg.trailingParameter == .startsAtArgument(1))
		#expect(RemoteCommand.fail.trailingParameter == .startsAtArgument(2))
		#expect(RemoteCommand.join.trailingParameter == .never)

		/* PASS declares no position at all, which is not the same as declaring
		 that it never has a trailing parameter: a password with a space in it
		 can only reach the server as one. */
		#expect(RemoteCommand.pass.trailingParameter == nil)
	}

	@Test("An action goes out as PRIVMSG but never matches an inbound line")
	func actionSharesThePrivmsgWireName() {
		#expect(RemoteCommand.privmsgAction.wireName == "PRIVMSG")
		#expect(RemoteCommand(wireName: "PRIVMSG") == .privmsg)
	}

	@Test("Local commands carry their syntax, and only real commands are offered for completion")
	func localCommandSyntaxAndCompletionList() {
		#expect(LocalCommand.away.syntax == "AWAY [comment]")
		#expect(LocalCommand.back.syntax == "BACK")
		#expect(LocalCommand.modeShortcut.displayName == "M")

		let commands = CommandIndex.localCommandList()

		#expect(commands.contains("JOIN"))
		#expect(commands.contains("BACK"))
	}
}
