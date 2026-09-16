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

import CocoaExtensions
import Foundation

/// A command the user types into the input field.
///
/// The raw value is the name as typed, lower-cased: it is the only key the
/// client matches a `/command` against. Cases whose Swift name cannot be the
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
	/// The handler a command belongs to.
	enum Group: Sendable, Equatable {
		case directChat
		case message
		case defaults
		case ignore
		case timer
		case channel(ChannelGroup)
		case native(NativeGroup)
	}

	/// The handlers that act on a channel or a query.
	enum ChannelGroup: Sendable {
		case broadcast
		case ctcp
		case moderation
		case privilege
		case lifecycle
		case navigation
		case window
		case membership
		case mode
		case queryRename
		case conversation
	}

	/// The handlers that act on the connection itself.
	enum NativeGroup: Sendable {
		case bouncer
		case raw
		case request
		case operatorControl
		case session
		case notification
		case capability
		case information
		case lag
	}

	/// Matches the name however the user capitalised it.
	init?(typedName: String) {
		self.init(rawValue: typedName.lowercased())
	}

	/// The name as the transcript spells it back to the user.
	var displayName: String {
		rawValue.uppercased()
	}

	/** The handler the command belongs to.

	 `Client.sendCommand` makes one routing decision from this and the
	 handler it picks answers with a plain switch. `nil` means the client has no
	 handler of its own for the name, so it goes to a user script or to the
	 server as the user typed it.
	 */
	var group: Group? {
		switch self {
		case .dcc: .directChat
		case .msg, .omsg, .smsg, .umsg, .me, .sme, .ume, .notice, .onotice, .unotice: .message
		case .defaults: .defaults
		case .ignore, .unignore: .ignore
		case .timer: .timer
		case .ame, .amsg: .channel(.broadcast)
		case .ctcp, .ctcpreply: .channel(.ctcp)
		case .ban, .kb, .kick, .kickban, .quiet, .unban, .unquiet: .channel(.moderation)
		case .op, .deop, .halfop, .dehalfop, .voice, .devoice: .channel(.privilege)
		case .j, .join, .joinRandom, .cycle, .hop, .rejoin, .leave, .part: .channel(.lifecycle)
		case .goto: .channel(.navigation)
		case .clear, .clearall, .close, .remove, .list, .setcolor: .channel(.window)
		case .invite: .channel(.membership)
		case .modeShortcut, .mode: .channel(.mode)
		case .setqueryname: .channel(.queryRename)
		case .query, .topicShortcut, .topic: .channel(.conversation)
		case .aquote, .araw, .quote, .raw, .cap, .caps, .debug, .echo: .native(.raw)
		case .ison, .names, .recv, .setname, .wallops: .native(.request)
		case .gline, .gzline, .shun, .tempshun, .zline, .kill: .native(.operatorControl)
		case .conn, .back, .away, .autojoin, .nick: .native(.session)
		case .mute, .unmute, .notifybubble, .notifysound, .quit, .server, .sslcontext:
			.native(.notification)
		case .chathistory, .umode, .monitor, .watch, .silence: .native(.capability)
		case .who, .whois, .weights, .myversion, .tage: .native(.information)
		case .lagcheck, .mylag: .native(.lag)
		case .attach, .detach, .znccert: .native(.bouncer)
		default: nil
		}
	}

	/// Kept out of completion, and refused with a message rather than forwarded
	/// to the server, unless the developer-mode preference is on.
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

/// A command that travels on the wire.
///
/// The raw value is the wire name, lower-cased, which is what an inbound line
/// is matched against.
enum RemoteCommand: String, Sendable, CaseIterable {
	case account
	case adchat
	case authenticate
	case away
	case batch
	case cap
	case certinfo
	case chatops
	case chghost
	case error
	case fail
	case gline
	case globops
	case gzline
	case invite
	case ison
	case join
	case kick
	case kill
	case list
	case markread
	case locops
	case mode
	case monitor
	case nachat
	case names
	case nick
	case note
	case notice
	case part
	case pass
	case ping
	case pong
	case privmsg
	/// A `PRIVMSG` whose body is a CTCP `ACTION`. Outbound only: a received
	/// action is recognised from the payload, not from the command word, so the
	/// raw value is deliberately not a legal command name — a wire command
	/// cannot contain a space, which is what keeps an inbound line from ever
	/// selecting this case.
	case privmsgAction = "privmsg action"
	case quit
	case setname
	case shun
	case tagmsg
	case tempshun
	case topic
	case user
	case wallops
	case warn
	case watch
	case who
	case whois
	case whowas
	case zline
}

