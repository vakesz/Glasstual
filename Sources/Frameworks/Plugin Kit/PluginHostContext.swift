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

/// Live application facilities intentionally exposed to Swift plugins.
///
/// The host supplies adapters for its private models. Plugins receive stable,
/// domain-named values and operations instead of importing the app target.
///
/// Every accessor reads live application state, so the whole surface is
/// main-actor isolated; the host builds it on the main actor and calls plugins
/// there too.
@MainActor
public final class PluginHostContext {
	public let defaults: UserDefaults

	private let clientsProvider: () -> [PluginClient]
	private let selectedChannelProvider: () -> PluginChannel?
	private let metricsProvider: () -> PluginApplicationMetrics
	private let applicationSnapshotProvider: () -> PluginApplicationSnapshot?
	private let themeSnapshotProvider: () -> PluginThemeSnapshot?
	private let connectionObserver: (@escaping (Bool) -> Void) -> PluginObservation
	private let removesFormattingProvider: () -> Bool

	public init(
		defaults: UserDefaults,
		clients: @escaping () -> [PluginClient],
		selectedChannel: @escaping () -> PluginChannel?,
		metrics: @escaping () -> PluginApplicationMetrics,
		applicationSnapshot: @escaping () -> PluginApplicationSnapshot?,
		themeSnapshot: @escaping () -> PluginThemeSnapshot?,
		observeConnectionState: @escaping (@escaping (Bool) -> Void) -> PluginObservation,
		removesFormatting: @escaping () -> Bool
	) {
		self.defaults = defaults
		clientsProvider = clients
		selectedChannelProvider = selectedChannel
		metricsProvider = metrics
		applicationSnapshotProvider = applicationSnapshot
		themeSnapshotProvider = themeSnapshot
		connectionObserver = observeConnectionState
		removesFormattingProvider = removesFormatting
	}

	public var clients: [PluginClient] {
		clientsProvider()
	}

	public var selectedChannel: PluginChannel? {
		selectedChannelProvider()
	}

	public var applicationMetrics: PluginApplicationMetrics {
		metricsProvider()
	}

	/// Launch, install and run-count figures, or `nil` when the host cannot
	/// supply them.
	public var applicationSnapshot: PluginApplicationSnapshot? {
		applicationSnapshotProvider()
	}

	/// The active message style and its resolved appearance, or `nil` when the
	/// host has not finished loading a theme.
	public var themeSnapshot: PluginThemeSnapshot? {
		themeSnapshotProvider()
	}

	public var removesIRCFormatting: Bool {
		removesFormattingProvider()
	}

	/// Observes whether at least one IRC client is logged in.
	/// The handler is invoked immediately and after connection-list changes.
	public func observeConnectionState(_ handler: @escaping (Bool) -> Void) -> PluginObservation {
		connectionObserver(handler)
	}
}

@MainActor
public final class PluginObservation {
	private let cancellation: () -> Void
	private var isCancelled = false

	public init(cancellation: @escaping () -> Void) {
		self.cancellation = cancellation
	}

	/// Cancelling on release spares plugins from unregistering by hand. The
	/// deinit is isolated so it can reach the host's main-actor observers.
	isolated deinit {
		cancel()
	}

	public func cancel() {
		guard isCancelled == false else {
			return
		}
		isCancelled = true
		cancellation()
	}
}

public struct PluginApplicationMetrics: Equatable, Sendable {
	public let messagesSent: UInt
	public let messagesReceived: UInt
	public let bandwidthIn: UInt64
	public let bandwidthOut: UInt64
	public let lastMessageReceived: TimeInterval
	public let visibleLineCount: Int
	public let usesDarkSidebar: Bool

	public init(
		messagesSent: UInt,
		messagesReceived: UInt,
		bandwidthIn: UInt64,
		bandwidthOut: UInt64,
		lastMessageReceived: TimeInterval,
		visibleLineCount: Int,
		usesDarkSidebar: Bool
	) {
		self.messagesSent = messagesSent
		self.messagesReceived = messagesReceived
		self.bandwidthIn = bandwidthIn
		self.bandwidthOut = bandwidthOut
		self.lastMessageReceived = lastMessageReceived
		self.visibleLineCount = visibleLineCount
		self.usesDarkSidebar = usesDarkSidebar
	}
}

public enum PluginMessageKind: UInt, Sendable {
	case other = 0
	case privateMessage
	case privateMessageNoHighlight
	case action
	case actionNoHighlight
	case notice
	case debug
}

public struct PluginSender: Equatable, Sendable {
	public var nickname: String
	public var username: String?
	public var address: String?
	public var hostmask: String
	public var isServer: Bool

	public init(
		nickname: String,
		username: String?,
		address: String?,
		hostmask: String,
		isServer: Bool
	) {
		self.nickname = nickname
		self.username = username
		self.address = address
		self.hostmask = hostmask
		self.isServer = isServer
	}
}

public struct PluginUser: Equatable, Sendable {
	public let nickname: String
	public let hostmask: String?
	public let address: String?
	public let isIRCop: Bool

