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

/// Behaviour corpus for the command catalog.
///
/// Every fact a command carries — its wire name, its documented syntax, the
/// arity that syntax implies and where its trailing parameter starts — is
/// declared on the case itself, so these tests pin the catalog against the
/// lines it produces rather than against a second copy of the table.
@MainActor
struct CommandIndexCorpusTests {
	@Test
	func everyLocalCommandResolvesFromItsName() {
		for command in LocalCommand.allCases {
			#expect(LocalCommand(typedName: command.rawValue) == command)
			#expect(LocalCommand(typedName: command.displayName) == command)
			#expect(command.displayName == command.rawValue.uppercased())
		}
	}

	/// An inbound line is matched against the raw value, so every remote
	/// command has to spell a legal wire name — except the one the client only
	/// ever sends.
	@Test
	func everyRemoteCommandResolvesFromItsWireName() {
		for command in RemoteCommand.allCases where command != .privmsgAction {
			#expect(RemoteCommand(wireName: command.rawValue) == command)
			#expect(RemoteCommand(wireName: command.wireName) == command)
			#expect(command.rawValue.contains(" ") == false)
		}

		#expect(RemoteCommand.privmsgAction.rawValue.contains(" "))
	}

	@Test
	func aCommandWithoutArgumentsIsItsOwnSyntaxLine() {
		for command in LocalCommand.allCases where command.arguments == nil {
			#expect(command.syntax == command.displayName)
			#expect(command.arity == .none)
		}
	}

	/// The arity is read off the documented syntax, so a command that declares
	/// arguments declares at least one group.
	@Test
	func argumentSyntaxImpliesTheArity() {
		for command in LocalCommand.allCases {
			guard let arguments = command.arguments else { continue }

			#expect(command.syntax == "\(command.displayName) \(arguments)")
			#expect(command.arity.required + command.arity.optional > 0, "\(command.rawValue)")
		}

		#expect(LocalCommand.kick.arity == CommandArity(required: 1, optional: 2))
		#expect(LocalCommand.away.arity == CommandArity(required: 0, optional: 1))
		#expect(LocalCommand.msg.arity == CommandArity(required: 2, optional: 0))
	}

	/// The developer-mode commands are hidden from completion, but still
	/// resolve, so the dispatcher can refuse them with a message instead of
	/// forwarding them to the server.
	@Test(arguments: ["recv", "tage", "join_random"])
	func developerCommandsAreHiddenByDefault(name: String) throws {
		let command = try #require(LocalCommand(typedName: name))

		#expect(command.isDeveloperModeOnly)
		#expect(CommandIndex.localCommandList().contains(command.displayName) == false)
	}

	@Test
	func onlyDeveloperCommandsAreHidden() {
		let offered = Set(CommandIndex.localCommandList())
		let expected = Set(
			LocalCommand.allCases
				.filter { $0.isDeveloperModeOnly == false }
				.map(\.displayName)
		)

		#expect(offered == expected)
	}

	/// A name the client has a handler for names its group; the rest are
	/// forwarded to a user script or to the server as the user typed them.
	@Test
	func everyHandledCommandNamesItsGroup() {
		#expect(LocalCommand.dcc.group == .directChat)
		#expect(LocalCommand.msg.group == .message)
		#expect(LocalCommand.defaults.group == .defaults)
		#expect(LocalCommand.unignore.group == .ignore)
		#expect(LocalCommand.timer.group == .timer)
		#expect(LocalCommand.kickban.group == .channel(.moderation))
		#expect(LocalCommand.modeShortcut.group == .channel(.mode))
		#expect(LocalCommand.topicShortcut.group == .channel(.conversation))
		#expect(LocalCommand.raw.group == .native(.raw))
		#expect(LocalCommand.mylag.group == .native(.lag))

		let forwarded = LocalCommand.allCases.filter { $0.group == nil }.map(\.rawValue)

		#expect(forwarded.sorted() == ["adchat", "chatops", "globops", "locops", "nachat", "pass", "whowas"])
	}

	// MARK: - Trailing parameters

	@Test
	func theTrailingParameterDrivesTheOutgoingLine() throws {
		#expect(
			try SendingMessage.string(command: "PRIVMSG", arguments: ["#chat", "hello there"])
				== "PRIVMSG #chat :hello there"
		)
		#expect(
			try SendingMessage.string(command: "KICK", arguments: ["#chat", "alice", "bye now"])
				== "KICK #chat alice :bye now"
		)
		#expect(
			try SendingMessage.string(command: "USER", arguments: ["user", "0", "*", "real name"])
				== "USER user 0 * :real name"
		)
		/* PASS declares no position, so nothing before the last argument gets a
		 colon — but a last argument holding a space still needs the trailing
		 marker to survive the wire as one token. */
		#expect(try SendingMessage.string(command: "PASS", arguments: ["a b"]) == "PASS :a b")
		#expect(try SendingMessage.string(command: "JOIN", arguments: ["#chat"]) == "JOIN #chat")
	}

	/// A command that never takes a trailing parameter takes each of its
	/// parameters as its own wire token.
	@Test(arguments: [
		RemoteCommand.join, .mode, .who, .whois, .ping, .pong, .cap, .authenticate,
	])
	func commandsWithoutATrailingParameterSaySo(command: RemoteCommand) {
		#expect(command.trailingParameter == .never)
	}

	@Test
	func aDeclaredPositionIsWithinReach() {
		for command in RemoteCommand.allCases {
			guard case let .startsAtArgument(position) = command.trailingParameter else { continue }

			#expect((0 ... 3).contains(position), "\(command.rawValue)")
		}
	}
}
