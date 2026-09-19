// Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// A command the user types into the input field.
///
/// The raw value is the name as typed, lower-cased: it is the only key the
/// session matches a `/command` against. Cases whose Swift name cannot be the
/// wire name — a shorthand, or a name with an underscore — spell theirs out.
enum LocalCommand: String, Sendable, CaseIterable {
	case adchat
	case ame
	case amsg
	case aquote
	case araw
	case attach
	case autojoin
	case away
	case back
	case ban
	case cap
	case caps
	case chathistory
	case chatops
	case clear
	case clearall
	case close
	case conn
	case ctcp
	case ctcpreply
	case cycle
	case dcc
	case debug
	case defaults
	case dehalfop
	case detach
	case deop
	case devoice
	case echo
	case gline
	case globops
	case goto
	case gzline
	case halfop
	case hop
	case ignore
	case invite
	case ison
	case j
	case join
	case joinRandom = "join_random"
	case kb
	case kick
	case kickban
	case kill
	case lagcheck
	case leave
	case list
	case locops
	/// `/m`, the shorthand for `/mode`.
	case modeShortcut = "m"
	case me
	case mode
	case monitor
	case msg
	case mute
	case mylag
	case myversion
	case nachat
	case names
	case nick
	case notice
	case notifybubble
	case notifysound
	case omsg
	case onotice
	case op
	case part
	case pass
	case query
	case quiet
	case quit
	case quote
	case raw
	case recv
	case rejoin
	case remove
	case server
	case setcolor
	case setname
	case setqueryname
	case shun
	case silence
	case sme
	case smsg
	case sslcontext
	/// `/t`, the shorthand for `/topic`.
	case topicShortcut = "t"
	case tage
	case tempshun
	case timer
	case topic
	case ume
	case umode
	case umsg
	case unban
	case unignore
	case unmute
	case unotice
	case unquiet
	case voice
	case wallops
	case watch
	case weights
	case who
	case whois
	case whowas
	case zline
	case znccert
}

extension LocalCommand {
	/** The handler a command belongs to.

	 One case per handler and nothing above them: `ServerSession.sendCommand` reads this
	 and calls the handler, so a name here is the name of a function rather than
	 a level in a taxonomy. */
	enum Group: Sendable, Equatable {
		case directChat
		case message
		case broadcast
		case ctcp
		case configuration
		case timer
		case moderation
		case lifecycle
		case window
		case mode
		case conversation
		case bouncer
		case raw
		case request
		case operatorControl
		case session
		case notification
		case capability
		case information
	}

	/// Matches the name however the user capitalised it.
	init?(typedName: String) {
		self.init(rawValue: typedName.lowercased())
	}

	/// The name as the transcript spells it back to the user.
	var displayName: String {
		rawValue.uppercased()
	}

	/** The wire command this `/command` relays to unchanged, or `nil` when it has
	 no wire name of its own.

	 The two catalogues key on the same lower-cased spelling, so a command the
	 session passes straight through — `/gline`, `/monitor`, `/silence` — is the
	 remote command of the same name. A handler that builds its own line names
	 the `RemoteCommand` it sends instead. */
	var relayedRemoteCommand: RemoteCommand? {
		RemoteCommand(rawValue: rawValue)
	}

	/** The handler the command belongs to.

	 `ServerSession.sendCommand` makes one routing decision from this and the
	 handler it picks answers with a plain switch. `nil` means the session has no
	 handler of its own for the name, so it goes to a user script or to the
	 server as the user typed it.
	 */
	var group: Group? {
		switch self {
		case .dcc: .directChat
		case .msg, .omsg, .smsg, .umsg, .me, .sme, .ume, .notice, .onotice, .unotice: .message
		case .ame, .amsg: .broadcast
		case .ctcp, .ctcpreply: .ctcp
		case .defaults, .ignore, .unignore: .configuration
		case .timer: .timer
		case .ban, .kb, .kick, .kickban, .quiet, .unban, .unquiet: .moderation
		case .j, .join, .joinRandom, .cycle, .hop, .rejoin, .leave, .part, .invite: .lifecycle
		case .clear, .clearall, .close, .remove, .list, .setcolor, .goto: .window
		case .modeShortcut, .mode, .op, .deop, .halfop, .dehalfop, .voice, .devoice: .mode
		case .query, .topicShortcut, .topic, .setqueryname: .conversation
		case .aquote, .araw, .quote, .raw, .cap, .caps, .debug, .echo: .raw
		case .ison, .names, .recv, .setname, .wallops: .request
		case .gline, .gzline, .shun, .tempshun, .zline, .kill: .operatorControl
		case .conn, .back, .away, .autojoin, .nick, .quit, .server, .sslcontext: .session
		case .mute, .unmute, .notifybubble, .notifysound: .notification
		case .chathistory, .umode, .monitor, .watch, .silence: .capability
		case .who, .whois, .weights, .myversion, .tage, .lagcheck, .mylag: .information
		case .attach, .detach, .znccert: .bouncer
		default: nil
		}
	}

