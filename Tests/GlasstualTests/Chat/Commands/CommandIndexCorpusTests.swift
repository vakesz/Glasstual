// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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
	/// command has to spell a legal wire name — except the one the session only
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
		#expect(CommandIndex.candidates(includingDeveloperCommands: false, scriptCommands: [])
			.contains { $0.name == command.rawValue } == false)
	}

	@Test
	func onlyDeveloperCommandsAreHidden() {
		let offered = Set(CommandIndex.candidates(includingDeveloperCommands: false, scriptCommands: []).map(\.name))
		let expected = Set(
			LocalCommand.allCases
				.filter { $0.isDeveloperModeOnly == false }
				.map(\.rawValue)
		)

		#expect(offered == expected)
	}

	/// A name the session has a handler for names its group; the rest are
	/// forwarded to a user script or to the server as the user typed them.
	@Test
	func everyHandledCommandNamesItsGroup() {
		#expect(LocalCommand.dcc.group == .directChat)
		#expect(LocalCommand.msg.group == .message)
		#expect(LocalCommand.defaults.group == .configuration)
		#expect(LocalCommand.unignore.group == .configuration)
		#expect(LocalCommand.timer.group == .timer)
		#expect(LocalCommand.kickban.group == .moderation)
		#expect(LocalCommand.modeShortcut.group == .mode)
		#expect(LocalCommand.deop.group == .mode)
		#expect(LocalCommand.goto.group == .window)
		#expect(LocalCommand.invite.group == .lifecycle)
		#expect(LocalCommand.setqueryname.group == .conversation)
		#expect(LocalCommand.topicShortcut.group == .conversation)
		#expect(LocalCommand.raw.group == .raw)
		#expect(LocalCommand.mylag.group == .information)

		let forwarded = LocalCommand.allCases.filter { $0.group == nil }.map(\.rawValue)

		#expect(forwarded.sorted() == ["adchat", "chatops", "globops", "locops", "nachat", "pass", "whowas"])
	}

	// MARK: - Trailing parameters

	@Test
	func theTrailingParameterDrivesTheOutgoingLine() throws {
		#expect(
			try SendingMessage.string(command: .privmsg, arguments: ["#chat", "hello there"])
				== "PRIVMSG #chat :hello there"
		)
		#expect(
			try SendingMessage.string(command: .kick, arguments: ["#chat", "alice", "bye now"])
				== "KICK #chat alice :bye now"
		)
		#expect(
			try SendingMessage.string(command: .user, arguments: ["user", "0", "*", "real name"])
				== "USER user 0 * :real name"
		)
		/* PASS declares no position, so nothing before the last argument gets a
		 colon — but a last argument holding a space still needs the trailing
		 marker to survive the wire as one token. */
		#expect(try SendingMessage.string(command: .pass, arguments: ["a b"]) == "PASS :a b")
		#expect(try SendingMessage.string(command: .join, arguments: ["#chat"]) == "JOIN #chat")
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
