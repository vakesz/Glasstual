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

nonisolated enum IRCISupportStrings {
	static func everyoneExcept(_ description: String) -> String {
		String(localized: .IRC.everyoneExcept(description))
	}

	static func extendedBanDescription(type: String, argument: String?) -> String {
		guard let argument else {
			return String(localized: .IRC.isupportDrivenMessagesExtendedBanOfType(type))
		}

		guard let kind = IRCExtendedBanKind(rawValue: type) else {
			return String(localized: .IRC.extendedBanOfType(type, argument))
		}

		switch kind {
		case .account: return String(localized: .IRC.usersLoggedInToAccount(argument))
		case .channel: return String(localized: .IRC.usersInChannel(argument))
		case .bannedFromChannel: return String(localized: .IRC.usersBannedFromChannel(argument))
		case .muted: return String(localized: .IRC.isupportDrivenMessagesMuted(argument))
		case .nicknameChangeBlocked: return String(localized: .IRC.nickChangesBlocked(argument))
		case .operatorMask: return String(localized: .IRC.operatorsMatching(argument))
		case .operatorClass: return String(localized: .IRC.operatorsOfClass(argument))
		case .quieted: return String(localized: .IRC.isupportDrivenMessagesQuieted(argument))
		case .realName: return String(localized: .IRC.usersWhoseRealNameMatches(argument))
		case .registeredUser: return String(localized: .IRC.registeredUsersMatching(argument))
		case .server: return String(localized: .IRC.usersConnectedToServer(argument))
		case .securityGroup: return String(localized: .IRC.usersInSecurityGroup(argument))
		case .expiration: return String(localized: .IRC.expiresAfter(argument))
		case .text: return String(localized: .IRC.textMatching(argument))
		case .unregisteredUser: return String(localized: .IRC.unregisteredUsersMatching(argument))
		case .hostmaskAndRealName: return String(localized: .IRC.usersMatchingHostmaskAndRealName(argument))
		case .certificateFingerprint: return String(localized: .IRC.usersWithCertificateFingerprint(argument))
		}
	}

	static func networkName(_ value: String) -> String {
		String(localized: .IRC.ircNetwork(value))
	}

	static func channelLimitExceeded(
		channelName: String,
		limit: UInt,
		prefix: String
	) -> String {
		String(localized: .IRC.joiningWouldExceedTheLimit(channelName, limit, prefix))
	}
}
