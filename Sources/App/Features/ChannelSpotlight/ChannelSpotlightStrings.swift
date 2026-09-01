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

nonisolated enum ChannelSpotlightStrings { // nonisolated: value
	static var accessibilityTitle: String {
		String(localized: .TDCChannelSpotlightController.accessibilityTitle)
	}

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
		String(localized: .TDCChannelSpotlightController.unreadMessageCount(count))
	}

	static func highlights(_ count: Int) -> String {
		String(localized: .TDCChannelSpotlightController.highlightCount(count))
	}

	static func combined(_ firstDescription: String, _ secondDescription: String) -> String {
		String(localized: .TDCChannelSpotlightController.joinsTwoChannelStatus(firstDescription, secondDescription))
	}

	static var resultsAccessibilityLabel: String {
		String(localized: .TDCChannelSpotlightController.resultsAccessibilityLabel)
	}

	static var searchPlaceholder: String {
		String(localized: .TDCChannelSpotlightController.searchPlaceholder)
	}
}
