// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The CTCP extended messages this session names.

 A verb is an ASCII token the sender may spell in any case, so the raw values
 are the upper-cased wire spelling and ``init(wireName:)`` folds to it. A verb
 with no case here is still carried by name, because a query this session does
 not implement is printed and answered by the person, not by the catalogue. */
nonisolated enum CTCPVerb: String, Sendable, CaseIterable {
	case action = "ACTION"
	case clientInfo = "CLIENTINFO"
	case dcc = "DCC"
	case finger = "FINGER"
	case lagCheck = "LAGCHECK"
	case ping = "PING"
	case time = "TIME"
	case userInfo = "USERINFO"
	case version = "VERSION"

	init?(wireName: String) {
		self.init(rawValue: wireName.uppercased())
	}

	/// The verb as it goes out inside the frame.
	var wireName: String {
		rawValue
	}

	/// The verbs a `CLIENTINFO` reply lists: every one this session reads or
	/// answers, which leaves out `LAGCHECK`, a query it sends only to itself.
	static var advertised: [CTCPVerb] {
		allCases.filter { $0 != .lagCheck }
	}

	/// What a peer is told after the verb's name when it asks `CLIENTINFO <verb>`.
	/// This is protocol text that goes to another client, so it stays out of
	/// the String Catalogs, where a translation would change what is sent.
	var clientInfoDescription: String {
		switch self {
		case .action: "shows its text as an action, like /me"
		case .clientInfo: "lists the supported verbs, or describes the one named"
		case .dcc: "offers a file (SEND, or SSEND over TLS) or a direct chat (CHAT, or SCHAT over TLS)"
		case .finger: "returns a short message"
		case .lagCheck: "measures lag to the server"
		case .ping: "returns its token unchanged"
		case .time: "returns the local time in ISO 8601"
		case .userInfo: "returns text the user chose to share"
		case .version: "returns the client name"
		}
	}
}

/// A CTCP reply before it is framed: the verb it carries and its text.
nonisolated struct CTCPReply: Sendable, Equatable {
	let command: String
	let text: String
}

/** How `CLIENTINFO` is answered.

 With no argument the reply lists the verbs. With one it describes that verb,
 or says through `ERRMSG` that the verb is not one of them. An argument is
 echoed back in the error, so one longer than a `PING` parameter earns no
 reply, the same bound that keeps the session from being an amplifier. */
nonisolated enum CTCPClientInfo {
	/// The longest argument that is answered, in UTF-8 bytes.
	static let maximumArgumentBytes = 50

	/// The list a bare `CLIENTINFO` is answered with.
	static var verbList: String {
		CTCPVerb.advertised.map(\.wireName).joined(separator: " ")
	}

	static func reply(toArguments arguments: String) -> CTCPReply? {
		guard arguments.utf8.count <= maximumArgumentBytes else { return nil }

		let verbName = arguments.split(separator: " ", maxSplits: 1).first.map(String.init)

		guard let verbName else {
			return CTCPReply(command: CTCPVerb.clientInfo.wireName, text: verbList)
		}
		guard let verb = CTCPVerb(wireName: verbName), CTCPVerb.advertised.contains(verb) else {
			return CTCPReply(command: "ERRMSG", text: "\(CTCPVerb.clientInfo.wireName) \(verbName) :Unknown CTCP verb")
		}

		return CTCPReply(command: CTCPVerb.clientInfo.wireName, text: "\(verb.wireName) :\(verb.clientInfoDescription)")
	}
}

/// CTCP wraps an extended message between two `0x01` bytes. ACTION is the one
/// extended message Glasstual both writes and reads, on the IRC connection and
/// on a direct chat alike, so its framing is spelled out once here instead of
/// at each of those sites.
enum CTCPPayload {
	static let delimiter = "\u{01}"

	static func framed(command: String, text: String?, sanitizingLineBreaks: Bool) -> String {
		var payload = text.map { "\(command) \($0)" } ?? command
		if sanitizingLineBreaks {
			payload = payload.replacingOccurrences(of: "\r", with: " ")
			payload = payload.replacingOccurrences(of: "\n", with: " ")
		}
		/* modern.ircdocs.horse defines no way to quote a delimiter inside a
		 CTCP message, so one carried in the text ends the frame at the
		 receiver: everything after it is silently dropped and what follows can
		 be read as a second extended message. Removing it is the only way to
		 send the text the user actually wrote. */
		payload = payload.replacingOccurrences(of: delimiter, with: "")
		return "\(delimiter)\(payload)\(delimiter)"
	}

	static func action(_ message: String) -> String {
		framed(command: CTCPVerb.action.wireName, text: message, sanitizingLineBreaks: false)
	}

	/// The message inside an ACTION frame, or `nil` when the line is not one.
	/// A frame missing its closing delimiter still parses: some clients omit
	/// it.
	static func actionText(in line: String) -> String? {
		let prefix = "\(delimiter)\(CTCPVerb.action.wireName) "
		guard line.hasPrefix(prefix) else { return nil }
		var body = line.dropFirst(prefix.count)
		if body.hasSuffix(delimiter) {
			body = body.dropLast()
		}
		return String(body)
	}
}

