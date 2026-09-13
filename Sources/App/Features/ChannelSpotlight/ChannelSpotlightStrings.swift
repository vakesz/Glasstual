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
	static var windowTitle: String {
		String(localized: .ChannelSpotlight.windowTitle)
	}

	static var noResults: String {
		String(localized: .ChannelSpotlight.noResults)
	}

	static func channelOnNetwork(_ channelName: String, _ networkName: String) -> String {
		String(localized: .ChannelSpotlight.channelOnNetwork(channelName, networkName))
	}

	static func unreadMessages(_ count: Int) -> String {
		String(localized: .ChannelSpotlight.unreadMessageCount(count))
	}

	static func highlights(_ count: Int) -> String {
		String(localized: .ChannelSpotlight.highlightCount(count))
	}

	static func combined(_ firstDescription: String, _ secondDescription: String) -> String {
		String(localized: .ChannelSpotlight.joinsTwoChannelStatus(firstDescription, secondDescription))
	}

	static var resultsAccessibilityLabel: String {
		String(localized: .ChannelSpotlight.resultsAccessibilityLabel)
	}

	static var searchPlaceholder: String {
		String(localized: .ChannelSpotlight.searchPlaceholder)
	}
}