	/// Kept out of completion, and refused with a message rather than forwarded
	/// to the server, unless the developer-mode setting is on.
	var isDeveloperModeOnly: Bool {
		Self.developerModeOnlyCommands.contains(self)
	}

	/// The documented argument syntax, or `nil` for a command that takes none.
	var arguments: String? {
		Self.argumentSyntax[self]
	}

	/// The documented syntax as an invalid-syntax message quotes it.
	var syntax: String {
		guard let arguments else {
			return displayName
		}

		return "\(displayName) \(arguments)"
	}

	/// How many argument groups the documented syntax declares.
	var arity: CommandArity {
		CommandArity(syntax: arguments)
	}

	private static let developerModeOnlyCommands: Set<LocalCommand> = [.joinRandom, .recv, .tage]

	private static let argumentSyntax: [LocalCommand: String] = [
		.adchat: "<message>",
		.ame: "<message>",
		.amsg: "<message>",
		.aquote: "<input>",
		.araw: "<input>",
		.attach: "[channel]",
		.away: "[comment]",
		.ban: "[channel] <nickname>",
		.chathistory: "<subcommand> <target> [arguments]",
		.close: "[target]",
		.conn: "[server]",
		.ctcp: "<nickname> <command> [extra]",
		.ctcpreply: "<nickname> <command> [extra]",
		.dcc: "chat <nickname> | send <nickname> <path>",
		.debug: "<message>",
		.dehalfop: "[channel] <nickname>",
		.detach: "[channel]",
		.deop: "[channel] <nickname>",
		.devoice: "[channel] <nickname>",
		.echo: "<message>",
		.gline: "<+ | -><hostmask | nickname> [duration] [comment]",
		.globops: "<message>",
		.goto: "<needle>",
		.gzline: "<+ | -><hostmask | nickname> [duration] [comment]",
		.halfop: "[channel] <nickname>",
		.ignore: "<nickname>",
		.invite: "<nickname> [channel]",
		.ison: "<nickname>",
		.j: "<channel[,channel]]> [key[,key]]",
		.join: "<channel[,channel]]> [key[,key]]",
		.joinRandom: "[count]",
		.kb: "[channel] <nickname> [comment]",
		.kick: "[channel] <nickname> [comment]",
		.kickban: "[channel] <nickname> [comment]",
		.kill: "<nickname> [comment]",
		.leave: "[comment]",
		.locops: "<message>",
		.modeShortcut: "<target> [flags] [arguments]",
		.me: "<message>",
		.mode: "<target> [flags] [arguments]",
		.msg: "<target[,target]]> <message>",
		.nachat: "<message>",
		.names: "<channel>",
		.nick: "<nickname>",
		.notice: "<target[,target]]> <message>",
		.notifybubble: "[target] <message>",
		.notifysound: "<sound>",
		.omsg: "<channel> <message>",
		.onotice: "<channel> <message>",
		.op: "[channel] <nickname>",
		.part: "[comment]",
		.pass: "<password>",
		.query: "<nickname>",
		.quiet: "[channel] <nickname>",
		.quit: "[comment]",
		.quote: "<input>",
		.raw: "<input>",
		.recv: "<input>",
		.remove: "[target]",
		.server: "<address> [[+] port] [password]",
		.setcolor: "<nickname>",
		.setname: "<real name>",
		.setqueryname: "<nickname>",
		.shun: "<+ | -><hostmask | nickname> [duration] [comment]",
		.silence: "[<+ | -><hostmask | nickname>]",
		.sme: "<target[,target]]> <message>",
		.smsg: "<target[,target]]> <message>",
		.topicShortcut: "<channel> [topic]",
		.tempshun: "<+ | -><hostmask | nickname> [comment]",
		.timer: "<seconds> <repeat> <command>",
		.topic: "<channel> [topic]",
		.ume: "<target> <message>",
		.umode: "[flags] [arguments]",
		.umsg: "<target> <message>",
		.unban: "[channel] <nickname>",
		.unignore: "<nickname>",
		.unotice: "<target> <message>",
		.unquiet: "[channel] <nickname>",
		.voice: "[channel] <nickname>",
		.wallops: "<message>",
		.who: "<channel>",
		.whois: "<nickname>",
		.whowas: "<nickname>",
		.zline: "<+ | -><hostmask | nickname> [duration] [comment]",
	]
}

/// The names `/`-completion offers.
///
/// Everything else a command declares is a property of `LocalCommand` or
/// `RemoteCommand`; only the completion lists are worth keeping built.
enum CommandIndex {
	static func localCommandList(includingDeveloperCommands: Bool) -> [String] {
		includingDeveloperCommands ? allCommandNames : publicCommandNames
	}

	private static let allCommandNames = LocalCommand.allCases.map(\.displayName)

	private static let publicCommandNames = LocalCommand.allCases
		.filter { $0.isDeveloperModeOnly == false }
		.map(\.displayName)
}
