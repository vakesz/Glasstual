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
	static var cancelButtonTitle: String {
		PromptStrings.Action.cancel
	}

	static var changeModesButtonTitle: String {
		String(localized: .TDCChannelModifyModesSheet.changeModesButton)
	}

	static var channelKeyFieldHint: String {
		String(localized: .TDCChannelModifyModesSheet.channelKeyFieldHint)
	}

	static var channelKeyModeTitle: String {
		String(localized: .TDCChannelModifyModesSheet.channelKeyMode)
	}

	static var channelKeyPlaceholder: String {
		String(localized: .TDCChannelModifyModesSheet.channelKeyPlaceholder)
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

	static var userLimitPlaceholder: String {
		String(localized: .TDCChannelModifyModesSheet.userLimitPlaceholder)
	}

	static func headingTitle(channelName: String) -> String {
		String(localized: .TDCChannelModifyModesSheet.heading(channelName))
	}

	/// The footer under the channel key field, which says how far past the
	/// server's limit the key is; below the limit there is nothing to say.
	static func keyLengthWarning(remaining: Int) -> String? {
		remaining < 0
			? String(localized: .TDCChannelModifyModesSheet.channelKeyCharactersOverLimit(arg1: -remaining))
			: nil
	}
}
