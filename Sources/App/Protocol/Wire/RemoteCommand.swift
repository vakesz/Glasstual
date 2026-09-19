// Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// A command that travels on the wire.
///
/// The raw value is the wire name, lower-cased, which is what an inbound line
/// is matched against.
nonisolated enum RemoteCommand: String, Sendable, CaseIterable {
	case account
	/// IRCv3 `labeled-response`: the answer a server sends when it has nothing
	/// else to say about a labelled command. Inbound only, like `PASS` it has
	/// no trailing-parameter rule because the session never sends one.
	case ack
	case adchat
	case authenticate
	case away
	case batch
	case cap
	case certinfo
	case chathistory
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
	case silence
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
nonisolated enum TrailingParameter: Sendable, Equatable {
	case startsAtArgument(Int)

	/// The command never takes a trailing parameter, so each of its parameters
	/// is its own wire token.
	case never
}

nonisolated extension RemoteCommand { // nonisolated: pure
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
		/* Every parameter of a CHATHISTORY subcommand is one token: the subcommand,
			a target, a selector such as `timestamp=…` and a limit. */
		.chathistory: .never,
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
		.silence: .never,
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
