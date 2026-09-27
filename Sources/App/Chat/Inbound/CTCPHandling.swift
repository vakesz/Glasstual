// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private let ctcpLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "CTCP"
)

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

	/// How this rating reads in the `/mylag` reply the user sends back to the
	/// conversation.
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

@MainActor
extension ServerSession {
	func receiveCTCPQuery(_ message: Message, text: String) {
		let sender = message.senderNickname ?? ""
		let isLocalUser = nicknameIsMyself(sender)
		let ignore = isLocalUser ? nil : message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))
		guard let parsed = CTCPPolicy.commandAndArguments(from: text) else { return }

		/* A lag check is a query the session sends itself, so with echo-message
		 the copy that comes back is the only one there is. It has to be read
		 before echoes of queries sent to other people are set aside. */
		if parsed.verb == .lagCheck {
			receiveCTCPLagCheckQuery(message, text: parsed.arguments)
			return
		}
		if isLocalUser, isCapabilityEnabled(.echoMessage) {
			return
		}
		if ignore?.ignoreClientToClientProtocol == true {
			return
		}
		guard environment.settings.replyToCTCPRequests else {
			printDebugInformation(toConsole: String(localized: .IRC.ctcpFromWasIgnored(parsed.rawCommand, sender)))
			return
		}
		if parsed.verb == .dcc {
			receivedDCCQuery(message, text: parsed.arguments, ignoreInfo: ignore)
			return
		}

		let printTarget = noticePrintTarget()
		print(String(localized: .IRC.miscellaneousMessagesRelatedCtcp(parsed.rawCommand, sender)), by: nil, in: printTarget, as: .ctcpQuery,
		      command: message.command, receivedAt: message.receivedAt)

		guard let replyText = ctcpReplyText(for: parsed.verb, arguments: parsed.arguments) else {
			return
		}

		/* The query is still printed — it is the user's record of the flood —
		 but answering every one of them is what gets the connection killed for
		 excess flood. The throttle is consulted only once there is an answer to
		 send, so a burst of commands this session does not implement cannot spend
		 the allowance a real query needs. */
		guard allowsCTCPReply(to: sender) else {
			ctcpLogger.notice("Throttled a CTCP reply")
			return
		}

		sendCTCPReply(sender, command: parsed.rawCommand, text: replyText)
	}

	/// What this session answers `command` with, or `nil` when it answers nothing.
	private func ctcpReplyText(for command: CTCPVerb?, arguments: String) -> String? {
		switch command {
		case .clientInfo:
			return String(localized: .IRC.clientinfoDccFingerPingTimeUserinfo)
		case .finger:
			return String(localized: .IRC.stopFingeringMePervert)
		case .ping:
			guard arguments.utf8.count <= 50 else {
				ctcpLogger.fault("Ignoring PING query that exceeds 50 bytes")
				return nil
			}

			return arguments
		case .time:
			return DateFormatting.iso8601String(from: Date())
		case .userInfo:
			return config.realName
		case .version:
			let masquerade = config.ctcpVersionReply?.nonEmpty ?? environment.settings.masqueradeCTCPVersion?
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
		// "channel" is the field name the lag-check CTCP payload carries; what it
		// holds is whichever conversation `/mylag` was run in.
		if let conversationName = context["channel"], let conversation = findConversation(conversationName) {
			sendPrivmsg(response, to: conversation)
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
		 session reported a lag of fifty-six years rather than saying nothing. */
		if parsed.verb == .ping, let echoedTime = Double(parsed.arguments), echoedTime.isFinite {
			let delta = Date().timeIntervalSince1970 - echoedTime
			output = String(localized: .IRC.ctcpSec(sender, parsed.rawCommand, Float(delta)))
		} else {
			output = String(localized: .IRC.ctcp(sender, parsed.rawCommand, parsed.arguments))
		}
		print(output, by: nil, in: noticePrintTarget(), as: .ctcpReply,
		      command: message.command, receivedAt: message.receivedAt)
	}

	private func noticePrintTarget() -> Conversation? {
		guard environment.settings.locationToSendNotices == .selectedConversation else { return nil }
		return output?.selectedConversation(on: self)
	}
}