/// Where a command's trailing parameter begins.
///
/// Every parameter before it is one wire token; the one at that index carries
/// the rest of the line behind a colon.
nonisolated enum TrailingParameter: Sendable, Equatable { // nonisolated: value
	case startsAtArgument(Int)

	/// The command never takes a trailing parameter, so each of its parameters
	/// is its own wire token.
	case never
}

extension RemoteCommand {
	/// Matches the wire name however the server capitalised it.
	init?(wireName: String) {
		self.init(rawValue: wireName.lowercased())
	}

	/// The wire name as it goes out.
	var wireName: String {
		self == .privmsgAction ? "PRIVMSG" : rawValue.uppercased()
	}

	/// Where the command puts its trailing parameter, or `nil` when it has no
	/// fixed position and a caller has to mark its own.
	var trailingParameter: TrailingParameter? {
		Self.trailingParameters[self]
	}

	/** `PASS` is deliberately absent: a password is one token wherever it sits,
	 and colonising it by position would change the credential. */
	private static let trailingParameters: [RemoteCommand: TrailingParameter] = [
		.account: .never,
		.adchat: .startsAtArgument(0),
		.authenticate: .never,
		.away: .startsAtArgument(0),
		.batch: .never,
		.cap: .never,
		.certinfo: .never,
		.chatops: .startsAtArgument(0),
		.chghost: .never,
		.error: .startsAtArgument(0),
		.fail: .startsAtArgument(2),
		.gline: .startsAtArgument(2),
		.globops: .startsAtArgument(0),
		.gzline: .startsAtArgument(2),
		.invite: .never,
		.ison: .never,
		.join: .never,
		.kick: .startsAtArgument(2),
		.kill: .startsAtArgument(1),
		.list: .never,
		.markread: .never,
		.locops: .startsAtArgument(0),
		.mode: .never,
		.monitor: .never,
		.nachat: .startsAtArgument(0),
		.names: .never,
		.nick: .never,
		.note: .startsAtArgument(2),
		.notice: .startsAtArgument(1),
		.part: .startsAtArgument(1),
		.ping: .never,
		.pong: .never,
		.privmsg: .startsAtArgument(1),
		.privmsgAction: .startsAtArgument(1),
		.quit: .startsAtArgument(0),
		.setname: .startsAtArgument(0),
		.shun: .startsAtArgument(2),
		.tagmsg: .never,
		.tempshun: .startsAtArgument(1),
		.topic: .startsAtArgument(1),
		.user: .startsAtArgument(3),
		.wallops: .startsAtArgument(0),
		.warn: .startsAtArgument(2),
		.watch: .never,
		.who: .never,
		.whois: .never,
		.whowas: .never,
		.zline: .startsAtArgument(2),
	]
}

/// The names `/`-completion offers.
///
/// Everything else a command declares is a property of `LocalCommand` or
/// `RemoteCommand`; only the completion lists are worth keeping built.
enum CommandIndex {
	static func localCommandList() -> [String] {
		Preferences.Commands.developerMode.value ? allCommandNames : publicCommandNames
	}

	private static let allCommandNames = LocalCommand.allCases.map(\.displayName)

	private static let publicCommandNames = LocalCommand.allCases
		.filter { $0.isDeveloperModeOnly == false }
		.map(\.displayName)
}

/// How many argument groups a command's documented syntax declares.
///
/// Every top-level `<group>` is required and every `[group]` is optional. It
/// describes the documented syntax, not what a particular handler goes on to
/// read.
nonisolated struct CommandArity: Sendable, Equatable { // nonisolated: value
	let required: Int
	let optional: Int

	static let none = CommandArity(required: 0, optional: 0)

	init(required: Int, optional: Int) {
		self.required = required
		self.optional = optional
	}

	init(syntax: String?) {
		guard let syntax else {
			self = .none

			return
		}

		var required = 0
		var optional = 0
		var depth = 0
		var openedWith: Character?

		for character in syntax {
			switch character {
			case "<", "[":
				if depth == 0 {
					openedWith = character
				}

				depth += 1
			case ">", "]":
				guard depth > 0 else {
					continue
				}

				depth -= 1

				if depth == 0 {
					if openedWith == "<" {
						required += 1
					} else {
						optional += 1
					}
				}
			default:
				continue
			}
		}

		self.init(required: required, optional: optional)
	}
}

