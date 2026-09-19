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

/** The objects a session talks to that are not other model objects: the window,
 the menus and the application. Every reference is weak — the session outlives
 none of them and owns none of them — and every one may legitimately be `nil`,
 which is what makes a session constructible without a user interface. */
@MainActor
final class ChatServices {
	weak var output: (any ServerSessionPresenting)?
	weak var menu: (any MenuPresenting)?
	weak var channelList: (any ChannelListPresenting)?
	weak var applicationState: (any ApplicationStatePresenting)?
	weak var notifications: (any UserNotificationPresenting)?
	weak var fileTransfers: (any FileTransferPresenting)?
	weak var messageRules: (any MessageRuleFiltering)?
	weak var scripts: (any UserScriptRunning)?
	weak var chatSession: ChatSession?

	/** The nickname format the loaded theme asks for, already resolved against
	 the theme's own default.

	 A closure rather than a port: one question with one answer, and a session
	 that is handed none formats nicknames the way ``NicknameFormat/default``
	 spells them. Nothing in the chat domain has to know what a theme is. */
	var themeNicknameFormat: @MainActor () -> String = { NicknameFormat.default }

	/** Redraws the Dock badge for the unread counts as they now stand.

	 A closure for the same reason: the badge is drawn by the application, the
	 counters belong to the conversations, and there is nothing to ask — only
	 something to tell. */
	var updateDockBadge: @MainActor () -> Void = {}

	/** Where a certificate the system would not vouch for is put in front of
	 the user.

	 Owned rather than borrowed: it is a panel with no other home, and a
	 connection that raises one has to be able to take it down again from
	 wherever the session ends. */
	let certificateTrust = CertificateTrustPanel()

	/** The transport-security policies servers have pinned hosts to.

	 One table for the process by default — a policy names a host, not a
	 session — reached through here rather than statically so a test can drive
	 the STS path with a store of its own. */
	let stsPolicies: STSPolicyStore

	/** The box the running application installs its window, menus and session
	 chat session into, for the handful of protocol-layer entry points that have no
	 session to ask — the URL scheme handler, chiefly.

	 Only the services are shared: a setting snapshot belongs to whoever hands
	 it out, so there is no process-wide copy of it to keep in step. Sessions read
	 the one their chat session published. */
	static let shared = ChatServices()

	init(
		output: (any ServerSessionPresenting)? = nil,
		menu: (any MenuPresenting)? = nil,
		channelList: (any ChannelListPresenting)? = nil,
		applicationState: (any ApplicationStatePresenting)? = nil,
		notifications: (any UserNotificationPresenting)? = nil,
		fileTransfers: (any FileTransferPresenting)? = nil,
		messageRules: (any MessageRuleFiltering)? = nil,
		scripts: (any UserScriptRunning)? = nil,
		chatSession: ChatSession? = nil,
		stsPolicies: STSPolicyStore = .applicationStore
	) {
		self.output = output
		self.menu = menu
		self.channelList = channelList
		self.applicationState = applicationState
		self.notifications = notifications
		self.fileTransfers = fileTransfers
		self.messageRules = messageRules
		self.scripts = scripts
		self.chatSession = chatSession
		self.stsPolicies = stsPolicies
	}
}

/** What a session needs from outside itself: the setting values it branches
 on and the services it calls into.

 It is main-actor state, because `services` is a box of main-actor references
 and every reader of the setting half is on the main actor too. What crosses
 a boundary is `ChatSettings` on its own: it is a `Sendable` value, so a
 caller that needs it elsewhere copies it out rather than carrying this. */
struct ChatEnvironment {
	var settings: ChatSettings
	var services: ChatServices

	var output: (any ServerSessionPresenting)? {
		services.output
	}

	var menu: (any MenuPresenting)? {
		services.menu
	}

	var chatSession: ChatSession? {
		services.chatSession
	}
}

extension ChatEnvironment {
	/// Live setting values against the application's services.
	static var application: ChatEnvironment {
		ChatEnvironment(settings: .current(), services: ChatServices.shared)
	}
}

/// Shorthands so the connection code reads `output?.…` rather than reaching
/// through the environment at every call.
@MainActor
extension ServerSession {
	var output: (any ServerSessionPresenting)? {
		environment.services.output
	}

	var menu: (any MenuPresenting)? {
		environment.services.menu
	}

	var channelListPresentation: (any ChannelListPresenting)? {
		environment.services.channelList
	}

	var chatSession: ChatSession? {
		environment.services.chatSession
	}
}
