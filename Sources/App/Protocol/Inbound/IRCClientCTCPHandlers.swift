/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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
import os

enum IRCCTCPPolicy {
	static func commandAndArguments(from text: String) -> (command: String, arguments: String)? {
		// CTCP tokens are separated by SPACE (0x20), not by Unicode whitespace.
		let parts = text.unicodeScalars.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
		guard let command = parts.first, command.isEmpty == false else { return nil }
		return (String(command).uppercased(), parts.count > 1 ? String(parts[1]) : "")
	}

	static func formData(_ text: String) -> [String: String] {
		// The text is server-controlled and may repeat a key, so duplicates
		// must merge rather than trap. The first occurrence wins.
		Dictionary(
			text.split(separator: "&").compactMap { field -> (String, String)? in
				let pair = field.split(separator: "=", maxSplits: 1)
				guard pair.count == 2 else { return nil }
				return (String(pair[0]), String(pair[1]))
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
nonisolated struct CTCPReplyThrottle: Sendable { // nonisolated: value
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
public extension IRCClient {
	func receiveCTCPQuery(_ message: Message, text: String) {
		let sender = message.senderNickname ?? ""
		let isLocalUser = nicknameIsMyself(sender)
		let ignore = isLocalUser ? nil : message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))
		if isLocalUser, isCapabilityEnabled(.echoMessage) {
			return
		}
		if ignore?.ignoreClientToClientProtocol == true {
			return
		}
		guard let parsed = IRCCTCPPolicy.commandAndArguments(from: text) else { return }

		if parsed.command == "LAGCHECK" {
			receiveCTCPLagCheckQuery(message, text: parsed.arguments)
			return
		}
		guard environment.preferences.replyToCTCPRequests else {
			printDebugInformation(toConsole: IRCCTCPStrings.ignored(command: parsed.command, sender: sender))
			return
		}
		if parsed.command == "DCC" {
			receivedDCCQuery(message, text: parsed.arguments, ignoreInfo: ignore)
			return
		}

		let printTarget = noticePrintTarget()
		print(IRCCTCPStrings.query(command: parsed.command, sender: sender), by: nil, in: printTarget, as: .ctcpQuery,
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
			return IRCCTCPStrings.clientInfoReply
		case "FINGER":
			return IRCCTCPStrings.fingerReply
		case "PING":
			guard arguments.utf8.count <= 50 else {
				ctcpLogger.fault("Ignoring PING query that exceeds 50 bytes")
				return nil
			}

			return arguments
		case "TIME":
			return sharedISOStandardDateFormatter().string(from: Date())
		case "USERINFO":
			return config.realName
		case "VERSION":
			let masquerade = config.ctcpVersionReply?.nonEmpty ?? environment.preferences.masqueradeCTCPVersion?
				.nonEmpty

			return masquerade ?? IRCCTCPStrings.version(
				applicationName: ApplicationInfo.applicationNameWithoutVersion(),
				shortVersion: ApplicationInfo.applicationVersionShort()
			)
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
		let context = IRCCTCPPolicy.formData(text)
		guard let socket, context["connection"] == socket.uniqueIdentifier,
		      let time = context["time"].flatMap(Double.init)
		else { return }
		let delta = (Date().timeIntervalSince1970 - time) * 1000
		let rating = IRCCTCPStrings.lagRating(IRCCTCPLagRating(milliseconds: delta))
		let response = IRCCTCPStrings.lagCheckReply(server: serverAddress ?? "", milliseconds: delta, rating: rating)
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
		guard let parsed = IRCCTCPPolicy.commandAndArguments(from: text) else { return }
		let sender = message.senderNickname ?? ""
		let output: String
		/* Only a PING whose echo comes back as the number that was sent can be
		 timed. An unparsable one used to read as zero — the epoch — and the
		 client reported a lag of fifty-six years rather than saying nothing. */
		if parsed.command == "PING", let echoedTime = Double(parsed.arguments), echoedTime.isFinite {
			let delta = Date().timeIntervalSince1970 - echoedTime
			output = IRCCTCPStrings.timedReply(sender: sender, command: parsed.command, seconds: delta)
		} else {
			output = IRCCTCPStrings.reply(sender: sender, command: parsed.command, arguments: parsed.arguments)
		}
		print(output, by: nil, in: noticePrintTarget(), as: .ctcpReply,
		      command: message.command, receivedAt: message.receivedAt)
	}

	private func noticePrintTarget() -> IRCChannel? {
		guard environment.preferences.locationToSendNotices == .selectedChannel else { return nil }
		return output?.selectedChannel(on: self)
	}
}

private extension String {
	var nonEmpty: String? {
		isEmpty ? nil : self
	}
}
