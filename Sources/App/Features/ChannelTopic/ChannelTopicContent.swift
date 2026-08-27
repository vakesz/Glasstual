/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

struct ChannelTopicContent: Equatable, Sendable {
	let headerTitle: String
	let editorAccessibilityHint: String
	let changeButtonTitle: String
	let cancelButtonTitle: String
	let windowTitle: String

	static func current(channelName: String) -> Self {
		Self(
			headerTitle: ChannelTopicStrings.headerTitle(channelName: channelName),
			editorAccessibilityHint: ChannelTopicStrings.editorAccessibilityHint,
			changeButtonTitle: ChannelTopicStrings.changeButtonTitle,
			cancelButtonTitle: ChannelTopicStrings.cancelButtonTitle,
			windowTitle: ChannelTopicStrings.windowTitle
		)
	}
}