	public init(nickname: String, hostmask: String?, address: String?, isIRCop: Bool) {
		self.nickname = nickname
		self.hostmask = hostmask
		self.address = address
		self.isIRCop = isIRCop
	}
}

public struct PluginChannelMember: Equatable, Sendable {
	public let user: PluginUser
	public let mark: String
	public let ranks: UserRank

	/// When the host first saw this member in the channel, in seconds since the
	/// 1970 epoch. Compare it with ``membershipAge`` rather than by hand: the
	/// other epoch is nearly a billion seconds away, and the difference is not
	/// one a wrong answer shows.
	public let creationTime: TimeInterval

	public init(user: PluginUser, mark: String, ranks: UserRank, creationTime: TimeInterval) {
		self.user = user
		self.mark = mark
		self.ranks = ranks
		self.creationTime = creationTime
	}

	public var isHalfOperator: Bool {
		ranks.contains(.halfOperator) || ranks.contains(.normalOperator) || ranks.contains(.superOperator) ||
			ranks.contains(.channelOwner)
	}

	/// How long this member has been in the channel, in seconds.
	public var membershipAge: TimeInterval {
		Date().timeIntervalSince1970 - creationTime
	}
}

/// A snapshot of one IRC conversation, plus the operations a plugin may run
/// against it. The operations reach live app models, so the type is bound to
/// the main actor.
@MainActor
public final class PluginChannel: Hashable {
	public let identifier: String
	public let name: String
	public let type: ChannelType
	public let isActive: Bool
	public let members: [PluginChannelMember]

	private let autoJoinReader: () -> Bool
	private let autoJoinWriter: (Bool) -> Void
	private let deactivation: () -> Void

	public init(
		identifier: String,
		name: String,
		type: ChannelType,
		isActive: Bool,
		members: [PluginChannelMember],
		autoJoin: @escaping () -> Bool,
		setAutoJoin: @escaping (Bool) -> Void,
		deactivate: @escaping () -> Void
	) {
		self.identifier = identifier
		self.name = name
		self.type = type
		self.isActive = isActive
		self.members = members
		autoJoinReader = autoJoin
		autoJoinWriter = setAutoJoin
		deactivation = deactivate
	}

	public var isChannel: Bool {
		type == .channel
	}

	public var isPrivateMessage: Bool {
		type == .privateMessage
	}

	public var isUtility: Bool {
		type == .utility
	}

	public var autoJoin: Bool {
		get { autoJoinReader() }
		set { autoJoinWriter(newValue) }
	}

	public func member(named nickname: String) -> PluginChannelMember? {
		members.first { $0.user.nickname.caseInsensitiveCompare(nickname) == .orderedSame }
	}

	public func deactivate() {
		deactivation()
	}

	public nonisolated static func == (lhs: PluginChannel, rhs: PluginChannel) -> Bool { // nonisolated: pure
		lhs.identifier == rhs.identifier
	}

	public nonisolated func hash(into hasher: inout Hasher) { // nonisolated: pure
		hasher.combine(identifier)
	}
}

public struct PluginPrintResult: Equatable, Sendable {
	public let isHighlight: Bool

	public init(isHighlight: Bool) {
		self.isHighlight = isHighlight
	}
}

/// A snapshot of one IRC connection, plus the operations a plugin may run
/// against it. Bound to the main actor for the same reason as `PluginChannel`.
@MainActor
public final class PluginClient: Hashable {
	public let identifier: String
	public let userNickname: String
	public let networkName: String?
	public let serverAddress: String?
	public let isConnected: Bool
	public let isLoggedIn: Bool
	public let isIRCop: Bool
	public let localUser: PluginUser?
	public let channels: [PluginChannel]
	public let isConnectedToZNC: Bool
	public let zncCertificateChainData: Data?
	public let maximumNicknameLength: UInt

	private let nicknameMatcher: (String, String) -> Bool
	private let channelNameValidator: (String) -> Bool
	private let channelFinder: (String) -> PluginChannel?
	private let privateMessageProvider: (String) -> PluginChannel?
	private let utilityChannelProvider: (String) -> PluginChannel?
	private let capabilityReader: (UInt) -> Bool
	private let debugPrinter: (String, PluginChannel?) -> Void
	private let privateMessageSender: (String, PluginChannel) -> Void
	private let commandSender: (String) -> Void
	private let lineSender: (String) -> Void
	private let channelJoiner: (String) -> Void
	private let messagePrinter: (
		String,
		String?,
		PluginChannel,
		PluginMessageKind,
		String,
		Date,
		Bool,
		@escaping (PluginPrintResult) -> Void
	) -> Void
	private let unreadMarker: (PluginChannel, Bool) -> Void
	private let highlightMarker: (PluginChannel) -> Void
	private let sidebarRefresher: () -> Void

