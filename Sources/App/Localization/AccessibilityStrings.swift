// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated enum AccessibilityStrings {
	static func joinedChannel(_ channelName: String) -> String {
		String(localized: .Accessibility.channelJoined(channelName))
	}

	static func unjoinedChannel(_ channelName: String) -> String {
		String(localized: .Accessibility.channelNotJoined(channelName))
	}

	static var showFullTopic: String {
		String(localized: .Accessibility.topicShowFull)
	}

	static var showLessTopic: String {
		String(localized: .Accessibility.topicShowLess)
	}

	static func connectedServer(_ connectionName: String) -> String {
		String(localized: .Accessibility.connectionConnected(connectionName))
	}

	static func disconnectedServer(_ connectionName: String) -> String {
		String(localized: .Accessibility.connectionDisconnected(connectionName))
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
