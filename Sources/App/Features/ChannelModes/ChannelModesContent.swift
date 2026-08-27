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

struct ChannelModesContent: Equatable, Sendable {
	let headingTitle: String
	let channelKeyFieldHint: String
	let userLimitFieldHint: String
	let saveButtonTitle: String
	let cancelButtonTitle: String
	let windowTitle: String

	static func current(channelName: String) -> Self {
		Self(
			headingTitle: ChannelModesStrings.headingTitle(channelName: channelName),
			channelKeyFieldHint: ChannelModesStrings.channelKeyFieldHint,
			userLimitFieldHint: ChannelModesStrings.userLimitFieldHint,
			saveButtonTitle: PromptStrings.Action.save,
			cancelButtonTitle: PromptStrings.Action.cancel,
			windowTitle: ChannelModesStrings.windowTitle
		)
	}

	func title(for mode: ChannelMode) -> String {
		switch mode {
		case .inviteOnly:
			ChannelModesStrings.inviteOnlyModeTitle
		case .moderated:
			ChannelModesStrings.moderatedModeTitle
		case .noExternalMessages:
			ChannelModesStrings.noExternalMessagesModeTitle
		case .privateChannel:
			ChannelModesStrings.privateChannelModeTitle
		case .secretChannel:
			ChannelModesStrings.secretChannelModeTitle
		case .operatorTopic:
			ChannelModesStrings.operatorTopicModeTitle
		case .key:
			ChannelModesStrings.channelKeyModeTitle
		case .userLimit:
			ChannelModesStrings.userLimitModeTitle
		}
	}
}
