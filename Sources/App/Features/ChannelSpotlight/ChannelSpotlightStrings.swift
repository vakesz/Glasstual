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
		String(localized: .TDCChannelSpotlightController.noResults)
	}

	static func channelName(_ channelName: String) -> String {
		String(localized: .TDCChannelSpotlightController.channelName(channelName))
	}

	static func networkSuffix(_ networkName: String) -> String {
		String(localized: .TDCChannelSpotlightController.networkNameSuffixOn(networkName))
	}

	static func unreadMessages(_ count: Int) -> String {
		let countDescription = formattedNumber(count) as String

		if count == 1 {
			return String(localized: .TDCChannelSpotlightController.unreadMessage(countDescription))
		}

		return String(localized: .TDCChannelSpotlightController.unreadMessages(countDescription))
	}

	static func highlights(_ count: Int) -> String {
		let countDescription = formattedNumber(count) as String

		if count == 1 {
			return String(localized: .TDCChannelSpotlightController.singularNicknameHighlightCount(countDescription))
		}

		return String(localized: .TDCChannelSpotlightController
			.pluralNicknameHighlightCountHighlights(countDescription))
	}

	static func combined(_ firstDescription: String, _ secondDescription: String) -> String {
		String(localized: .TDCChannelSpotlightController.joinsTwoChannelStatus(firstDescription, secondDescription))
	}
}
