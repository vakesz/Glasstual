// Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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

		let commands = CommandIndex.localCommandList(includingDeveloperCommands: false)

		#expect(commands.contains("JOIN"))
		#expect(commands.contains("BACK"))
	}
}
