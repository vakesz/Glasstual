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
		String(localized: .ServerChannelList.channelName)
	}

	static var memberCount: String {
		String(localized: .ServerChannelList.memberCount)
	}

	static var topic: String {
		String(localized: .ServerChannelList.topic)
	}

	static var searchPlaceholder: String {
		String(localized: .ServerChannelList.searchChannels)
	}

	static var channelListAccessibilityLabel: String {
		String(localized: .ServerChannelList.publicChannelList)
	}

	static var joinSelectedChannels: String {
		String(localized: .ServerChannelList.joinSelectedChannels)
	}

	static var refresh: String {
		String(localized: .ServerChannelList.updateList)
	}

	static var requestingChannelList: String {
		String(localized: .ServerChannelList.requestingChannelList)
	}

	static var emptyTitle: String {
		String(localized: .ServerChannelList.noPublicChannels)
	}

	static var emptyDescription: String {
		String(localized: .ServerChannelList.changeTheSearchOrUpdate)
	}

	static var minimumUserCountLabel: String {
		String(localized: .ServerChannelList.minimumUsers)
	}

	static var minimumUserCountFooter: String {
		String(localized: .ServerChannelList.onlyListChannelsWithAtLeast)
	}

	static var windowGroupTitle: String {
		String(localized: .ServerChannelList.windowGroupTitle)
	}

	static var noChannelListTitle: String {
		String(localized: .ServerChannelList.noChannelList)
	}

	static var noChannelListDescription: String {
		String(localized: .ServerChannelList.noChannelListDescription)
	}

	static func truncationNotice(keptChannelCount: Int) -> String {
		String(localized: .ServerChannelList.listTruncatedNotice(keptChannelCount))
	}

	static func windowSubtitle(publicChannelCount: Int) -> String {
		String(localized: .ServerChannelList.publicChannelCount(publicChannelCount))
	}
}
