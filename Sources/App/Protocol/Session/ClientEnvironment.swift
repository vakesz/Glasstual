// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Every preference the IRC layer reads, taken once and handed to the clients.

 The values are a snapshot rather than live lookups so that the connection code
 has one place to read from and tests can hand it a different one. `ClientDirectory`
 rebuilds the snapshot whenever the defaults store reports a write, which is the
 only way any of these values can change. */
nonisolated struct ClientPreferences: Sendable, Equatable {
	// MARK: Connection

	var autojoinDelayAfterIdentification: TimeInterval = 0
	var autojoinOnInvite = false
	var rejoinOnKick = false
	var appNapEnabled = false
	var preferModernCiphers = true
	var disconnectOnSleep = false
	var awayOnScreenSleep = false
	var enableEchoMessageCapability = false
	var requestChatHistory = true
	var synchronizeReadMarkers = true
	/// The IRCv3 capabilities the user switched off, by wire name. Empty means
	/// every capability the registry knows is available.
	var disabledCapabilities: Set<String> = []
	var rememberServerListQueryStates = false
	var trackUserAwayStatusMaximumChannelSize: UInt = 0

	// MARK: Messages

	var removeAllFormatting = false
	var showJoinLeave = false
	var displayServerMOTD = false
	var replyToCTCPRequests = false
	var masqueradeCTCPVersion: String?
	var locationToSendNotices: NoticeSendLocation = .selectedChannel
	var sendTypingNotifications = false
	var displayTypingNotifications = true
	var giveFocusOnMessageCommand = false
	var autoAddScrollbackMark = false
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
	var showInlineMedia = false
	var soundIsMuted = false

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

/** The objects a client talks to that are not other model objects: the window,
 the menus and the application. Every reference is weak — the client outlives
 none of them and owns none of them — and every one may legitimately be `nil`,
 which is what makes a client constructible without a user interface. */
@MainActor
final class ClientServices {
	weak var output: (any ClientOutput)?
	weak var menu: (any ClientMenuPresenting)?
	weak var channelList: (any ClientChannelListPresenting)?
	weak var applicationState: (any ClientApplicationState)?
	weak var clientDirectory: ClientDirectory?

	/** Where a certificate the system would not vouch for is put in front of
	 the user.

	 Owned rather than borrowed: it is a panel with no other home, and a
	 connection that raises one has to be able to take it down again from
	 wherever the session ends. */
	let certificateTrust = CertificateTrustPanel()

	init(
		output: (any ClientOutput)? = nil,
		menu: (any ClientMenuPresenting)? = nil,
		channelList: (any ClientChannelListPresenting)? = nil,
		applicationState: (any ClientApplicationState)? = nil,
		clientDirectory: ClientDirectory? = nil
	) {
		self.output = output
		self.menu = menu
		self.channelList = channelList
		self.applicationState = applicationState
		self.clientDirectory = clientDirectory
	}
}

/** What a client needs from outside itself: the preference values it branches
 on and the services it calls into.

 It is main-actor state, because `services` is a box of main-actor references
 and every reader of the preference half is on the main actor too. What crosses
 a boundary is `ClientPreferences` on its own: it is a `Sendable` value, so a
 caller that needs it elsewhere copies it out rather than carrying this. */
struct ClientEnvironment {
	var preferences: ClientPreferences
	var services: ClientServices

	var output: (any ClientOutput)? {
		services.output
	}

	var menu: (any ClientMenuPresenting)? {
		services.menu
	}

	var clientDirectory: ClientDirectory? {
		services.clientDirectory
	}
}

extension ClientEnvironment {
	/** The environment the running application installs, for the handful of
	 protocol-layer entry points that have no client to ask — the URL scheme
	 handler, chiefly. Clients hold their own copy and never read this. */
	static var shared = ClientEnvironment(
		preferences: ClientPreferences(),
		services: ClientServices()
	)

	/// An environment with live preference values and no user interface.
	static func headless() -> ClientEnvironment {
		ClientEnvironment(preferences: .current(), services: ClientServices())
	}
}

/// Shorthands so the connection code reads `output?.…` rather than reaching
/// through the environment at every call.
@MainActor
extension Client {
	var output: (any ClientOutput)? {
		environment.services.output
	}

	var menu: (any ClientMenuPresenting)? {
		environment.services.menu
	}

	var channelListPresentation: (any ClientChannelListPresenting)? {
		environment.services.channelList
	}

	var clientDirectory: ClientDirectory? {
		environment.services.clientDirectory
	}
}
