// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Every setting the IRC layer reads, taken once and handed to the sessions.

 The values are a snapshot rather than live lookups so that the connection code
 has one place to read from and tests can hand it a different one. `ChatSession`
 rebuilds the snapshot whenever the defaults store reports a write, which is the
 only way any of these values can change.

 What it deliberately does not cover: the stored collections and identity
 defaults the IRC layer reads from their declaration directly — the connection
 list, the STS policies, the transcript folder bookmark, the sleep switches and
 the identity a fresh `ServerConfig` starts from. Those are read once at the
 point they are persisted or seeded, not branched on per line, so a snapshot of
 them would only be a second copy to keep in step. */
nonisolated struct ChatSettings: Sendable, Equatable {
	// MARK: Connection

	var autojoinDelayAfterIdentification: TimeInterval = 0
	var autojoinOnInvite = false
	var rejoinOnKick = false
	var disconnectOnSleep = false
	var awayOnScreenSleep = false
	var enableEchoMessageCapability = false
	var requestChatHistory = true
	var synchronizeReadMarkers = true
	/// The IRCv3 capabilities the user switched off, by wire name. Empty means
	/// every capability the registry knows is available.
	var disabledCapabilities: Set<String> = []
	var remembersDirectConversations = false
	var trackUserAwayStatusMaximumChannelSize: UInt = 0

	// MARK: Messages

	var removeAllFormatting = false
	var showJoinLeave = false
	var displayServerMOTD = false
	var replyToCTCPRequests = false
	var masqueradeCTCPVersion: String?
	var locationToSendNotices: NoticeSendLocation = .selectedConversation
	var sendTypingNotifications = false
	var displayTypingNotifications = true
	var giveFocusOnMessageCommand = false
	var autoAddUnreadMarker = false
	var defaultKickMessage = ""
	var irCopDefaultKillMessage = ""
	var banFormat: HostmaskBanFormat = .whnin

	// MARK: Commands that fan out across connections

	var amsgAllConnections = false
	var awayAllConnections = false
	var nickAllConnections = false
	var clearAllConnections = false

	// MARK: Presentation

	var displayPublicMessageCountOnDockBadge = false
	var memberListSortFavorsServerStaff = false
	var disableNicknameColorHashing = false
	var soundIsMuted = false
	var notifyAboutMentions = false
	var postNotificationsWhileInFocus = false

	// MARK: Highlights

	var highlightCurrentNickname = false
	var highlightMatchingMethod: NicknameHighlightMatchMode = .partial
	var highlightMatchKeywords: [String] = []
	var highlightExcludeKeywords: [String] = []
	var logHighlights = false

	// MARK: Logging and transfers

	var logToDiskIsEnabled = false
	var developerModeEnabled = false
	var fileTransferRequestReplyAction: FileTransferRequestBehavior = .ignore
	var fileTransferPortRangeStart: UInt16 = 0
	var fileTransferPortRangeEnd: UInt16 = 0
	var fileTransferIPAddressInterfaceName: String?

	init() {}
}
