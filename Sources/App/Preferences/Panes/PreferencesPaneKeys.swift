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

/// One setting a pane binds: the typed key, and the words the pane puts beside
/// its control.
struct PreferencesBoundKey {
	let key: any AnyPreferenceKey
	let displayName: LocalizedStringResource

	init(_ key: any AnyPreferenceKey, _ displayName: LocalizedStringResource) {
		self.key = key
		self.displayName = displayName
	}
}

/** Which typed keys each pane binds to, and what each one is called.

 The panes read and write through these declarations, and this list is what
 `PreferencesPaneInventoryTests` checks against the catalogue: a key a pane
 binds to that the catalogue does not know is a setting that would never be
 exported, imported or registered.

 The display name is the pane's own label, which is what lets an import preview
 name the settings it is about to change without printing the defaults keys
 they are stored under. */
enum PreferencesPaneKeys {
	static let keysByPane: [PreferencesPane: [PreferencesBoundKey]] = [
		.general: [
			.init(Preferences.Connection.confirmQuit, .Settings.generalConfirmQuit),
			.init(Preferences.Connection.awayOnScreenSleep, .Settings.generalAwayOnScreenSleep),
			.init(Preferences.Connection.rejoinOnKick, .Settings.generalRejoinOnKick),
			.init(Preferences.Connection.autojoinOnInvite, .Settings.generalAutojoinOnInvite),
			.init(Preferences.Logging.reloadScrollbackOnLaunch, .Settings.generalReloadScrollback),
			.init(Preferences.Appearance.rememberQueryStates, .Settings.generalRememberQueries),
		],
		.ircv3: [
			.init(Preferences.Connection.displayTypingNotifications, .Settings.ircv3DisplayTypingNotifications),
			.init(Preferences.Connection.sendTypingNotifications, .Settings.ircv3SendTypingNotifications),
			.init(Preferences.Connection.echoMessageCapability, .Settings.ircv3EchoMessage),
			.init(Preferences.Connection.requestChatHistory, .Settings.ircv3RequestChatHistory),
			.init(Preferences.Connection.synchronizeReadMarkers, .Settings.ircv3SynchronizeReadMarkers),
			.init(Preferences.Connection.disabledCapabilities, .Settings.ircv3Capabilities),
		],
		.notifications: [
			.init(Preferences.Notifications.onlySpeakForSelection, .Settings.notificationsOnlySpeakSelection),
			.init(
				Preferences.Notifications.flag(.channelMessage, .speakChannelName),
				.Settings.notificationsSpeakChannelName
			),
			.init(
				Preferences.Notifications.flag(.channelMessage, .speakNickname),
				.Settings.notificationsSpeakNickname
			),
			.init(Preferences.Notifications.displayDockBadge, .Settings.notificationsDockBadgePrivate),
			.init(
				Preferences.Notifications.publicMessageCountOnDockBadge,
				.Settings.notificationsDockBadgePublic
			),
			.init(Preferences.Notifications.postWhileInFocus, .Settings.notificationsPostWhileInFocus),
		],
		.highlights: [
			.init(Preferences.Highlights.matchingMethod, .Settings.highlightsMatchTypeLabel),
			.init(Preferences.Logging.logHighlights, .Settings.highlightsLogToWindow),
			.init(Preferences.Highlights.trackLocalNickname, .Settings.highlightsTrackLocalNickname),
			.init(Preferences.Highlights.matchKeywords, .Settings.highlightsWordsLabel),
			.init(Preferences.Highlights.excludeKeywords, .Settings.highlightsExcludeWordsLabel),
		],
		.interface: [
			.init(Preferences.Messages.rightToLeftFormatting, .Settings.interfaceRightToLeftText),
			.init(Preferences.Appearance.preferredAppearance, .Settings.interfaceAppearanceLabel),
			.init(Preferences.Appearance.memberListNoModeSymbol, .Settings.interfaceNoModeSymbol),
			.init(Preferences.Appearance.memberListSortFavorsServerStaff, .Settings.interfaceStaffAtTop),
			.init(
				Preferences.Appearance.memberListUpdatesPopoverOnScroll,
				.Settings.interfacePopoverUpdatesOnScroll
			),
			.init(
				Preferences.Badges.serverListUnreadHighlight,
				.Settings.interfaceUnreadHighlightColorLabel
			),
		] + UserListModeBadge.allCases.map { .init($0.preferenceKey, $0.displayName) },
		.style: [
			.init(Preferences.Theme.transcriptTheme, .TranscriptTheme.transcriptTheme),
			.init(Preferences.Messages.autoAddScrollbackMark, .Settings.styleAutoScrollbackMarker),
			.init(Preferences.Messages.showDateChanges, .Settings.styleShowDateChanges),
			.init(Preferences.Messages.showJoinLeave, .Settings.styleShowJoinLeave),
			.init(Preferences.Messages.showInlineMedia, .TranscriptTheme.showInlineImages),
			.init(Preferences.Logging.scrollbackSaveLimit, .Settings.styleScrollbackSaveLimit),
			.init(Preferences.Messages.disableNicknameColorHashing, .Settings.styleDisableNicknameColors),
			.init(Preferences.Connection.displayServerMOTD, .Settings.styleShowMotd),
		],
		.controls: [
			.init(
				Preferences.Appearance.channelNavigationIsServerSpecific,
				.Settings.controlsNavigationServerSpecific
			),
			.init(Preferences.Input.userDoubleClickAction, .Settings.controlsUserDoubleClickLabel),
			.init(Preferences.Input.commandWKeyAction, .Settings.controlsCommandWLabel),
			.init(Preferences.Appearance.connectOnDoubleClick, .Settings.controlsConnectOnDoubleClick),
			.init(Preferences.Appearance.disconnectOnDoubleClick, .Settings.controlsDisconnectOnDoubleClick),
			.init(Preferences.Appearance.joinOnDoubleClick, .Settings.controlsJoinOnDoubleClick),
			.init(Preferences.Appearance.leaveOnDoubleClick, .Settings.controlsLeaveOnDoubleClick),
			.init(Preferences.Messages.copyOnSelect, .Settings.controlsCopyOnSelect),
			.init(Preferences.Messages.openBrowserInBackground, .Settings.controlsOpenLinksInBackground),
			.init(Preferences.Input.automaticSpellCheck, .Settings.controlsSpellCheck),
			.init(Preferences.Input.automaticGrammarCheck, .Settings.controlsGrammarCheck),
			.init(Preferences.Input.automaticSpellCorrection, .Settings.controlsSpellCorrection),
			.init(Preferences.Input.historyIsChannelSpecific, .Settings.controlsHistoryPerSelection),
			.init(Preferences.Input.commandReturnSendsAction, .Settings.controlsCommandReturnAction),
			.init(Preferences.Input.controlEnterSendsMessage, .Settings.controlsControlEnterSends),
			.init(Preferences.Input.textViewFontSize, .Settings.controlsTextSizeLabel),
			.init(Preferences.Input.tabKeyAction, .Settings.controlsTabKeyLabel),
			.init(Preferences.Input.tabCompletionSuffix, .Settings.controlsCompletionSuffixLabel),
		],
		// The pane lists what the plugin manager reports; it binds nothing.
		.addOns: [],
		.channelManagement: [
			.init(Preferences.Commands.banFormat, .Settings.channelManagementBanFormatLabel),
			.init(Preferences.Commands.kickMessage, .Settings.channelManagementKickReasonLabel),
		],
		.commandScope: [
			.init(Preferences.Commands.amsgAllConnections, .Settings.commandScopeAmsg),
			.init(Preferences.Commands.awayAllConnections, .Settings.commandScopeAway),
			.init(Preferences.Commands.nickAllConnections, .Settings.commandScopeNick),
			.init(Preferences.Commands.clearAllConnections, .Settings.commandScopeClearall),
			.init(Preferences.Commands.giveFocusOnMessageCommand, .Settings.commandScopeFocusOnMessage),
			.init(Preferences.Commands.noticeDestination, .Settings.commandScopeNoticeLabel),
		],
		.floodControl: [
			.init(
				Preferences.Connection.autojoinDelayAfterIdentification,
				.Settings.floodControlIdentifyDelayLabel
			),
			.init(
				Preferences.Appearance.trackUserAwayStatusMaximumChannelSize,
				.Settings.floodControlWhoLimitLabel
			),
		],
		.incomingData: [
			.init(Preferences.Messages.replyToCTCPRequests, .Settings.incomingDataReplyCtcp),
			.init(Preferences.Messages.detectHighlightSpam, .Settings.incomingDataHighlightSpam),
			.init(Preferences.Messages.removeAllFormatting, .Settings.incomingDataRemoveFormatting),
			.init(Preferences.Messages.filterUnicodeTextSpam, .Settings.incomingDataUnicodeSpam),
		],
		.fileTransfers: [
			.init(Preferences.FileTransfers.requestReplyAction, .Settings.fileTransfersReplyActionLabel),
			.init(Preferences.FileTransfers.ipAddressDetectionMethod, .Settings.fileTransfersDetectionLabel),
			.init(
				Preferences.FileTransfers.manuallyEnteredIPAddress,
				.Settings.fileTransfersManualAddressLabel
			),
			.init(Preferences.FileTransfers.portRangeStart, .Settings.fileTransfersPortRangeFirst),
			.init(Preferences.FileTransfers.portRangeEnd, .Settings.fileTransfersPortRangeLast),
			.init(Preferences.FileTransfers.requestsAreReversed, .Settings.fileTransfersReverseDcc),
			.init(Preferences.FileTransfers.preventIdleSystemSleep, .Settings.fileTransfersPreventSleep),
		],
		.logLocation: [.init(Preferences.Logging.logToDisk, .Settings.logLocationToggle)],
		.defaultIdentity: [
			.init(Preferences.Identity.nickname, .Settings.defaultIdentityNickname),
			.init(Preferences.Identity.awayNickname, .Settings.defaultIdentityAwayNickname),
			.init(Preferences.Identity.username, .Settings.defaultIdentityUsername),
			.init(Preferences.Identity.realName, .Settings.defaultIdentityRealname),
		],
		.defaultIRCopMessages: [
			.init(Preferences.Commands.irCopKillMessage, .Settings.ircopKillLabel),
			.init(Preferences.Commands.irCopGlineMessage, .Settings.ircopGlineLabel),
			.init(Preferences.Commands.irCopShunMessage, .Settings.ircopShunLabel),
		],
		.hidden: [
			.init(Preferences.Internals.appSleepDisabled, .Settings.hiddenAppNap),
			.init(Preferences.Logging.loadHistoryLazily, .Settings.hiddenLoadHistoryLazily),
			.init(Preferences.Appearance.disableSidebarTranslucency, .Settings.hiddenSidebarTranslucency),
			.init(Preferences.Logging.scrollbackVisibleLimit, .Settings.hiddenScrollbackVisibleLimit),
		],
	]

	private static let displayNamesByKeyName: [String: LocalizedStringResource] = {
		var names: [String: LocalizedStringResource] = [:]

		for entry in keysByPane.values.joined() {
			names[entry.key.name] = entry.displayName
		}

		return names
	}()

	/// What Settings calls a stored key, or `nil` for a key no pane shows —
	/// which is a key whose raw name is no use to anyone either.
	static func displayName(forKeyNamed name: String) -> String? {
		displayNamesByKeyName[name].map { String(localized: $0) }
	}
}
