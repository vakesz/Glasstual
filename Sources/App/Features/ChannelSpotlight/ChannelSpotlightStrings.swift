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

nonisolated enum ChannelSpotlightStrings {
	static var noResults: String {
		String(localized: .TDCChannelSpotlightController.tyvP6)
	}

	static func channelName(_ channelName: String) -> String {
		String(localized: .TDCChannelSpotlightController.jpwCj(channelName))
	}

	static func networkSuffix(_ networkName: String) -> String {
		String(localized: .TDCChannelSpotlightController.z685Q(networkName))
	}

	static func unreadMessages(_ count: Int) -> String {
		let countDescription = formattedNumber(count) as String

		if count == 1 {
			return String(localized: .TDCChannelSpotlightController._43SX4(countDescription))
		}

		return String(localized: .TDCChannelSpotlightController.vzj30(countDescription))
	}

	static func highlights(_ count: Int) -> String {
		let countDescription = formattedNumber(count) as String

		if count == 1 {
			return String(localized: .TDCChannelSpotlightController._0LzOh(countDescription))
		}

		return String(localized: .TDCChannelSpotlightController.c4U21(countDescription))
	}

	static func combined(_ firstDescription: String, _ secondDescription: String) -> String {
		String(localized: .TDCChannelSpotlightController.et7C5(firstDescription, secondDescription))
	}
}
