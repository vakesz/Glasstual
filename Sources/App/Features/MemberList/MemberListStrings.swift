/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
import GlasstualPluginKit

nonisolated enum MemberListStrings { // nonisolated: value
	static var userIsAway: String {
		String(localized: .TVCMainWindow.userIsAway)
	}

	static var userIsNotAway: String {
		String(localized: .TVCMainWindow.userIsNotAway)
	}

	static var userIsBot: String {
		String(localized: .TVCMainWindow.userIsABot)
	}

	static var botCaption: String {
		String(localized: .TVCMainWindow.memberListCaptionShownBot)
	}

	static var informationUnavailable: String {
		String(localized: .TVCMainWindow.informationNotAvailable)
	}

	static var notLoggedIn: String {
		String(localized: .TVCMainWindow.notLogged)
	}

	static func loggedIn(account: String) -> String {
		String(localized: .TVCMainWindow.memberAccountStatusDescriptionLogged(account))
	}

	static func privilegeDescription(for rank: UserRank) -> String {
		switch rank {
		case .irCopByMode:
			String(localized: .TVCMainWindow.serverStaffMemberIrcOperator)
		case .channelOwner:
			String(localized: .TVCMainWindow.channelOwner)
		case .superOperator:
			String(localized: .TVCMainWindow.superAdmin)
		case .normalOperator:
			String(localized: .TVCMainWindow.memberPrivilegeDescriptionOperator)
		case .halfOperator:
			String(localized: .TVCMainWindow.halfOp)
		case .voiced:
			String(localized: .TVCMainWindow.memberPrivilegeDescriptionVoice)
		default:
			String(localized: .TVCMainWindow.noPrivileges)
		}
	}

	static func sectionTitle(for rank: UserRank) -> String {
		switch rank {
		case .irCopByMode:
			String(localized: .TVCMainWindow.serverStaff)
		case .channelOwner:
			String(localized: .TVCMainWindow.memberListSectionHeadersOwners)
		case .superOperator:
			String(localized: .TVCMainWindow.memberListSectionHeadersAdmins)
		case .normalOperator:
			String(localized: .TVCMainWindow.memberListSectionHeadersOperators)
		case .halfOperator:
			String(localized: .TVCMainWindow.halfOperators)
		case .voiced:
			String(localized: .TVCMainWindow.memberListSectionHeadersVoiced)
		default:
			String(localized: .TVCMainWindow.memberListSectionHeadersMembers)
		}
	}

	enum Info {
		static var username: String {
			String(localized: .TVCMainWindow.memberUsername)
		}

		static var address: String {
			String(localized: .TVCMainWindow.memberAddress)
		}

		static var realName: String {
			String(localized: .TVCMainWindow.memberRealName)
		}

		static var account: String {
			String(localized: .TVCMainWindow.memberAccount)
		}

		static var privileges: String {
			String(localized: .TVCMainWindow.memberPrivileges)
		}

		static var status: String {
			String(localized: .TVCMainWindow.memberStatus)
		}
	}
}
