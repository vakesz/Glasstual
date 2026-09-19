// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// One setting a pane binds: the typed key, and the words the pane puts beside
/// its control.
struct SettingsBoundKey {
	let key: any AnySettingsKey
	let displayName: LocalizedStringResource

	init(_ key: any AnySettingsKey, _ displayName: LocalizedStringResource) {
		self.key = key
		self.displayName = displayName
	}
}

/** Which typed keys each pane binds to, and what each one is called.

 The panes read and write through these declarations, and they are what
 `SettingsPaneInventoryTests` checks against the catalogue: a key a pane
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
		.init(SettingsKeys.Internals.appLanguages, .Settings.appLanguage),
		.init(SettingsKeys.Connection.confirmQuit, .Settings.generalConfirmQuit),
		.init(SettingsKeys.Connection.awayOnScreenSleep, .Settings.generalAwayOnScreenSleep),
		.init(SettingsKeys.Connection.preventSleepWhileConnected, .Settings.preventSleepWhileConnected),
		.init(SettingsKeys.Connection.rejoinOnKick, .Settings.generalRejoinOnKick),
		.init(SettingsKeys.Connection.autojoinOnInvite, .Settings.generalAutojoinOnInvite),
		.init(SettingsKeys.Logging.reloadScrollbackOnLaunch, .Settings.generalReloadScrollback),
		.init(SettingsKeys.Appearance.rememberDirectConversations, .Settings.generalRememberQueries),
	]

	private static let controlsKeys: [SettingsBoundKey] = [
		.init(
			SettingsKeys.Appearance.conversationNavigationIsServerSpecific,
			.Settings.controlsNavigationServerSpecific
		),
		.init(SettingsKeys.Input.userDoubleClickAction, .Settings.controlsUserDoubleClickLabel),
		.init(SettingsKeys.Input.commandWKeyAction, .Settings.controlsCommandWLabel),
		.init(SettingsKeys.Appearance.connectOnDoubleClick, .Settings.controlsConnectOnDoubleClick),
		.init(SettingsKeys.Appearance.disconnectOnDoubleClick, .Settings.controlsDisconnectOnDoubleClick),
		.init(SettingsKeys.Appearance.joinOnDoubleClick, .Settings.controlsJoinOnDoubleClick),
		.init(SettingsKeys.Appearance.leaveOnDoubleClick, .Settings.controlsLeaveOnDoubleClick),
		.init(SettingsKeys.Messages.copyOnSelect, .Settings.controlsCopyOnSelect),
		.init(SettingsKeys.Messages.openBrowserInBackground, .Settings.controlsOpenLinksInBackground),
		.init(SettingsKeys.Input.automaticSpellCheck, .Settings.controlsSpellCheck),
		.init(SettingsKeys.Input.automaticGrammarCheck, .Settings.controlsGrammarCheck),
		.init(SettingsKeys.Input.automaticSpellCorrection, .Settings.controlsSpellCorrection),
		.init(SettingsKeys.Input.historyIsPerSelection, .Settings.controlsHistoryPerSelection),
		.init(SettingsKeys.Input.commandReturnSendsAction, .Settings.controlsCommandReturnAction),
		.init(SettingsKeys.Input.controlEnterSendsMessage, .Settings.controlsControlEnterSends),
		.init(SettingsKeys.Input.textViewFontSize, .Settings.controlsTextSizeLabel),
		.init(SettingsKeys.Input.tabKeyAction, .Settings.controlsTabKeyLabel),
		.init(SettingsKeys.Input.tabCompletionSuffix, .Settings.controlsCompletionSuffixLabel),
	]

	private static let interfaceKeys: [SettingsBoundKey] = [
		.init(SettingsKeys.Messages.rightToLeftFormatting, .Settings.interfaceRightToLeftText),
		.init(SettingsKeys.Appearance.preferredAppearance, .Settings.interfaceAppearanceLabel),
		.init(SettingsKeys.Appearance.memberListSortFavorsServerStaff, .Settings.interfaceStaffAtTop),
		.init(
			SettingsKeys.Appearance.memberListUpdatesPopoverOnScroll,
			.Settings.interfacePopoverUpdatesOnScroll
		),
		.init(
			SettingsKeys.Badges.sidebarUnreadHighlight,
			.Settings.interfaceUnreadHighlightColorLabel
		),
	] + UserListModeBadge.allCases.map { .init($0.settingsKey, $0.displayName) }

	private static let styleKeys: [SettingsBoundKey] = [
		.init(SettingsKeys.Theme.transcriptTheme, .TranscriptTheme.transcriptTheme),
		.init(SettingsKeys.Messages.autoAddUnreadMarker, .Settings.styleAutoScrollbackMarker),
		.init(SettingsKeys.Messages.showDateChanges, .Settings.styleShowDateChanges),
		.init(SettingsKeys.Messages.showJoinLeave, .Settings.styleShowJoinLeave),
		.init(SettingsKeys.Messages.showInlineMedia, .TranscriptTheme.showInlineImages),
		.init(SettingsKeys.Logging.scrollbackSaveLimit, .Settings.styleScrollbackSaveLimit),
		.init(SettingsKeys.Messages.disableNicknameColorHashing, .Settings.styleDisableNicknameColors),
		.init(SettingsKeys.Connection.displayServerMOTD, .Settings.styleShowMotd),
	]

	private static let notificationsKeys: [SettingsBoundKey] = [
		.init(SettingsKeys.Notifications.notifyAboutMentions, .Settings.notificationsNotifyMentions),
		.init(SettingsKeys.Notifications.soundIsMuted, .Settings.notificationsPlaySound),
		.init(SettingsKeys.Notifications.displayDockBadge, .Settings.notificationsDockBadgePrivate),
		.init(
			SettingsKeys.Notifications.publicMessageCountOnDockBadge,
			.Settings.notificationsDockBadgePublic
		),
		.init(SettingsKeys.Notifications.postWhileInFocus, .Settings.notificationsPostWhileInFocus),
	]

	private static let highlightsKeys: [SettingsBoundKey] = [
		.init(SettingsKeys.Highlights.matchingMethod, .Settings.highlightsMatchTypeLabel),
		.init(SettingsKeys.Logging.logHighlights, .Settings.highlightsLogToWindow),
		.init(SettingsKeys.Highlights.trackLocalNickname, .Settings.highlightsTrackLocalNickname),
		.init(SettingsKeys.Highlights.matchKeywords, .Settings.highlightsWordsLabel),
		.init(SettingsKeys.Highlights.excludeKeywords, .Settings.highlightsExcludeWordsLabel),
	]

	/// The pane edits one stored rule list rather than named settings.
	private static let rulesKeys: [SettingsBoundKey] = []

	private static let defaultIdentityKeys: [SettingsBoundKey] = [
		.init(SettingsKeys.Identity.nickname, .Settings.defaultIdentityNickname),
		.init(SettingsKeys.Identity.awayNickname, .Settings.defaultIdentityAwayNickname),
		.init(SettingsKeys.Identity.username, .Settings.defaultIdentityUsername),
		.init(SettingsKeys.Identity.realName, .Settings.defaultIdentityRealname),
	]

	private static let defaultIRCopMessagesKeys: [SettingsBoundKey] = [
		.init(SettingsKeys.Commands.irCopKillMessage, .Settings.ircopKillLabel),
		.init(SettingsKeys.Commands.irCopGlineMessage, .Settings.ircopGlineLabel),
		.init(SettingsKeys.Commands.irCopShunMessage, .Settings.ircopShunLabel),
	]

	private static let commandScopeKeys: [SettingsBoundKey] = [
		.init(SettingsKeys.Commands.amsgAllConnections, .Settings.commandScopeAmsg),
		.init(SettingsKeys.Commands.awayAllConnections, .Settings.commandScopeAway),
		.init(SettingsKeys.Commands.nickAllConnections, .Settings.commandScopeNick),
		.init(SettingsKeys.Commands.clearAllConnections, .Settings.commandScopeClearall),
		.init(SettingsKeys.Commands.giveFocusOnMessageCommand, .Settings.commandScopeFocusOnMessage),
		.init(SettingsKeys.Commands.noticeDestination, .Settings.commandScopeNoticeLabel),
	]

	private static let channelManagementKeys: [SettingsBoundKey] = [
		.init(SettingsKeys.Commands.banFormat, .Settings.channelManagementBanFormatLabel),
		.init(SettingsKeys.Commands.kickMessage, .Settings.channelManagementKickReasonLabel),
	]

	private static let floodControlKeys: [SettingsBoundKey] = [
		.init(
			SettingsKeys.Connection.autojoinDelayAfterIdentification,
			.Settings.floodControlIdentifyDelayLabel
		),
		.init(
			SettingsKeys.Appearance.trackUserAwayStatusMaximumChannelSize,
			.Settings.floodControlWhoLimitLabel
		),
	]

	private static let incomingDataKeys: [SettingsBoundKey] = [
		.init(SettingsKeys.Messages.replyToCTCPRequests, .Settings.incomingDataReplyCtcp),
		.init(SettingsKeys.Messages.detectHighlightSpam, .Settings.incomingDataHighlightSpam),
		.init(SettingsKeys.Messages.removeAllFormatting, .Settings.incomingDataRemoveFormatting),
		.init(SettingsKeys.Messages.filterUnicodeTextSpam, .Settings.incomingDataUnicodeSpam),
	]

	private static let ircv3Keys: [SettingsBoundKey] = [
		.init(SettingsKeys.Connection.displayTypingNotifications, .Settings.ircv3DisplayTypingNotifications),
		.init(SettingsKeys.Connection.sendTypingNotifications, .Settings.ircv3SendTypingNotifications),
		.init(SettingsKeys.Connection.echoMessageCapability, .Settings.ircv3EchoMessage),
		.init(SettingsKeys.Connection.requestChatHistory, .Settings.ircv3RequestChatHistory),
		.init(SettingsKeys.Connection.synchronizeReadMarkers, .Settings.ircv3SynchronizeReadMarkers),
		.init(SettingsKeys.Connection.disabledCapabilities, .Settings.ircv3Capabilities),
	]

	private static let fileTransfersKeys: [SettingsBoundKey] = [
		.init(SettingsKeys.FileTransfers.requestReplyAction, .Settings.fileTransfersReplyActionLabel),
		.init(SettingsKeys.FileTransfers.ipAddressDetectionMethod, .Settings.fileTransfersDetectionLabel),
		.init(
			SettingsKeys.FileTransfers.manuallyEnteredIPAddress,
			.Settings.fileTransfersManualAddressLabel
		),
		.init(SettingsKeys.FileTransfers.portRangeStart, .Settings.fileTransfersPortRangeFirst),
		.init(SettingsKeys.FileTransfers.portRangeEnd, .Settings.fileTransfersPortRangeLast),
		.init(SettingsKeys.FileTransfers.requestsAreReversed, .Settings.fileTransfersReverseDcc),
		.init(SettingsKeys.FileTransfers.preventIdleSystemSleep, .Settings.fileTransfersPreventSleep),
	]

	private static let logLocationKeys: [SettingsBoundKey] = [.init(SettingsKeys.Logging.logToDisk, .Settings.logLocationToggle)]

	private static let hiddenKeys: [SettingsBoundKey] = [
		.init(SettingsKeys.Internals.appSleepDisabled, .Settings.hiddenAppNap),
		.init(SettingsKeys.Logging.loadHistoryLazily, .Settings.hiddenLoadHistoryLazily),
		.init(SettingsKeys.Appearance.disableSidebarTranslucency, .Settings.hiddenSidebarTranslucency),
		.init(SettingsKeys.Logging.scrollbackVisibleLimit, .Settings.hiddenScrollbackVisibleLimit),
	]

	private static let displayNamesByKeyName: [String: LocalizedStringResource] = {
		// Retired controls retain readable names in older archive previews, but
		// are absent from the visible pane inventory and Settings search.
		var names: [String: LocalizedStringResource] = [
			SettingsKeys.Appearance.memberListNoModeSymbol.name: .Settings.interfaceNoModeSymbol,
		]

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
