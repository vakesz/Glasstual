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

enum ChannelAccessListStrings {
	static var hostmask: String {
		String(localized: .TDCChannelBanListSheet.hostmask)
	}

	static var addedBy: String {
		String(localized: .TDCChannelBanListSheet.addedBy)
	}

	static var created: String {
		String(localized: .TDCChannelBanListSheet.created)
	}

	static var accessList: String {
		String(localized: .TDCChannelBanListSheet.accessList)
	}

	static var removeSelected: String {
		String(localized: .TDCChannelBanListSheet.removeSelected)
	}

	static var updateList: String {
		String(localized: .TDCChannelBanListSheet.updateList)
	}

	static var loadingList: String {
		String(localized: .TDCChannelBanListSheet.loadingList)
	}

	static var emptyTitle: String {
		String(localized: .TDCChannelBanListSheet.emptyTitle)
	}

	static var emptyDescription: String {
		String(localized: .TDCChannelBanListSheet.emptyDescription)
	}

	static func heading(for entryType: ChannelBanListEntryType, channelName: String) -> String {
		switch entryType {
		case .ban:
			String(localized: .TDCChannelBanListSheet.headingForTheBanBans(channelName))
		case .banException:
			String(localized: .TDCChannelBanListSheet.banExceptions(channelName))
		case .inviteException:
			String(localized: .TDCChannelBanListSheet.inviteExceptions(channelName))
		case .quiet:
			String(localized: .TDCChannelBanListSheet.headingForTheQuietQuiets(channelName))
		}
	}

	static func entryCount(_ count: Int, maximum: Int) -> String {
		guard maximum > 0 else {
			return String(localized: .TDCChannelBanListSheet.entryCount(count))
		}

		return String(
			localized: .TDCChannelBanListSheet.ofEntries(
				formattedNumber(count) as String,
				formattedNumber(maximum) as String
			)
		)
	}
}
