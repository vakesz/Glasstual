// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

enum CTCPLagRating: Sendable {
	case excellent
	case suspiciouslyFast
	case veryGood
	case good
	case acceptable
	case needsWork
	case slow
	case verySlow

	init(milliseconds: Double) {
		switch milliseconds {
		case ...10: self = .excellent
		case ...25: self = .suspiciouslyFast
		case ...100: self = .veryGood
		case ...125: self = .good
		case ...200: self = .acceptable
		case ...225: self = .needsWork
		case ...300: self = .slow
		default: self = .verySlow
		}
	}

	/// How this rating reads in the `/lagcheck` reply the user sends back to
	/// the channel.
	var ratingText: String {
		switch self {
		case .excellent: String(localized: .IRC.yeahOkay)
		case .suspiciouslyFast: String(localized: .IRC.areYouPluggedIntoTheServer)
		case .veryGood: String(localized: .IRC.prettyGood)
		case .good: String(localized: .IRC.notBad)
		case .acceptable: String(localized: .IRC.lagcheckCommandOkay)
		case .needsWork: String(localized: .IRC.needsWork)
		case .slow: String(localized: .IRC.lagcheckCommandSlow)
		case .verySlow: String(localized: .IRC.verySlow)
		}
	}
}

/// CTCP wraps an extended message between two `0x01` bytes. ACTION is the one
/// extended message Glasstual both writes and reads, on the IRC connection and
/// on a direct chat alike, so its framing is spelled out once here instead of
/// at each of those sites.
enum CTCPPayload {
	static let delimiter = "\u{01}"

	private static let actionCommand = "ACTION"

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
		framed(command: actionCommand, text: message, sanitizingLineBreaks: false)
	}

	/// The message inside an ACTION frame, or `nil` when the line is not one.
	/// A frame missing its closing delimiter still parses: some clients omit
	/// it.
	static func actionText(in line: String) -> String? {
		let prefix = "\(delimiter)\(actionCommand) "
		guard line.hasPrefix(prefix) else { return nil }
		var body = line.dropFirst(prefix.count)
		if body.hasSuffix(delimiter) {
			body = body.dropLast()
		}
		return String(body)
	}
}

enum CTCPPolicy {
	static func commandAndArguments(from text: String) -> (command: String, arguments: String)? {
		// CTCP tokens are separated by SPACE (0x20), not by Unicode whitespace.
		let parts = text.unicodeScalars.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
		guard let command = parts.first, command.isEmpty == false else { return nil }
		return (String(command).uppercased(), parts.count > 1 ? String(parts[1]) : "")
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

private let ctcpLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCCTCP"
)

/** How many CTCP queries get an answer, and how quickly.

 A reply is a `NOTICE` the client sends on its own, so a channel full of
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

@MainActor
extension Client {
	func receiveCTCPQuery(_ message: Message, text: String) {
		let sender = message.senderNickname ?? ""
		let isLocalUser = nicknameIsMyself(sender)
		let ignore = isLocalUser ? nil : message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))
		guard let parsed = CTCPPolicy.commandAndArguments(from: text) else { return }

		/* A lag check is a query the client sends itself, so with echo-message
		 the copy that comes back is the only one there is. It has to be read
		 before echoes of queries sent to other people are set aside. */
		if parsed.command == "LAGCHECK" {
			receiveCTCPLagCheckQuery(message, text: parsed.arguments)
			return
		}
		if isLocalUser, isCapabilityEnabled(.echoMessage) {
			return
		}
		if ignore?.ignoreClientToClientProtocol == true {
			return
		}
		guard environment.preferences.replyToCTCPRequests else {
			printDebugInformation(toConsole: String(localized: .IRC.ctcpFromWasIgnored(parsed.command, sender)))
			return
		}
		if parsed.command == "DCC" {
			receivedDCCQuery(message, text: parsed.arguments, ignoreInfo: ignore)
			return
		}