/// The arguments of a user-typed command, read left to right.
///
/// Commands are typed into a rich-text field and a few of them (ME, TOPIC,
/// MSG) have to put the formatting back on the wire, so the arguments arrive
/// as an `NSAttributedString`. This walks a cursor over that string rather
/// than deleting characters from one shared mutable attributed string: it is a
/// value, so one dispatcher pulling a token can no longer disturb the next one
/// that is handed the same line.
struct CommandArguments {
	private let source: NSAttributedString
	private var tokenizer: CommandTokenizer

	/// What the command index declares this command takes. Handlers read
	/// arguments in whatever order suits them; this is the documented shape.
	let arity: CommandArity

	init(_ source: NSAttributedString, arity: CommandArity = .none) {
		self.source = source
		self.arity = arity
		tokenizer = CommandTokenizer(source.string)
	}

	init(_ source: String, arity: CommandArity = .none) {
		self.init(NSAttributedString(string: source), arity: arity)
	}

	/// Everything the cursor has not passed yet, as plain text.
	var rest: String {
		String(tokenizer.remainder)
	}

	/// Everything the cursor has not passed yet, formatting intact.
	var attributedRest: NSAttributedString {
		let consumed = tokenizer.consumedUTF16Length

		guard consumed > 0 else {
			return source
		}

		guard consumed < source.length else {
			return NSAttributedString()
		}

		return source.attributedSubstring(
			from: NSRange(location: consumed, length: source.length - consumed)
		)
	}

	var isEmpty: Bool {
		rest.isEmpty
	}

	/// How many whitespace-delimited tokens are left.
	var tokenCount: Int {
		var counter = tokenizer
		var count = 0

		while counter.nextToken().isEmpty == false {
			count += 1
		}

		return count
	}

	/// The caller has supplied at least as many tokens as the index declares
	/// required, and at least one either way.
	var satisfiesDeclaredArity: Bool {
		isEmpty == false && tokenCount >= arity.required
	}

	/// Consumes and returns the next whitespace-delimited token, or the empty
	/// string once the line is exhausted.
	mutating func next() -> String {
		tokenizer.nextToken()
	}

	/// Consumes and returns the quoted token at the cursor, or the empty string
	/// when the cursor is not on one. The cursor does not move in that case.
	mutating func nextQuoted() -> String {
		tokenizer.nextQuotedToken()
	}
}

/// A line the user typed into the input field, split into its command and the
/// arguments that follow it.
struct ParsedUserCommand {
	/// The command exactly as typed. Syntax messages quote it and unknown
	/// commands are handed to a user script or to the server under it.
	let command: String

	/// The command the name resolves to, absent when the client has never heard
	/// of it. Handlers switch on this rather than on the string.
	let localCommand: LocalCommand?

	var arguments: CommandArguments

	var isDeveloperModeOnly: Bool {
		localCommand?.isDeveloperModeOnly ?? false
	}

	init?(_ input: Any) {
		let source: NSAttributedString

		if let string = input as? String {
			source = NSAttributedString(string: string)
		} else if let attributed = input as? NSAttributedString {
			source = attributed
		} else {
			assertionFailure("Command input must be String or NSAttributedString")

			return nil
		}

		guard source.length > 0 else {
			return nil
		}

		var line = source

		if line.string.hasPrefix("/") {
			line = line.attributedSubstring(from: NSRange(location: 1, length: line.length - 1))
		}

		var tokenizer = CommandTokenizer(line.string)
		let name = tokenizer.nextToken()
		let remainder = line.attributedSubstring(
			from: NSRange(
				location: tokenizer.consumedUTF16Length,
				length: line.length - tokenizer.consumedUTF16Length
			)
		)

		command = name
		localCommand = LocalCommand(typedName: name)
		arguments = CommandArguments(remainder, arity: localCommand?.arity ?? .none)
	}
}
