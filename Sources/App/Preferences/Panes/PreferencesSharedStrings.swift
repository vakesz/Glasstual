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
	static var general: String {
		String(localized: .Settings.headingGeneral)
	}
}

/// Copy shared by the reusable Settings controls rather than owned by a pane.
enum PreferencesFieldStrings {
	static var presetsHelp: String {
		String(localized: .Settings.comboPresetsHelp)
	}

	static var wholeNumberRequired: String {
		String(localized: .PreferencesTransfer.enterAValidWholeNumber)
	}
}

enum PreferencesGeneralStrings {
	static var autojoinOnInvite: String {
		String(localized: .Settings.generalAutojoinOnInvite)
	}

	static var awayOnScreenSleep: String {
		String(localized: .Settings.generalAwayOnScreenSleep)
	}

	static var confirmQuit: String {
		String(localized: .Settings.generalConfirmQuit)
	}

	static var headingChannels: String {
		String(localized: .Settings.generalHeadingChannels)
	}

	static var headingOnLaunch: String {
		String(localized: .Settings.generalHeadingOnLaunch)
	}

	static var rejoinOnKick: String {
		String(localized: .Settings.generalRejoinOnKick)
	}

	static var reloadScrollback: String {
		String(localized: .Settings.generalReloadScrollback)
	}

	static var rememberQueries: String {
		String(localized: .Settings.generalRememberQueries)
	}
}

enum PreferencesIRCv3Strings {
	static var capabilities: String {
		String(localized: .Settings.ircv3Capabilities)
	}

	static var capabilitySpecification: String {
		String(localized: .Settings.ircv3CapabilitySpecification)
	}

	static func capabilityAccessibilityLabel(name: String, summary: String) -> String {
		String(localized: .Settings.ircv3CapabilityAccessibilityLabel(name, summary))
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
		"account-notify": .Settings.ircv3CapabilityAccountNotify,
		"account-tag": .Settings.ircv3CapabilityAccountTag,
		"away-notify": .Settings.ircv3CapabilityAwayNotify,
		"batch": .Settings.ircv3CapabilityBatch,
		"cap-notify": .Settings.ircv3CapabilityCapNotify,
		"chghost": .Settings.ircv3CapabilityChghost,
		"extended-join": .Settings.ircv3CapabilityExtendedJoin,
		"extended-monitor": .Settings.ircv3CapabilityExtendedMonitor,
		"invite-notify": .Settings.ircv3CapabilityInviteNotify,
		"labeled-response": .Settings.ircv3CapabilityLabeledResponse,
		"message-tags": .Settings.ircv3CapabilityMessageTags,
		"multi-prefix": .Settings.ircv3CapabilityMultiPrefix,
		"pre-away": .Settings.ircv3CapabilityPreAway,
		"sasl": .Settings.ircv3CapabilitySasl,
		"server-time": .Settings.ircv3CapabilityServerTime,
		"setname": .Settings.ircv3CapabilitySetname,
		"standard-replies": .Settings.ircv3CapabilityStandardReplies,
		"userhost-in-names": .Settings.ircv3CapabilityUserhostInNames,
		"znc.in/playback": .Settings.ircv3CapabilityZncPlayback,
		"znc.in/self-message": .Settings.ircv3CapabilityZncSelfMessage,
		"znc.in/server-time": .Settings.ircv3CapabilityZncServerTime,
		"znc.in/server-time-iso": .Settings.ircv3CapabilityZncServerTimeIso,
		"znc.in/tlsinfo": .Settings.ircv3CapabilityZncTlsinfo,
	]

	static var connectedServers: String {
		String(localized: .Settings.ircv3ConnectedServers)
	}

	static var disconnected: String {
		String(localized: .Settings.ircv3Disconnected)
	}

	static var displayTypingNotifications: String {
		String(localized: .Settings.ircv3DisplayTypingNotifications)
	}

	static var echoMessage: String {
		String(localized: .Settings.ircv3EchoMessage)
	}

	static var history: String {
		String(localized: .Settings.ircv3History)
	}

	static var historyNote: String {
		String(localized: .Settings.ircv3HistoryNote)
	}

	static var messages: String {
		String(localized: .Settings.ircv3Messages)
	}

	static var noCapabilities: String {
		String(localized: .Settings.ircv3NoCapabilities)
	}

	static var noConnections: String {
		String(localized: .Settings.ircv3NoConnections)
	}

	static var reconnectNote: String {
		String(localized: .Settings.ircv3ReconnectNote)
	}

	static var requestChatHistory: String {
		String(localized: .Settings.ircv3RequestChatHistory)
	}

	static var sendTypingNotifications: String {
		String(localized: .Settings.ircv3SendTypingNotifications)
	}

	static var synchronizeReadMarkers: String {
		String(localized: .Settings.ircv3SynchronizeReadMarkers)
	}
}

enum PreferencesCommandScopeStrings {
	static var amsg: String {
		String(localized: .Settings.commandScopeAmsg)
	}

	static var away: String {
		String(localized: .Settings.commandScopeAway)
	}

	static var clearall: String {
		String(localized: .Settings.commandScopeClearall)
	}

	static var focusOnMessage: String {
		String(localized: .Settings.commandScopeFocusOnMessage)
	}

	static var nick: String {
		String(localized: .Settings.commandScopeNick)
	}

	static var noticeLabel: String {
		String(localized: .Settings.commandScopeNoticeLabel)
	}

	static var noticeQuery: String {
		String(localized: .Settings.commandScopeNoticeQuery)
	}

	static var noticeSelectedChannel: String {
		String(localized: .Settings.commandScopeNoticeSelectedChannel)
	}

	static var noticeServerConsole: String {
		String(localized: .Settings.commandScopeNoticeServerConsole)
	}
}

enum PreferencesChannelManagementStrings {
	static var banFormatExact: String {
		String(localized: .Settings.channelManagementBanFormatExact)
	}

	static var banFormatLabel: String {
		String(localized: .Settings.channelManagementBanFormatLabel)
	}

	static var banFormatNote: String {
		String(localized: .Settings.channelManagementBanFormatNote)
	}

	static var banFormatWhainn: String {
		String(localized: .Settings.channelManagementBanFormatWhainn)
	}

	static var banFormatWhanni: String {
		String(localized: .Settings.channelManagementBanFormatWhanni)
	}

	static var banFormatWhnin: String {
		String(localized: .Settings.channelManagementBanFormatWhnin)
	}

	static var kickReasonLabel: String {
		String(localized: .Settings.channelManagementKickReasonLabel)
	}
}
