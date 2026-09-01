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

enum ServerChannelListStrings {
	static var channelName: String {
		String(localized: .TDCServerChannelListDialog.channelName)
	}

	static var memberCount: String {
		String(localized: .TDCServerChannelListDialog.memberCount)
	}

	static var topic: String {
		String(localized: .TDCServerChannelListDialog.topic)
	}

	static var searchPlaceholder: String {
		String(localized: .TDCServerChannelListDialog.searchChannels)
	}

	static var searchAccessibilityLabel: String {
		String(localized: .TDCServerChannelListDialog.channelListSearch)
	}

	static var channelListAccessibilityLabel: String {
		String(localized: .TDCServerChannelListDialog.publicChannelList)
	}

	static var joinSelectedChannels: String {
		String(localized: .TDCServerChannelListDialog.joinSelectedChannels)
	}

	static var updateList: String {
		String(localized: .TDCServerChannelListDialog.updateList)
	}

	static var requestingChannelList: String {
		String(localized: .TDCServerChannelListDialog.requestingChannelList)
	}

	static var emptyTitle: String {
		String(localized: .TDCServerChannelListDialog.noPublicChannels)
	}

	static var emptyDescription: String {
		String(localized: .TDCServerChannelListDialog.changeTheSearchOrUpdate)
	}

	static var minimumUserCountLabel: String {
		String(localized: .TDCServerChannelListDialog.minimumUsers)
	}

	static var minimumUserCountHint: String {
		String(localized: .TDCServerChannelListDialog.onlyListChannelsWithAtLeast)
	}

	static func heading(networkName: String) -> String {
		String(localized: .TDCServerChannelListDialog.channelList(networkName))
	}

	static func windowTitle(publicChannelCount: Int) -> String {
		String(localized: .TDCServerChannelListDialog.publicChannelCount(publicChannelCount))
	}
}
