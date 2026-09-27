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