		let printTarget = noticePrintTarget()
		print(String(localized: .IRC.miscellaneousMessagesRelatedCtcp(parsed.command, sender)), by: nil, in: printTarget, as: .ctcpQuery,
		      command: message.command, receivedAt: message.receivedAt)

		guard let replyText = ctcpReplyText(for: parsed.command, arguments: parsed.arguments) else {
			return
		}

		/* The query is still printed — it is the user's record of the flood —
		 but answering every one of them is what gets the connection killed for
		 excess flood. The throttle is consulted only once there is an answer to
		 send, so a burst of commands this client does not implement cannot spend
		 the allowance a real query needs. */
		guard allowsCTCPReply(to: sender) else {
			ctcpLogger.notice("Throttled a CTCP reply")
			return
		}

		sendCTCPReply(sender, command: parsed.command, text: replyText)
	}

	/// What this client answers `command` with, or `nil` when it answers nothing.
	private func ctcpReplyText(for command: String, arguments: String) -> String? {
		switch command {
		case "CLIENTINFO":
			return String(localized: .IRC.clientinfoDccFingerPingTimeUserinfo)
		case "FINGER":
			return String(localized: .IRC.stopFingeringMePervert)
		case "PING":
			guard arguments.utf8.count <= 50 else {
				ctcpLogger.fault("Ignoring PING query that exceeds 50 bytes")
				return nil
			}

			return arguments
		case "TIME":
			return DateFormatting.iso8601String(from: Date())
		case "USERINFO":
			return config.realName
		case "VERSION":
			let masquerade = config.ctcpVersionReply?.nonEmpty ?? environment.preferences.masqueradeCTCPVersion?
				.nonEmpty

			return masquerade ?? String(localized: .IRC.ircClientV(
				ApplicationInfo.applicationName(),
				ApplicationInfo.applicationVersionShort()
			))
		default:
			return nil
		}
	}

	/// Whether this query gets an answer, counting it against the throttle.
	func allowsCTCPReply(to sender: String) -> Bool {
		ctcpReplyThrottle.recordReply(to: sender, at: Date())
	}

	func receiveCTCPLagCheckQuery(_ message: Message, text: String) {
		guard messageIsFromMyself(message) else { return }
		let context = CTCPPolicy.formData(text)
		guard let socket, context["connection"] == socket.uniqueIdentifier,
		      let time = context["time"].flatMap(Double.init)
		else { return }
		let delta = (Date().timeIntervalSince1970 - time) * 1000
		let rating = CTCPLagRating(milliseconds: delta).ratingText
		let response = String(localized: .IRC.receivedLagCheckReplyFromTime(serverAddress ?? "", Float(delta), rating))
		if let channelName = context["channel"], let channel = findChannel(channelName) {
			sendPrivmsg(response, to: channel)
		} else {
			printDebugInformation(response)
		}
	}

	func receiveCTCPReply(_ message: Message, text: String) {
		if let hostmask = message.senderHostmask,
		   findAddressBookEntry(forHostmask: hostmask)?.ignoreClientToClientProtocol == true
		{
			return
		}
		guard let parsed = CTCPPolicy.commandAndArguments(from: text) else { return }
		let sender = message.senderNickname ?? ""
		let output: String
		/* Only a PING whose echo comes back as the number that was sent can be
		 timed. An unparsable one used to read as zero — the epoch — and the
		 client reported a lag of fifty-six years rather than saying nothing. */
		if parsed.command == "PING", let echoedTime = Double(parsed.arguments), echoedTime.isFinite {
			let delta = Date().timeIntervalSince1970 - echoedTime
			output = String(localized: .IRC.ctcpSec(sender, parsed.command, Float(delta)))
		} else {
			output = String(localized: .IRC.ctcp(sender, parsed.command, parsed.arguments))
		}
		print(output, by: nil, in: noticePrintTarget(), as: .ctcpReply,
		      command: message.command, receivedAt: message.receivedAt)
	}

	private func noticePrintTarget() -> Channel? {
		guard environment.preferences.locationToSendNotices == .selectedChannel else { return nil }
		return output?.selectedChannel(on: self)
	}
}