/** One extended message read out of a CTCP frame: the verb it names and the
 text behind it.

 `rawCommand` is the verb as it was sent, upper-cased; `verb` is `nil` when this
 session has no case for it, which is how an unknown query keeps being printed
 and answered by the name the sender used. */
nonisolated struct CTCPMessage: Sendable, Equatable {
	let verb: CTCPVerb?
	let rawCommand: String
	let arguments: String
}

enum CTCPPolicy {
	/// The extended message `text` carries, or `nil` when it names no verb.
	static func commandAndArguments(from text: String) -> CTCPMessage? {
		// CTCP tokens are separated by SPACE (0x20), not by Unicode whitespace.
		let parts = text.unicodeScalars.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
		guard let command = parts.first, command.isEmpty == false else { return nil }
		let rawCommand = String(command).uppercased()
		return CTCPMessage(
			verb: CTCPVerb(rawValue: rawCommand),
			rawCommand: rawCommand,
			arguments: parts.count > 1 ? String(parts[1]) : ""
		)
	}

	/// The characters a form field keeps as they are. `&`, `=` and `+` are the
	/// form's own syntax, and `&` also opens a local channel name.
	private static let formFieldAllowedCharacters = CharacterSet.urlQueryAllowed.subtracting(
		CharacterSet(charactersIn: "&=+")
	)

	/// `fields` written as `key=value&…`, each side percent-encoded so that no
	/// value can be read back as the form's syntax.
	static func formEncoded(_ fields: [(key: String, value: String)]) -> String {
		fields.map { field in
			encodedFormField(field.key) + "=" + encodedFormField(field.value)
		}.joined(separator: "&")
	}

	private static func encodedFormField(_ string: String) -> String {
		string.addingPercentEncoding(withAllowedCharacters: formFieldAllowedCharacters) ?? ""
	}

	/// The fields of a `key=value&…` form, percent-decoded. A field whose
	/// encoding is invalid is dropped.
	static func formData(_ text: String) -> [String: String] {
		// The text is server-controlled and may repeat a key, so duplicates
		// must merge rather than trap. The first occurrence wins.
		Dictionary(
			text.split(separator: "&").compactMap { field -> (String, String)? in
				let pair = field.split(separator: "=", maxSplits: 1)
				guard pair.count == 2,
				      let key = String(pair[0]).removingPercentEncoding,
				      let value = String(pair[1]).removingPercentEncoding
				else { return nil }
				return (key, value)
			},
			uniquingKeysWith: { first, _ in first }
		)
	}
}

/** How many CTCP queries get an answer, and how quickly.

 A reply is a `NOTICE` the session sends on its own, so a channel full of
 `VERSION` queries — or one scripted sender — turns into as many outgoing lines
 as the flood-control queue will hold, and the server kills the connection for
 excess flood. The per-sender ceiling stops one person doing it; the overall
 one stops a channel's worth of people doing it together.

 The counts are timestamps rather than a running total so that the window
 slides: a sender who asked five times a minute ago is answered again now. */
nonisolated struct CTCPReplyThrottle: Sendable {
	/// How long a reply is remembered for.
	static let window: TimeInterval = 60
	/// Replies one sender gets inside the window.
	static let perSenderLimit = 5
	/// Replies everyone together gets inside the window.
	static let overallLimit = 30
	/** Senders remembered at once.

	 The dictionary is keyed by a nickname the network chooses, so it is
	 bounded: a flood from ten thousand names would otherwise be a flood of
	 dictionary entries. Past the ceiling the least recently heard from is
	 dropped, which at worst forgives an old sender one reply.

	 Larger than `overallLimit` on purpose: the overall ceiling is what a flood
	 runs into first, and entries have to outlive it for the per-sender count to
	 mean anything. */
	static let maximumTrackedSenders = 128

	private var replyTimesBySender: [String: [Date]] = [:]

	/// Whether `sender` may be answered now, counting the reply if so.
	mutating func recordReply(to sender: String, at now: Date) -> Bool {
		expire(before: now.addingTimeInterval(-Self.window))

		let senderCount = replyTimesBySender[sender]?.count ?? 0
		let overallCount = replyTimesBySender.values.reduce(0) { $0 + $1.count }

		guard senderCount < Self.perSenderLimit, overallCount < Self.overallLimit else {
			return false
		}

		replyTimesBySender[sender, default: []].append(now)
		evictOldestSenderIfNeeded()

		return true
	}

	private mutating func expire(before cutoff: Date) {
		for (sender, times) in replyTimesBySender {
			let recent = times.filter { $0 > cutoff }

			if recent.isEmpty {
				replyTimesBySender.removeValue(forKey: sender)
			} else {
				replyTimesBySender[sender] = recent
			}
		}
	}

	private mutating func evictOldestSenderIfNeeded() {
		guard replyTimesBySender.count > Self.maximumTrackedSenders else {
			return
		}

		let oldest = replyTimesBySender.min { first, second in
			(first.value.last ?? .distantPast) < (second.value.last ?? .distantPast)
		}

		guard let oldest else { return }

		replyTimesBySender.removeValue(forKey: oldest.key)
	}
}
