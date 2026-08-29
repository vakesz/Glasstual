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

nonisolated enum ChannelAccessListStrings { // nonisolated: value
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
