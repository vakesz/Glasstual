// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// One setting a pane binds: the typed key, and the words the pane puts beside
/// its control.
struct SettingsBoundKey {
	let key: any AnyPreferenceKey
	let displayName: LocalizedStringResource

	init(_ key: any AnyPreferenceKey, _ displayName: LocalizedStringResource) {
		self.key = key
		self.displayName = displayName
	}
}

/** Which typed keys each pane binds to, and what each one is called.

 The panes read and write through these declarations, and they are what
 `PreferencesPaneInventoryTests` checks against the catalogue: a key a pane
 binds to that the catalogue does not know is a setting that would never be
 exported, imported or registered. A `switch` rather than a table, so a pane
 added without its settings does not compile.

 The display name is the pane's own label, which is what lets an import preview
 name the settings it is about to change without printing the defaults keys
 they are stored under. */
enum SettingsPaneKeys {
	/// The settings one pane binds, in the order it draws them.
	static func keys(for pane: SettingsPane) -> [SettingsBoundKey] {
		switch pane {
		case .general: generalKeys
		case .controls: controlsKeys
		case .interface: interfaceKeys
		case .style: styleKeys
		case .notifications: notificationsKeys
		case .highlights: highlightsKeys
		case .rules: rulesKeys
		case .defaultIdentity: defaultIdentityKeys
		case .defaultIRCopMessages: defaultIRCopMessagesKeys
		case .commandScope: commandScopeKeys
		case .channelManagement: channelManagementKeys
		case .floodControl: floodControlKeys
		case .incomingData: incomingDataKeys
		case .ircv3: ircv3Keys
		case .fileTransfers: fileTransfersKeys
		case .logLocation: logLocationKeys
		case .hidden: hiddenKeys
		}
	}

	private static let generalKeys: [SettingsBoundKey] = [
		.init(Preferences.Internals.appLanguages, .Settings.appLanguage),
		.init(Preferences.Connection.confirmQuit, .Settings.generalConfirmQuit),
		.init(Preferences.Connection.awayOnScreenSleep, .Settings.generalAwayOnScreenSleep),
		.init(Preferences.Connection.preventSleepWhileConnected, .Settings.preventSleepWhileConnected),
		.init(Preferences.Connection.rejoinOnKick, .Settings.generalRejoinOnKick),
		.init(Preferences.Connection.autojoinOnInvite, .Settings.generalAutojoinOnInvite),
		.init(Preferences.Logging.reloadScrollbackOnLaunch, .Settings.generalReloadScrollback),
		.init(Preferences.Appearance.rememberQueryStates, .Settings.generalRememberQueries),
	]

	private static let controlsKeys: [SettingsBoundKey] = [
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
	]

	private static let interfaceKeys: [SettingsBoundKey] = [
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
	] + UserListModeBadge.allCases.map { .init($0.preferenceKey, $0.displayName) }

	private static let styleKeys: [SettingsBoundKey] = [
		.init(Preferences.Theme.transcriptTheme, .TranscriptTheme.transcriptTheme),
		.init(Preferences.Messages.autoAddScrollbackMark, .Settings.styleAutoScrollbackMarker),
		.init(Preferences.Messages.showDateChanges, .Settings.styleShowDateChanges),
		.init(Preferences.Messages.showJoinLeave, .Settings.styleShowJoinLeave),
		.init(Preferences.Messages.showInlineMedia, .TranscriptTheme.showInlineImages),
		.init(Preferences.Logging.scrollbackSaveLimit, .Settings.styleScrollbackSaveLimit),
		.init(Preferences.Messages.disableNicknameColorHashing, .Settings.styleDisableNicknameColors),
		.init(Preferences.Connection.displayServerMOTD, .Settings.styleShowMotd),
	]

	private static let notificationsKeys: [SettingsBoundKey] = [
		.init(Preferences.Notifications.notifyAboutMentions, .Settings.notificationsNotifyMentions),
		.init(Preferences.Notifications.soundIsMuted, .Settings.notificationsPlaySound),
		.init(Preferences.Notifications.displayDockBadge, .Settings.notificationsDockBadgePrivate),
		.init(
			Preferences.Notifications.publicMessageCountOnDockBadge,
			.Settings.notificationsDockBadgePublic
		),
		.init(Preferences.Notifications.postWhileInFocus, .Settings.notificationsPostWhileInFocus),
	]

	private static let highlightsKeys: [SettingsBoundKey] = [
		.init(Preferences.Highlights.matchingMethod, .Settings.highlightsMatchTypeLabel),
		.init(Preferences.Logging.logHighlights, .Settings.highlightsLogToWindow),
		.init(Preferences.Highlights.trackLocalNickname, .Settings.highlightsTrackLocalNickname),
		.init(Preferences.Highlights.matchKeywords, .Settings.highlightsWordsLabel),
		.init(Preferences.Highlights.excludeKeywords, .Settings.highlightsExcludeWordsLabel),
	]

