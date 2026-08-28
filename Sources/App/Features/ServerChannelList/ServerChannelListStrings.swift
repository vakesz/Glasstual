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

nonisolated enum ServerChannelListStrings {
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
