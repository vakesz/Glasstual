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

nonisolated enum PreferencesSectionStrings {
	static var advanced: String {
		String(localized: .TDCPreferencesController.headingAdvanced)
	}

	static var general: String {
		String(localized: .TDCPreferencesController.headingGeneral)
	}
}

nonisolated enum PreferencesAdvancedStrings {
	static var channels: String {
		String(localized: .TDCPreferencesController.advancedChannels)
	}

	static var connection: String {
		String(localized: .TDCPreferencesController.advancedConnection)
	}

	static var identity: String {
		String(localized: .TDCPreferencesController.advancedIdentity)
	}

	static var media: String {
		String(localized: .TDCPreferencesController.advancedMedia)
	}

	static var system: String {
		String(localized: .TDCPreferencesController.advancedSystem)
	}
}

nonisolated enum PreferencesGeneralStrings {
	static var confirmQuit: String {
		String(localized: .TDCPreferencesController.generalConfirmQuit)
	}
}

nonisolated enum PreferencesBehaviorStrings {
	static var autojoinOnInvite: String {
		String(localized: .TDCPreferencesController.behaviorAutojoinOnInvite)
	}

	static var awayOnScreenSleep: String {
		String(localized: .TDCPreferencesController.behaviorAwayOnScreenSleep)
	}

	static var openLinksInBackground: String {
		String(localized: .TDCPreferencesController.behaviorOpenLinksInBackground)
	}

	static var rejoinOnKick: String {
		String(localized: .TDCPreferencesController.behaviorRejoinOnKick)
	}

	static var reloadScrollback: String {
		String(localized: .TDCPreferencesController.behaviorReloadScrollback)
	}

	static var rememberQueries: String {
		String(localized: .TDCPreferencesController.behaviorRememberQueries)
	}

	static var sendTypingNotifications: String {
		String(localized: .TDCPreferencesController.behaviorSendTypingNotifications)
	}

	static var typingNotificationsNote: String {
		String(localized: .TDCPreferencesController.behaviorTypingNotificationsNote)
	}
}

nonisolated enum PreferencesCompatibilityStrings {
	static var echoMessage: String {
		String(localized: .TDCPreferencesController.compatibilityEchoMessage)
	}
}

nonisolated enum PreferencesCommandScopeStrings {
	static var amsg: String {
		String(localized: .TDCPreferencesController.commandScopeAmsg)
	}

	static var away: String {
		String(localized: .TDCPreferencesController.commandScopeAway)
	}

	static var clearall: String {
		String(localized: .TDCPreferencesController.commandScopeClearall)
	}

	static var focusOnMessage: String {
		String(localized: .TDCPreferencesController.commandScopeFocusOnMessage)
	}

	static var nick: String {
		String(localized: .TDCPreferencesController.commandScopeNick)
	}

	static var noticeLabel: String {
		String(localized: .TDCPreferencesController.commandScopeNoticeLabel)
	}

	static var noticeQuery: String {
		String(localized: .TDCPreferencesController.commandScopeNoticeQuery)
	}

	static var noticeSelectedChannel: String {
		String(localized: .TDCPreferencesController.commandScopeNoticeSelectedChannel)
	}

	static var noticeServerConsole: String {
		String(localized: .TDCPreferencesController.commandScopeNoticeServerConsole)
	}
}

nonisolated enum PreferencesChannelManagementStrings {
	static var banFormatExact: String {
		String(localized: .TDCPreferencesController.channelManagementBanFormatExact)
	}

	static var banFormatLabel: String {
		String(localized: .TDCPreferencesController.channelManagementBanFormatLabel)
	}

	static var banFormatNote: String {
		String(localized: .TDCPreferencesController.channelManagementBanFormatNote)
	}

	static var banFormatWhainn: String {
		String(localized: .TDCPreferencesController.channelManagementBanFormatWhainn)
	}

	static var banFormatWhanni: String {
		String(localized: .TDCPreferencesController.channelManagementBanFormatWhanni)
	}

	static var banFormatWhnin: String {
		String(localized: .TDCPreferencesController.channelManagementBanFormatWhnin)
	}

	static var kickReasonLabel: String {
		String(localized: .TDCPreferencesController.channelManagementKickReasonLabel)
	}
}
