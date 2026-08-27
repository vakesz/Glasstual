/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

private enum IRCExtendedBanKind: String {
	case account = "a"
	case channel = "c"
	case bannedFromChannel = "j"
	case muted = "m"
	case nicknameChangeBlocked = "n"
	case operatorMask = "o"
	case operatorClass = "O"
	case quieted = "q"
	case realName = "r"
	case registeredUser = "R"
	case server = "s"
	case securityGroup = "S"
	case expiration = "t"
	case text = "T"
	case unregisteredUser = "U"
	case hostmaskAndRealName = "x"
	case certificateFingerprint = "z"
}

enum IRCISupportStrings {
	static func everyoneExcept(_ description: String) -> String {
		String(localized: .IRC._6KqXb(description))
	}

	static func extendedBanDescription(type: String, argument: String?) -> String {
		guard let argument else {
			return String(localized: .IRC._2NbKl(type))
		}

		guard let kind = IRCExtendedBanKind(rawValue: type) else {
			return String(localized: .IRC._2NbKk(type, argument))
		}

		switch kind {
		case .account: return String(localized: .IRC._2NbKa(argument))
		case .channel: return String(localized: .IRC._2NbKc(argument))
		case .bannedFromChannel: return String(localized: .IRC._2NbKj(argument))
		case .muted: return String(localized: .IRC._2NbKm(argument))
		case .nicknameChangeBlocked: return String(localized: .IRC._2NbKn(argument))
		case .operatorMask: return String(localized: .IRC._2NbKo(argument))
		case .operatorClass: return String(localized: .IRC._2NbKo2(argument))
		case .quieted: return String(localized: .IRC._2NbKq(argument))
		case .realName: return String(localized: .IRC._2NbKr(argument))
		case .registeredUser: return String(localized: .IRC._2NbKr2(argument))
		case .server: return String(localized: .IRC._2NbKs(argument))
		case .securityGroup: return String(localized: .IRC._2NbKs2(argument))
		case .expiration: return String(localized: .IRC._2NbKt(argument))
		case .text: return String(localized: .IRC._2NbKt2(argument))
		case .unregisteredUser: return String(localized: .IRC._2NbKu(argument))
		case .hostmaskAndRealName: return String(localized: .IRC._2NbKx(argument))
		case .certificateFingerprint: return String(localized: .IRC._2NbKz(argument))
		}
	}

	static func networkName(_ value: String) -> String {
		String(localized: .IRC._8Hg7K(value))
	}

	static func channelLimitExceeded(
		channelName: String,
		limit: UInt,
		prefix: String
	) -> String {
		String(localized: .IRC.w7CLm(channelName, limit, prefix))
	}
}
