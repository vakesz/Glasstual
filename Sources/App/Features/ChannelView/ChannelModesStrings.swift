/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

nonisolated enum ChannelModesStrings { // nonisolated: value
	static var channelKeyFieldHint: String {
		String(localized: .TDCChannelModifyModesSheet.channelKeyFieldHint)
	}

	static var channelKeyModeTitle: String {
		String(localized: .TDCChannelModifyModesSheet.channelKeyMode)
	}

	static var inviteOnlyModeTitle: String {
		String(localized: .TDCChannelModifyModesSheet.inviteOnlyMode)
	}

	static var moderatedModeTitle: String {
		String(localized: .TDCChannelModifyModesSheet.moderatedMode)
	}

	static var noExternalMessagesModeTitle: String {
		String(localized: .TDCChannelModifyModesSheet.noExternalMessagesMode)
	}

	static var operatorTopicModeTitle: String {
		String(localized: .TDCChannelModifyModesSheet.operatorTopicMode)
	}

	static var privateChannelModeTitle: String {
		String(localized: .TDCChannelModifyModesSheet.privateChannelMode)
	}

	static var secretChannelModeTitle: String {
		String(localized: .TDCChannelModifyModesSheet.secretChannelMode)
	}

	static var userLimitFieldHint: String {
		String(localized: .TDCChannelModifyModesSheet.userLimitFieldHint)
	}

	static var userLimitModeTitle: String {
		String(localized: .TDCChannelModifyModesSheet.userLimitMode)
	}

	static var windowTitle: String {
		String(localized: .TDCChannelModifyModesSheet.windowTitle)
	}

	static func headingTitle(channelName: String) -> String {
		String(localized: .TDCChannelModifyModesSheet.heading(channelName))
	}
}
