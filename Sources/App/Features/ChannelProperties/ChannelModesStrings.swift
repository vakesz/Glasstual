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
		String(localized: .ChannelProperties.changeModesButton)
	}

	static var channelKeyFieldHint: String {
		String(localized: .ChannelProperties.channelKeyFieldHint)
	}

	static var channelKeyModeTitle: String {
		String(localized: .ChannelProperties.channelKeyMode)
	}

	static var channelKeyPlaceholder: String {
		String(localized: .ChannelProperties.channelKeyPlaceholder)
	}

	static var inviteOnlyModeTitle: String {
		String(localized: .ChannelProperties.inviteOnlyMode)
	}

	static var moderatedModeTitle: String {
		String(localized: .ChannelProperties.moderatedMode)
	}

	static var noExternalMessagesModeTitle: String {
		String(localized: .ChannelProperties.noExternalMessagesMode)
	}

	static var operatorTopicModeTitle: String {
		String(localized: .ChannelProperties.operatorTopicMode)
	}

	static var privateChannelModeTitle: String {
		String(localized: .ChannelProperties.privateChannelMode)
	}

	static var secretChannelModeTitle: String {
		String(localized: .ChannelProperties.secretChannelMode)
	}

	static var userLimitFieldHint: String {
		String(localized: .ChannelProperties.userLimitFieldHint)
	}

	static var userLimitModeTitle: String {
		String(localized: .ChannelProperties.userLimitMode)
	}

	static var userLimitPlaceholder: String {
		String(localized: .ChannelProperties.userLimitPlaceholder)
	}

	static func headingTitle(channelName: String) -> String {
		String(localized: .ChannelProperties.heading(channelName))
	}

	/// The footer under the channel key field, which says how far past the
	/// server's limit the key is; below the limit there is nothing to say.
	static func keyLengthWarning(remaining: Int) -> String? {
		remaining < 0
			? String(localized: .ChannelProperties.channelKeyCharactersOverLimit(arg1: -remaining))
			: nil
	}
}
