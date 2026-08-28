/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

nonisolated enum ChannelAccessListStrings {
	static func heading(for entryType: ChannelBanListEntryType, channelName: String) -> String {
		switch entryType {
		case .ban:
			String(localized: .TDCChannelBanListSheet.rhcKe(channelName))
		case .banException:
			String(localized: .TDCChannelBanListSheet.gbiWn(channelName))
		case .inviteException:
			String(localized: .TDCChannelBanListSheet.ylc6E(channelName))
		case .quiet:
			String(localized: .TDCChannelBanListSheet.g4RT6(channelName))
		}
	}

	static func entryCount(_ count: Int, maximum: Int) -> String {
		let countDescription = formattedNumber(count) as String

		guard maximum > 0 else {
			return String(localized: .TDCChannelBanListSheet.n0FCn(countDescription))
		}

		return String(
			localized: .TDCChannelBanListSheet.n0FMx(
				countDescription,
				formattedNumber(maximum) as String
			)
		)
	}
}
