/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

enum IRCCTCPLagRating: Sendable {
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
}

nonisolated enum IRCCTCPStrings { // nonisolated: value
	static var clientInfoReply: String {
		String(localized: .IRC.clientinfoDccFingerPingTimeUserinfo)
	}

	static var fingerReply: String {
		String(localized: .IRC.stopFingeringMePervert)
	}

	static func ignored(command: String, sender: String) -> String {
		String(localized: .IRC.ctcpFromWasIgnored(command, sender))
	}

	static func query(command: String, sender: String) -> String {
		String(localized: .IRC.miscellaneousMessagesRelatedCtcp(command, sender))
	}

	static func version(applicationName: String, shortVersion: String) -> String {
		String(localized: .IRC.ircClientV(applicationName, shortVersion))
	}

	static func lagRating(_ rating: IRCCTCPLagRating) -> String {
		switch rating {
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

	static func lagCheckReply(server: String, milliseconds: Double, rating: String) -> String {
		String(localized: .IRC.receivedLagCheckReplyFromTime(server, Float(milliseconds), rating))
	}

	static func timedReply(sender: String, command: String, seconds: Double) -> String {
		String(localized: .IRC.ctcpSec(sender, command, Float(seconds)))
	}

	static func reply(sender: String, command: String, arguments: String) -> String {
		String(localized: .IRC.ctcp(sender, command, arguments))
	}
}
