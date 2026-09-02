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

/** Which typed keys each pane binds to.

 The panes read and write through these declarations, and this list is what
 `PreferencesPaneInventoryTests` checks against the catalogue: a key a pane
 binds to that the catalogue does not know is a setting that would never be
 exported, imported or registered. */
enum PreferencesPaneKeys {
	static let keysByPane: [PreferencesPaneIdentifier: [any AnyPreferenceKey]] = [
		.general: [Preferences.Connection.confirmQuit],
		.behavior: [
			Preferences.Messages.openBrowserInBackground,
			Preferences.Connection.rejoinOnKick,
			Preferences.Connection.autojoinOnInvite,
			Preferences.Connection.awayOnScreenSleep,
			Preferences.Logging.reloadScrollbackOnLaunch,
			Preferences.Appearance.rememberQueryStates,
		],
		.ircv3: [
			Preferences.Connection.displayTypingNotifications,
			Preferences.Connection.sendTypingNotifications,
			Preferences.Connection.echoMessageCapability,
			Preferences.Connection.requestChatHistory,
			Preferences.Connection.synchronizeReadMarkers,
			Preferences.Connection.disabledCapabilities,
		],
		.notifications: [
			Preferences.Notifications.onlySpeakForSelection,
			Preferences.Notifications.flag(.channelMessage, .speakChannelName),
			Preferences.Notifications.flag(.channelMessage, .speakNickname),
			Preferences.Notifications.displayDockBadge,
			Preferences.Notifications.publicMessageCountOnDockBadge,
			Preferences.Notifications.postWhileInFocus,
		],
		.highlights: [
			Preferences.Highlights.matchingMethod,
			Preferences.Logging.logHighlights,
			Preferences.Highlights.trackLocalNickname,
			Preferences.Highlights.matchKeywords,
			Preferences.Highlights.excludeKeywords,
		],
		.interface: [
			Preferences.Messages.rightToLeftFormatting,
			Preferences.Appearance.preferredAppearance,
			Preferences.Appearance.memberListNoModeSymbol,
			Preferences.Appearance.memberListSortFavorsServerStaff,
			Preferences.Appearance.memberListUpdatesPopoverOnScroll,
			Preferences.Badges.serverListUnreadHighlight,
		] + Preferences.Badges.userListMode,
		.style: [
			Preferences.Theme.transcriptTheme,
			Preferences.Messages.autoAddScrollbackMark,
			Preferences.Messages.showDateChanges,
			Preferences.Messages.showJoinLeave,
			Preferences.Messages.showInlineMedia,
			Preferences.Logging.scrollbackSaveLimit,
			Preferences.Messages.disableNicknameColorHashing,
			Preferences.Appearance.conversationTrackingIncludesModeSymbol,
			Preferences.Connection.displayServerMOTD,
		],
		.controls: [
			Preferences.Appearance.channelNavigationIsServerSpecific,
			Preferences.Input.userDoubleClickAction,
			Preferences.Input.commandWKeyAction,
			Preferences.Appearance.connectOnDoubleClick,
			Preferences.Appearance.disconnectOnDoubleClick,
			Preferences.Appearance.joinOnDoubleClick,
			Preferences.Appearance.leaveOnDoubleClick,
			Preferences.Messages.copyOnSelect,
			Preferences.Input.automaticSpellCheck,
			Preferences.Input.automaticGrammarCheck,
			Preferences.Input.automaticSpellCorrection,
			Preferences.Input.historyIsChannelSpecific,
			Preferences.Input.commandReturnSendsAction,
			Preferences.Input.controlEnterSendsMessage,
			Preferences.Input.textViewFontSize,
			Preferences.Input.tabKeyAction,
			Preferences.Input.tabCompletionSuffix,
		],
		// The pane lists what the plugin manager reports; it binds nothing.
		.addOns: [],
		.channelManagement: [
			Preferences.Commands.banFormat,
			Preferences.Commands.kickMessage,
		],
		.commandScope: [
			Preferences.Commands.amsgAllConnections,
			Preferences.Commands.awayAllConnections,
			Preferences.Commands.nickAllConnections,
			Preferences.Commands.clearAllConnections,
			Preferences.Commands.giveFocusOnMessageCommand,
			Preferences.Commands.noticeDestination,
		],
		.floodControl: [
			Preferences.Connection.autojoinDelayAfterIdentification,
			Preferences.Appearance.trackUserAwayStatusMaximumChannelSize,
		],
		.incomingData: [
			Preferences.Messages.replyToCTCPRequests,
			Preferences.Messages.detectHighlightSpam,
			Preferences.Messages.removeAllFormatting,
			Preferences.Messages.filterUnicodeTextSpam,
		],
		.fileTransfers: [
			Preferences.FileTransfers.requestReplyAction,
			Preferences.FileTransfers.ipAddressDetectionMethod,
			Preferences.FileTransfers.manuallyEnteredIPAddress,
			Preferences.FileTransfers.portRangeStart,
			Preferences.FileTransfers.portRangeEnd,
			Preferences.FileTransfers.requestsAreReversed,
			Preferences.FileTransfers.preventIdleSystemSleep,
		],
		.logLocation: [Preferences.Logging.logToDisk],
		.defaultIdentity: [
			Preferences.Identity.nickname,
			Preferences.Identity.awayNickname,
			Preferences.Identity.username,
			Preferences.Identity.realName,
		],
		.defaultIRCopMessages: [
			Preferences.Commands.irCopKillMessage,
			Preferences.Commands.irCopGlineMessage,
			Preferences.Commands.irCopShunMessage,
		],
		.hidden: [
			Preferences.Internals.appSleepDisabled,
			Preferences.Logging.loadHistoryLazily,
			Preferences.Appearance.disableSidebarTranslucency,
			Preferences.Logging.scrollbackVisibleLimit,
		],
	]
}
