// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The kinds of extended ban an `EXTBAN`-advertising server accepts.

 Each letter bans by something other than a hostmask, and the letters are the
 ones the convention settled on rather than anything ISUPPORT enumerates. */
enum ExtendedBanKind: String {
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

	/** How a mask on an extended-ban list reads.

	 A type the session does not know still prints: the server named it, and the
	 list is the user's to read whatever this build understands. */
	static func describing(type: String, argument: String?) -> String {
		guard let argument else {
			return String(localized: .IRC.isupportDrivenMessagesExtendedBanOfType(type))
		}

		guard let kind = ExtendedBanKind(rawValue: type) else {
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
}
