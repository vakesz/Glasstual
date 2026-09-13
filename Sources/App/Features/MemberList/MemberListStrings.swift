/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
import GlasstualPluginKit

nonisolated enum MemberListStrings { // nonisolated: value
	static var userIsAway: String {
		String(localized: .MemberList.userIsAway)
	}

	static var userIsNotAway: String {
		String(localized: .MemberList.userIsNotAway)
	}

	static var userIsBot: String {
		String(localized: .MemberList.userIsABot)
	}

	/// The badge beside a bot's nickname. A word, not a whisper: it was drawn
	/// lowercase beside names that are not.
	static var botCaption: String {
		String(localized: .MemberList.botCaption)
	}

	/// The row's own catalog: what a pointer reaches by clicking and waiting is
	/// reached here by name instead, and there was no migrated key for it.
	static var showProfileAction: String {
		String(localized: .MemberList.showProfileAction)
	}

	static var informationUnavailable: String {
		String(localized: .MemberList.informationUnavailable)
	}

	static var notLoggedIn: String {
		String(localized: .MemberList.notLoggedIn)
	}

	static func loggedIn(account: String) -> String {
		String(localized: .MemberList.loggedInAs(account))
	}

	/// What the profile's Status row shows. The sentence forms above are what
	/// VoiceOver reads out of a row, where "Away" on its own has nothing to
	/// attach itself to.
	static func awayStatus(isAway: Bool) -> String {
		isAway
			? String(localized: .MemberList.awayStatusAway)
			: String(localized: .MemberList.awayStatusAvailable)
	}

	static func privileges(_ privileges: String, caption: String) -> String {
		String(localized: .MemberList.privilegesWithCaption(privileges, caption))
	}

	static func privilegeDescription(for rank: UserRank) -> String {
		String(localized: MemberListRanks.style(for: rank).privilegeDescription)
	}

	static func sectionTitle(for rank: UserRank) -> String {
		String(localized: MemberListRanks.style(for: rank).sectionTitle)
	}

	enum Info {
		static var username: String {
			String(localized: .MemberList.infoUsername)
		}

		static var address: String {
			String(localized: .MemberList.infoAddress)
		}

		static var realName: String {
			String(localized: .MemberList.infoRealName)
		}

		static var account: String {
			String(localized: .MemberList.infoAccount)
		}

		static var privileges: String {
			String(localized: .MemberList.infoPrivileges)
		}

		static var status: String {
			String(localized: .MemberList.infoStatus)
		}
	}
}