	public init(
		identifier: String,
		userNickname: String,
		networkName: String?,
		serverAddress: String?,
		isConnected: Bool,
		isLoggedIn: Bool,
		isIRCop: Bool,
		localUser: PluginUser?,
		channels: [PluginChannel],
		isConnectedToZNC: Bool,
		zncCertificateChainData: Data?,
		maximumNicknameLength: UInt,
		nicknameMatchesZNCUser: @escaping (String, String) -> Bool,
		isChannelName: @escaping (String) -> Bool,
		findChannel: @escaping (String) -> PluginChannel?,
		privateMessage: @escaping (String) -> PluginChannel?,
		utilityChannel: @escaping (String) -> PluginChannel?,
		isCapabilityEnabled: @escaping (UInt) -> Bool,
		printDebug: @escaping (String, PluginChannel?) -> Void,
		sendPrivateMessage: @escaping (String, PluginChannel) -> Void,
		sendCommand: @escaping (String) -> Void,
		sendLine: @escaping (String) -> Void,
		joinChannel: @escaping (String) -> Void,
		printMessage: @escaping (
			String,
			String?,
			PluginChannel,
			PluginMessageKind,
			String,
			Date,
			Bool,
			@escaping (PluginPrintResult) -> Void
		) -> Void,
		markUnread: @escaping (PluginChannel, Bool) -> Void,
		markHighlight: @escaping (PluginChannel) -> Void,
		refreshSidebar: @escaping () -> Void
	) {
		self.identifier = identifier
		self.userNickname = userNickname
		self.networkName = networkName
		self.serverAddress = serverAddress
		self.isConnected = isConnected
		self.isLoggedIn = isLoggedIn
		self.isIRCop = isIRCop
		self.localUser = localUser
		self.channels = channels
		self.isConnectedToZNC = isConnectedToZNC
		self.zncCertificateChainData = zncCertificateChainData
		self.maximumNicknameLength = maximumNicknameLength
		nicknameMatcher = nicknameMatchesZNCUser
		channelNameValidator = isChannelName
		channelFinder = findChannel
		privateMessageProvider = privateMessage
		utilityChannelProvider = utilityChannel
		capabilityReader = isCapabilityEnabled
		debugPrinter = printDebug
		privateMessageSender = sendPrivateMessage
		commandSender = sendCommand
		lineSender = sendLine
		channelJoiner = joinChannel
		messagePrinter = printMessage
		unreadMarker = markUnread
		highlightMarker = markHighlight
		sidebarRefresher = refreshSidebar
	}

	public func nickname(_ nickname: String, isZNCUser zncNickname: String) -> Bool {
		nicknameMatcher(nickname, zncNickname)
	}

	public func isChannelName(_ value: String) -> Bool {
		channelNameValidator(value)
	}

	public func channel(named name: String) -> PluginChannel? {
		channelFinder(name)
	}

	public func privateMessage(named name: String) -> PluginChannel? {
		privateMessageProvider(name)
	}

	public func utilityChannel(named name: String) -> PluginChannel? {
		utilityChannelProvider(name)
	}

	public func isCapabilityEnabled(rawValue: UInt) -> Bool {
		capabilityReader(rawValue)
	}

	public func printDebug(_ message: String, in channel: PluginChannel? = nil) {
		debugPrinter(message, channel)
	}

	public func sendPrivateMessage(_ message: String, to channel: PluginChannel) {
		privateMessageSender(message, channel)
	}

	public func sendCommand(_ command: String) {
		commandSender(command)
	}

	public func sendLine(_ line: String) {
		lineSender(line)
	}

	public func joinChannel(named name: String) {
		channelJoiner(name)
	}

	public func print(
		_ message: String,
		authoredBy nickname: String?,
		in channel: PluginChannel,
		as kind: PluginMessageKind,
		command: String,
		receivedAt: Date = Date(),
		isEncrypted: Bool = false,
		completion: @escaping (PluginPrintResult) -> Void = { _ in }
	) {
		messagePrinter(message, nickname, channel, kind, command, receivedAt, isEncrypted, completion)
	}

	public func markUnread(_ channel: PluginChannel, isHighlight: Bool = false) {
		unreadMarker(channel, isHighlight)
	}

	public func markHighlight(_ channel: PluginChannel) {
		highlightMarker(channel)
	}

	public func refreshSidebar() {
		sidebarRefresher()
	}

	public nonisolated static func == (lhs: PluginClient, rhs: PluginClient) -> Bool { // nonisolated: pure
		lhs.identifier == rhs.identifier
	}

	public nonisolated func hash(into hasher: inout Hasher) { // nonisolated: pure
		hasher.combine(identifier)
	}
}

/// One parsed line of server input handed to interceptors.
///
/// A value: an interceptor edits its own copy and returns it, so no plugin can
/// mutate a message another plugin is still reading.
public struct PluginServerMessage: Equatable, Sendable {
	public var sender: PluginSender
	public var command: String
	public var parameters: [String]
	public var isPrintOnlyMessage: Bool

	public init(
		sender: PluginSender,
		command: String,
		parameters: [String],
		isPrintOnlyMessage: Bool
	) {
		self.sender = sender
		self.command = command
		self.parameters = parameters
		self.isPrintOnlyMessage = isPrintOnlyMessage
	}
}
