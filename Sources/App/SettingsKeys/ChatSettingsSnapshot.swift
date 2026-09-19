// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Fills the IRC layer's setting snapshot from the defaults store.

 This lives with the settings rather than with the snapshot so that the
 connection code declares what it needs and never reads the store itself. */
extension ChatSettings {
	/// Reads the shared defaults store once, on the main actor that owns it.
	/// The result is a `Sendable` value the connection layer keeps.
	@MainActor
	static func current(stores: SettingsStores = .live) -> ChatSettings {
		var snapshot = ChatSettings()

		snapshot.autojoinDelayAfterIdentification = stores[SettingsKeys.Connection.autojoinDelayAfterIdentification]
		snapshot.autojoinOnInvite = stores[SettingsKeys.Connection.autojoinOnInvite]
		snapshot.rejoinOnKick = stores[SettingsKeys.Connection.rejoinOnKick]
		snapshot.disconnectOnSleep = stores[SettingsKeys.Connection.disconnectOnSleep]
		snapshot.awayOnScreenSleep = stores[SettingsKeys.Connection.awayOnScreenSleep]
		snapshot.enableEchoMessageCapability = stores[SettingsKeys.Connection.echoMessageCapability]
		snapshot.requestChatHistory = stores[SettingsKeys.Connection.requestChatHistory]
		snapshot.synchronizeReadMarkers = stores[SettingsKeys.Connection.synchronizeReadMarkers]
		snapshot.disabledCapabilities = Set(stores[SettingsKeys.Connection.disabledCapabilities])
		snapshot.remembersDirectConversations = stores[SettingsKeys.Appearance.rememberDirectConversations]
		let awayTrackingLimit = SettingsKeys.Appearance.trackUserAwayStatusMaximumChannelSize
		snapshot.trackUserAwayStatusMaximumChannelSize = stores[awayTrackingLimit]

		snapshot.removeAllFormatting = stores[SettingsKeys.Messages.removeAllFormatting]
		snapshot.showJoinLeave = stores[SettingsKeys.Messages.showJoinLeave]
		snapshot.displayServerMOTD = stores[SettingsKeys.Connection.displayServerMOTD]
		snapshot.replyToCTCPRequests = stores[SettingsKeys.Messages.replyToCTCPRequests]
		snapshot.masqueradeCTCPVersion = stores[stored: SettingsKeys.Identity.ctcpVersionMasquerade]
		snapshot.locationToSendNotices = stores[SettingsKeys.Commands.noticeDestination]
		snapshot.sendTypingNotifications = stores[SettingsKeys.Connection.sendTypingNotifications]
		snapshot.displayTypingNotifications = stores[SettingsKeys.Connection.displayTypingNotifications]
		snapshot.giveFocusOnMessageCommand = stores[SettingsKeys.Commands.giveFocusOnMessageCommand]
		snapshot.autoAddUnreadMarker = stores[SettingsKeys.Messages.autoAddUnreadMarker]
		snapshot.defaultKickMessage = stores[SettingsKeys.Commands.kickMessage]
		snapshot.irCopDefaultKillMessage = stores[SettingsKeys.Commands.irCopKillMessage]
		snapshot.banFormat = stores[SettingsKeys.Commands.banFormat]

		snapshot.amsgAllConnections = stores[SettingsKeys.Commands.amsgAllConnections]
		snapshot.awayAllConnections = stores[SettingsKeys.Commands.awayAllConnections]
		snapshot.nickAllConnections = stores[SettingsKeys.Commands.nickAllConnections]
		snapshot.clearAllConnections = stores[SettingsKeys.Commands.clearAllConnections]

		snapshot.displayPublicMessageCountOnDockBadge = stores[SettingsKeys.Notifications.publicMessageCountOnDockBadge]
		snapshot.memberListSortFavorsServerStaff = stores[SettingsKeys.Appearance.memberListSortFavorsServerStaff]
		snapshot.disableNicknameColorHashing = stores[SettingsKeys.Messages.disableNicknameColorHashing]
		snapshot.soundIsMuted = stores[SettingsKeys.Notifications.soundIsMuted]
		snapshot.notifyAboutMentions = stores[SettingsKeys.Notifications.notifyAboutMentions]
		snapshot.postNotificationsWhileInFocus = stores[SettingsKeys.Notifications.postWhileInFocus]

		snapshot.highlightCurrentNickname = stores[SettingsKeys.Highlights.trackLocalNickname]
		snapshot.highlightMatchingMethod = stores[SettingsKeys.Highlights.matchingMethod]
		snapshot.highlightMatchKeywords = SettingsKeys.Highlights
			.keywords(in: stores[SettingsKeys.Highlights.matchKeywords])
		snapshot.highlightExcludeKeywords = SettingsKeys.Highlights
			.keywords(in: stores[SettingsKeys.Highlights.excludeKeywords])
		snapshot.logHighlights = stores[SettingsKeys.Logging.logHighlights]

		/* Not `ApplicationPaths.isWritingTranscripts`: the snapshot has to answer
		 from the store it was handed, which a transfer preview replaces. */
		snapshot.logToDiskIsEnabled = stores[SettingsKeys.Logging.logToDisk]
			&& ApplicationPaths.transcriptFolderURL != nil
		snapshot.developerModeEnabled = stores[SettingsKeys.Commands.developerMode]
		snapshot.fileTransferRequestReplyAction = stores[SettingsKeys.FileTransfers.requestReplyAction]
		snapshot.fileTransferPortRangeStart = stores[SettingsKeys.FileTransfers.portRangeStart]
		snapshot.fileTransferPortRangeEnd = stores[SettingsKeys.FileTransfers.portRangeEnd]
		snapshot.fileTransferIPAddressInterfaceName = stores[stored: SettingsKeys.FileTransfers.ipAddressInterfaceName]

		return snapshot
	}
}
