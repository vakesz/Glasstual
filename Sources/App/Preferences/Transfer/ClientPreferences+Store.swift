// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Fills the IRC layer's preference snapshot from the defaults store.

 This lives with the preferences rather than with the snapshot so that the
 connection code declares what it needs and never reads the store itself. */
extension ClientPreferences {
	/// Reads the shared defaults store once, on the main actor that owns it.
	/// The result is a `Sendable` value the connection layer keeps.
	@MainActor
	static func current(stores: PreferencesTransferStores = .live) -> ClientPreferences {
		var snapshot = ClientPreferences()

		snapshot.autojoinDelayAfterIdentification = stores[Preferences.Connection.autojoinDelayAfterIdentification]
		snapshot.autojoinOnInvite = stores[Preferences.Connection.autojoinOnInvite]
		snapshot.rejoinOnKick = stores[Preferences.Connection.rejoinOnKick]
		snapshot.appNapEnabled = !stores[Preferences.Internals.appSleepDisabled]
		snapshot.preferModernCiphers = stores[Preferences.Connection.preferModernCiphers]
		snapshot.disconnectOnSleep = stores[Preferences.Connection.disconnectOnSleep]
		snapshot.awayOnScreenSleep = stores[Preferences.Connection.awayOnScreenSleep]
		snapshot.enableEchoMessageCapability = stores[Preferences.Connection.echoMessageCapability]
		snapshot.requestChatHistory = stores[Preferences.Connection.requestChatHistory]
		snapshot.synchronizeReadMarkers = stores[Preferences.Connection.synchronizeReadMarkers]
		snapshot.disabledCapabilities = Set(stores[Preferences.Connection.disabledCapabilities])
		snapshot.rememberServerListQueryStates = stores[Preferences.Appearance.rememberQueryStates]
		let awayTrackingLimit = Preferences.Appearance.trackUserAwayStatusMaximumChannelSize
		snapshot.trackUserAwayStatusMaximumChannelSize = stores[awayTrackingLimit]

		snapshot.removeAllFormatting = stores[Preferences.Messages.removeAllFormatting]
		snapshot.showJoinLeave = stores[Preferences.Messages.showJoinLeave]
		snapshot.displayServerMOTD = stores[Preferences.Connection.displayServerMOTD]
		snapshot.replyToCTCPRequests = stores[Preferences.Messages.replyToCTCPRequests]
		snapshot.masqueradeCTCPVersion = stores[stored: Preferences.Identity.ctcpVersionMasquerade]
		snapshot.locationToSendNotices = stores[Preferences.Commands.noticeDestination]
		snapshot.sendTypingNotifications = stores[Preferences.Connection.sendTypingNotifications]
		snapshot.displayTypingNotifications = stores[Preferences.Connection.displayTypingNotifications]
		snapshot.giveFocusOnMessageCommand = stores[Preferences.Commands.giveFocusOnMessageCommand]
		snapshot.autoAddScrollbackMark = stores[Preferences.Messages.autoAddScrollbackMark]
		snapshot.defaultKickMessage = stores[Preferences.Commands.kickMessage]
		snapshot.irCopDefaultKillMessage = stores[Preferences.Commands.irCopKillMessage]
		snapshot.banFormat = stores[Preferences.Commands.banFormat]

		snapshot.amsgAllConnections = stores[Preferences.Commands.amsgAllConnections]
		snapshot.awayAllConnections = stores[Preferences.Commands.awayAllConnections]
		snapshot.nickAllConnections = stores[Preferences.Commands.nickAllConnections]
		snapshot.clearAllConnections = stores[Preferences.Commands.clearAllConnections]

		snapshot.displayPublicMessageCountOnDockBadge = stores[Preferences.Notifications.publicMessageCountOnDockBadge]
		snapshot.memberListSortFavorsServerStaff = stores[Preferences.Appearance.memberListSortFavorsServerStaff]
		snapshot.disableNicknameColorHashing = stores[Preferences.Messages.disableNicknameColorHashing]
		snapshot.showInlineMedia = stores[Preferences.Messages.showInlineMedia]
		snapshot.soundIsMuted = stores[Preferences.Notifications.soundIsMuted]

		snapshot.highlightCurrentNickname = stores[Preferences.Highlights.trackLocalNickname]
		snapshot.highlightMatchingMethod = stores[Preferences.Highlights.matchingMethod]
		snapshot.highlightMatchKeywords = Preferences.Highlights
			.keywords(in: stores[Preferences.Highlights.matchKeywords])
		snapshot.highlightExcludeKeywords = Preferences.Highlights
			.keywords(in: stores[Preferences.Highlights.excludeKeywords])
		snapshot.logHighlights = stores[Preferences.Logging.logHighlights]

		snapshot.logToDiskIsEnabled = stores[Preferences.Logging.logToDisk] && ApplicationPaths.transcriptFolderURL != nil
		snapshot.developerModeEnabled = stores[Preferences.Commands.developerMode]
		snapshot.fileTransferRequestReplyAction = stores[Preferences.FileTransfers.requestReplyAction]
		snapshot.fileTransferPortRangeStart = stores[Preferences.FileTransfers.portRangeStart]
		snapshot.fileTransferPortRangeEnd = stores[Preferences.FileTransfers.portRangeEnd]
		snapshot.fileTransferIPAddressInterfaceName = stores[stored: Preferences.FileTransfers.ipAddressInterfaceName]

		return snapshot
	}
}
