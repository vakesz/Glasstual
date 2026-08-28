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

nonisolated enum AccessibilityStrings {
	static func joinedChannel(_ channelName: String) -> String {
		String(localized: .Accessibility.channelJoined(channelName))
	}

	static func unjoinedChannel(_ channelName: String) -> String {
		String(localized: .Accessibility.channelNotJoined(channelName))
	}

	static func connectedServer(_ connectionName: String) -> String {
		String(localized: .Accessibility.connectionConnected(connectionName))
	}

	static func disconnectedServer(_ connectionName: String) -> String {
		String(localized: .Accessibility.connectionDisconnected(connectionName))
	}

	static var errorIcon: String {
		String(localized: .Accessibility.errorIcon)
	}

	static var mainWindow: String {
		String(localized: .Accessibility.mainWindow)
	}

	static func privateMessageQuery(with nickname: String) -> String {
		String(localized: .Accessibility.queryWithUser(nickname))
	}

	static func userListEntry(for nickname: String) -> String {
		String(localized: .Accessibility.userInUserList(nickname))
	}
}
