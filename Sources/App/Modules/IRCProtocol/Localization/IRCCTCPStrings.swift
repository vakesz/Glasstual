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

nonisolated enum IRCCTCPStrings {
	static var clientInfoReply: String {
		String(localized: .IRC.jerJu)
	}

	static var fingerReply: String {
		String(localized: .IRC.en6Mw)
	}

	static func ignored(command: String, sender: String) -> String {
		String(localized: .IRC.bg3H2(command, sender))
	}

	static func query(command: String, sender: String) -> String {
		String(localized: .IRC._6O8Eu(command, sender))
	}

	static func version(applicationName: String, shortVersion: String) -> String {
		String(localized: .IRC.vzuU7(applicationName, shortVersion))
	}

	static func lagRating(_ rating: IRCCTCPLagRating) -> String {
		switch rating {
		case .excellent: String(localized: .IRC._58GM9)
		case .suspiciouslyFast: String(localized: .IRC._0Jp93)
		case .veryGood: String(localized: .IRC.yym8Y)
		case .good: String(localized: .IRC.micQe)
		case .acceptable: String(localized: .IRC.mqgWi)
		case .needsWork: String(localized: .IRC.ut87S)
		case .slow: String(localized: .IRC._8FoSs)
		case .verySlow: String(localized: .IRC._4OcP2)
		}
	}

	static func lagCheckReply(server: String, milliseconds: Double, rating: String) -> String {
		String(localized: .IRC._5BfJp(server, Float(milliseconds), rating))
	}

	static func timedReply(sender: String, command: String, seconds: Double) -> String {
		String(localized: .IRC.vy7Pk(sender, command, Float(seconds)))
	}

	static func reply(sender: String, command: String, arguments: String) -> String {
		String(localized: .IRC.driL7(sender, command, arguments))
	}
}
