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

enum PreferencesSectionStrings {
	static var advanced: String {
		String(localized: .TDCPreferencesController.headingAdvanced)
	}

	static var general: String {
		String(localized: .TDCPreferencesController.headingGeneral)
	}
}

enum PreferencesAdvancedStrings {
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

enum PreferencesGeneralStrings {
	static var confirmQuit: String {
		String(localized: .TDCPreferencesController.generalConfirmQuit)
	}
}

enum PreferencesNavigationStrings {
	static var back: String {
		String(localized: .TDCPreferencesController.navigationBack)
	}

	static var forward: String {
		String(localized: .TDCPreferencesController.navigationForward)
	}
}

enum PreferencesBehaviorStrings {
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
}

enum PreferencesIRCv3Strings {
	static var automaticFeatures: String {
		String(localized: .TDCPreferencesController.ircv3AutomaticFeatures)
	}

	static var automaticFeaturesNote: String {
		String(localized: .TDCPreferencesController.ircv3AutomaticFeaturesNote)
	}

	static var connectedServers: String {
		String(localized: .TDCPreferencesController.ircv3ConnectedServers)
	}

	static var disconnected: String {
		String(localized: .TDCPreferencesController.ircv3Disconnected)
	}

	static var displayTypingNotifications: String {
		String(localized: .TDCPreferencesController.ircv3DisplayTypingNotifications)
	}

	static var echoMessage: String {
		String(localized: .TDCPreferencesController.ircv3EchoMessage)
	}

	static var history: String {
		String(localized: .TDCPreferencesController.ircv3History)
	}

	static var historyNote: String {
		String(localized: .TDCPreferencesController.ircv3HistoryNote)
	}

	static var messages: String {
		String(localized: .TDCPreferencesController.ircv3Messages)
	}

	static var noCapabilities: String {
		String(localized: .TDCPreferencesController.ircv3NoCapabilities)
	}

	static var noConnections: String {
		String(localized: .TDCPreferencesController.ircv3NoConnections)
	}

	static var reconnectNote: String {
		String(localized: .TDCPreferencesController.ircv3ReconnectNote)
	}

	static var requestChatHistory: String {
		String(localized: .TDCPreferencesController.ircv3RequestChatHistory)
	}

	static var sendTypingNotifications: String {
		String(localized: .TDCPreferencesController.ircv3SendTypingNotifications)
	}

	static var synchronizeReadMarkers: String {
		String(localized: .TDCPreferencesController.ircv3SynchronizeReadMarkers)
	}
}

enum PreferencesCommandScopeStrings {
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

enum PreferencesChannelManagementStrings {
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
