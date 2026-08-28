/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

/** Every preference the IRC layer reads, taken once and handed to the clients.

 The values are a snapshot rather than live lookups so that the connection code
 has one place to read from and tests can hand it a different one. `IRCWorld`
 rebuilds the snapshot whenever the defaults store reports a write, which is the
 only way any of these values can change. */
nonisolated struct ClientPreferences: Sendable, Equatable {
	// MARK: Connection

	var autojoinDelayAfterIdentification: TimeInterval = 0
	var autojoinDelayBetweenChannelJoins: TimeInterval = 0
	var autojoinMaximumChannelJoins: UInt = 0
	var autojoinOnInvite = false
	var rejoinOnKick = false
	var appNapEnabled = false
	var preferModernCiphers = false
	var disconnectOnSleep = false
	var awayOnScreenSleep = false
	var enableEchoMessageCapability = false
	var rememberServerListQueryStates = false
	var trackUserAwayStatusMaximumChannelSize: UInt = 0

	// MARK: Messages

	var removeAllFormatting = false
	var showJoinLeave = false
	var displayServerMOTD = false
	var replyToCTCPRequests = false
	var masqueradeCTCPVersion: String?
	var locationToSendNotices: TXNoticeSendLocation = .selectedChannel
	var sendTypingNotifications = false
	var giveFocusOnMessageCommand = false
	var autoAddScrollbackMark = false
	var defaultKickMessage = ""
	var irCopDefaultKillMessage = ""
	var banFormat: TXHostmaskBanFormat = .whnin

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
	var themeNicknameFormat = ""
	var themeNicknameFormatDefault = ""
	var soundIsMuted = false

	// MARK: Highlights

	var highlightCurrentNickname = false
	var highlightMatchingMethod: TXNicknameHighlightMatchType = .partial
	var highlightMatchKeywords: [String] = []
	var highlightExcludeKeywords: [String] = []
	var logHighlights = false

	// MARK: Logging and transfers

	var logToDiskIsEnabled = false
	var developerModeEnabled = false
	var fileTransferRequestReplyAction: TXFileTransferRequestReply = .ignore
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
	weak var applicationState: (any ClientApplicationState)?
	weak var world: IRCWorld?

	init(
		output: (any ClientOutput)? = nil,
		menu: (any ClientMenuPresenting)? = nil,
		applicationState: (any ClientApplicationState)? = nil,
		world: IRCWorld? = nil
	) {
		self.output = output
		self.menu = menu
		self.applicationState = applicationState
		self.world = world
	}
}

/** What a client needs from outside itself: the preference values it branches
 on and the services it calls into.

 It is a value so that it can be handed to a client at construction and copied
 into the objects the client makes; the services inside it are shared by
 reference, because they are the one window and the one menu bar. */
nonisolated struct ClientEnvironment: Sendable {
	var preferences: ClientPreferences
	var services: ClientServices

	@MainActor
	var output: (any ClientOutput)? {
		services.output
	}

	@MainActor
	var menu: (any ClientMenuPresenting)? {
		services.menu
	}

	@MainActor
	var world: IRCWorld? {
		services.world
	}
}

extension ClientEnvironment {
	/** The environment the running application installs, for the handful of
	 protocol-layer entry points that have no client to ask — the URL scheme
	 handler, chiefly. Clients hold their own copy and never read this. */
	@MainActor static var shared = ClientEnvironment(
		preferences: ClientPreferences(),
		services: ClientServices()
	)

	/// An environment with live preference values and no user interface.
	@MainActor static func headless() -> ClientEnvironment {
		ClientEnvironment(preferences: .current(), services: ClientServices())
	}
}

/// Shorthands so the connection code reads `output?.…` rather than reaching
/// through the environment at every call.
@MainActor
extension IRCClient {
	var output: (any ClientOutput)? {
		environment.services.output
	}

	var menu: (any ClientMenuPresenting)? {
		environment.services.menu
	}

	var world: IRCWorld? {
		environment.services.world
	}
}