	/// The pane edits one stored rule list rather than named settings.
	private static let rulesKeys: [SettingsBoundKey] = []

	private static let defaultIdentityKeys: [SettingsBoundKey] = [
		.init(Preferences.Identity.nickname, .Settings.defaultIdentityNickname),
		.init(Preferences.Identity.awayNickname, .Settings.defaultIdentityAwayNickname),
		.init(Preferences.Identity.username, .Settings.defaultIdentityUsername),
		.init(Preferences.Identity.realName, .Settings.defaultIdentityRealname),
	]

	private static let defaultIRCopMessagesKeys: [SettingsBoundKey] = [
		.init(Preferences.Commands.irCopKillMessage, .Settings.ircopKillLabel),
		.init(Preferences.Commands.irCopGlineMessage, .Settings.ircopGlineLabel),
		.init(Preferences.Commands.irCopShunMessage, .Settings.ircopShunLabel),
	]

	private static let commandScopeKeys: [SettingsBoundKey] = [
		.init(Preferences.Commands.amsgAllConnections, .Settings.commandScopeAmsg),
		.init(Preferences.Commands.awayAllConnections, .Settings.commandScopeAway),
		.init(Preferences.Commands.nickAllConnections, .Settings.commandScopeNick),
		.init(Preferences.Commands.clearAllConnections, .Settings.commandScopeClearall),
		.init(Preferences.Commands.giveFocusOnMessageCommand, .Settings.commandScopeFocusOnMessage),
		.init(Preferences.Commands.noticeDestination, .Settings.commandScopeNoticeLabel),
	]

	private static let channelManagementKeys: [SettingsBoundKey] = [
		.init(Preferences.Commands.banFormat, .Settings.channelManagementBanFormatLabel),
		.init(Preferences.Commands.kickMessage, .Settings.channelManagementKickReasonLabel),
	]

	private static let floodControlKeys: [SettingsBoundKey] = [
		.init(
			Preferences.Connection.autojoinDelayAfterIdentification,
			.Settings.floodControlIdentifyDelayLabel
		),
		.init(
			Preferences.Appearance.trackUserAwayStatusMaximumChannelSize,
			.Settings.floodControlWhoLimitLabel
		),
	]

	private static let incomingDataKeys: [SettingsBoundKey] = [
		.init(Preferences.Messages.replyToCTCPRequests, .Settings.incomingDataReplyCtcp),
		.init(Preferences.Messages.detectHighlightSpam, .Settings.incomingDataHighlightSpam),
		.init(Preferences.Messages.removeAllFormatting, .Settings.incomingDataRemoveFormatting),
		.init(Preferences.Messages.filterUnicodeTextSpam, .Settings.incomingDataUnicodeSpam),
	]

	private static let ircv3Keys: [SettingsBoundKey] = [
		.init(Preferences.Connection.displayTypingNotifications, .Settings.ircv3DisplayTypingNotifications),
		.init(Preferences.Connection.sendTypingNotifications, .Settings.ircv3SendTypingNotifications),
		.init(Preferences.Connection.echoMessageCapability, .Settings.ircv3EchoMessage),
		.init(Preferences.Connection.requestChatHistory, .Settings.ircv3RequestChatHistory),
		.init(Preferences.Connection.synchronizeReadMarkers, .Settings.ircv3SynchronizeReadMarkers),
		.init(Preferences.Connection.disabledCapabilities, .Settings.ircv3Capabilities),
	]

	private static let fileTransfersKeys: [SettingsBoundKey] = [
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
	]

	private static let logLocationKeys: [SettingsBoundKey] = [.init(Preferences.Logging.logToDisk, .Settings.logLocationToggle)]

	private static let hiddenKeys: [SettingsBoundKey] = [
		.init(Preferences.Internals.appSleepDisabled, .Settings.hiddenAppNap),
		.init(Preferences.Logging.loadHistoryLazily, .Settings.hiddenLoadHistoryLazily),
		.init(Preferences.Appearance.disableSidebarTranslucency, .Settings.hiddenSidebarTranslucency),
		.init(Preferences.Logging.scrollbackVisibleLimit, .Settings.hiddenScrollbackVisibleLimit),
	]

	private static let displayNamesByKeyName: [String: LocalizedStringResource] = {
		var names: [String: LocalizedStringResource] = [:]

		for entry in SettingsPane.allCases.flatMap({ keys(for: $0) }) {
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
