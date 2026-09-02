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
	static var capabilities: String {
		String(localized: .TDCPreferencesController.ircv3Capabilities)
	}

	static var capabilitySpecification: String {
		String(localized: .TDCPreferencesController.ircv3CapabilitySpecification)
	}

	static func capabilityAccessibilityLabel(name: String, summary: String) -> String {
		String(localized: .TDCPreferencesController.ircv3CapabilityAccessibilityLabel(name, summary))
	}

	/** What a capability does, in one sentence, for the switch that turns it
	 off. Keyed by the wire name the registry declares, because that name is
	 what the pane shows and what the disabled list stores.

	 A capability with no entry here has no summary to show rather than an
	 English fallback in a translated interface. */
	static func capabilitySummary(for name: String) -> String? {
		capabilitySummaries[name].map { String(localized: $0) }
	}

	private static let capabilitySummaries: [String: LocalizedStringResource] = [
		"account-notify": .TDCPreferencesController.ircv3CapabilityAccountNotify,
		"account-tag": .TDCPreferencesController.ircv3CapabilityAccountTag,
		"away-notify": .TDCPreferencesController.ircv3CapabilityAwayNotify,
		"batch": .TDCPreferencesController.ircv3CapabilityBatch,
		"cap-notify": .TDCPreferencesController.ircv3CapabilityCapNotify,
		"chghost": .TDCPreferencesController.ircv3CapabilityChghost,
		"extended-join": .TDCPreferencesController.ircv3CapabilityExtendedJoin,
		"extended-monitor": .TDCPreferencesController.ircv3CapabilityExtendedMonitor,
		"invite-notify": .TDCPreferencesController.ircv3CapabilityInviteNotify,
		"labeled-response": .TDCPreferencesController.ircv3CapabilityLabeledResponse,
		"message-tags": .TDCPreferencesController.ircv3CapabilityMessageTags,
		"multi-prefix": .TDCPreferencesController.ircv3CapabilityMultiPrefix,
		"pre-away": .TDCPreferencesController.ircv3CapabilityPreAway,
		"sasl": .TDCPreferencesController.ircv3CapabilitySasl,
		"server-time": .TDCPreferencesController.ircv3CapabilityServerTime,
		"setname": .TDCPreferencesController.ircv3CapabilitySetname,
		"standard-replies": .TDCPreferencesController.ircv3CapabilityStandardReplies,
		"userhost-in-names": .TDCPreferencesController.ircv3CapabilityUserhostInNames,
		"znc.in/playback": .TDCPreferencesController.ircv3CapabilityZncPlayback,
		"znc.in/self-message": .TDCPreferencesController.ircv3CapabilityZncSelfMessage,
		"znc.in/server-time": .TDCPreferencesController.ircv3CapabilityZncServerTime,
		"znc.in/server-time-iso": .TDCPreferencesController.ircv3CapabilityZncServerTimeIso,
		"znc.in/tlsinfo": .TDCPreferencesController.ircv3CapabilityZncTlsinfo,
	]

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
