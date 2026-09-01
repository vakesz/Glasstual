/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
 *      Please see Acknowledgements.pdf for additional information.
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

/* Portions of the SASL implementation originated in Colloquy's Chat Core.
 Copyright © 2000 - 2012 the Colloquy IRC Client. Redistribution is permitted
 under the three-clause BSD license reproduced in Acknowledgements.pdf. */

import CocoaExtensions
import Foundation
import Synchronization

public extension Notification.Name {
	static let IRCClientConfigurationWasUpdated = Self("IRCClientConfigurationWasUpdatedNotification")
	static let IRCClientChannelListWasModified = Self("IRCClientChannelListWasModifiedNotification")
	static let IRCClientWillConnect = Self("IRCClientWillConnectNotification")
	static let IRCClientDidConnect = Self("IRCClientDidConnectNotification")
	static let IRCClientWillSendQuit = Self("IRCClientWillSendQuitNotification")
	static let IRCClientWillDisconnect = Self("IRCClientWillDisconnectNotification")
	static let IRCClientDidDisconnect = Self("IRCClientDidDisconnectNotification")
	static let IRCClientUserNicknameChanged = Self("IRCClientUserNicknameChangedNotification")
}

open class IRCClient: TreeItem, @MainActor ConnectionDelegate {
	#if DEBUG
		var linePrintObserver: ((IRCLinePrintRequest) -> Void)?
	#endif

	/* The three seams a test double replaces live in the class body rather than
	 in the extensions that hold the rest of the transport and dispatch, because
	 Swift only dispatches a class-body method through the vtable. They used to
	 be `@objc` in an extension, which made the override work through the
	 Objective-C runtime instead. */

	/// Writes one already-framed line to the server.
	public func sendLine(_ line: String) {
		guard isConnected else {
			printDebugInformation(toConsole: IRCTransportStrings.notConnected)
			return
		}

		socket?.sendLine(line)
		world?.noteMessageSent(length: UInt(line.count))
	}

	/// Sends one `CAP` subcommand, with its argument when the subcommand takes
	/// one.
	public func sendCapability(_ subcommand: String, data: String?) {
		guard isConnected else { return }

		var arguments = [subcommand]

		if let data {
			arguments.append(data)
		}

		send("CAP", arguments: arguments)
	}

	/// Hands one parsed message to the inbound state machine.
	public func processIncomingMessage(_ message: Message) {
		processIncomingMessageOnMainActor(message)
	}

	public var config: IRCClientConfig {
		didSet { refreshDescription() }
	}

	public lazy var supportInfo = IRCISupportInfo(client: self)
	/** The ISUPPORT prefix and case-mapping values, republished by `supportInfo`
	 whenever they change. Channel members rank, compare and mark themselves on
	 the printing queue and must not read the live table for them. */
	nonisolated let userPrefixes = Mutex(IRCUserPrefixTable()) // nonisolated: let

	/// The prefix table as it stands now. A member is stamped with it when the
	/// list creates or edits one, because a member does not know its client.
	nonisolated var currentUserPrefixes: IRCUserPrefixTable { // nonisolated: pure
		userPrefixes.withLock { $0 }
	}

	public var cachedHighlights: [HighlightLogEntry] = []
	/// The endpoint this connection selected, while it lasts.
	public var server: Server?
	/** Keychain items belonging to endpoints the user deleted while the client
	 was still connected to one of them. They are removed once the connection
	 ends, so the live connection keeps its password until then. */
	var retiredServerKeychainItems: Set<KeychainItem> = []
	public var isConnecting = false
	public var isConnected = false {
		didSet { refreshDescription() }
	}

	/// KVO: `PluginHostAdapter` watches this through `publisher(for:)` to tell
	/// plugins when a client finished registering.
	@objc public dynamic var isLoggedIn = false {
		didSet {
			refreshDescription()
			output?.updateMemberListVisibilityForSelection()
		}
	}

	public var isQuitting = false
	var isDisconnecting = false
	public var userIsAway = false
	public var userIsIRCop = false
	public var userIsIdentifiedWithNickServ = false
	public var isWaitingForNickServ = false
	public var serverHasNickServ = false
	public var lastMessageReceived: TimeInterval = 0
	public var lastMessageServerTime: TimeInterval = 0 {
		didSet { markConfigurationStaleIfChanged(from: oldValue, to: lastMessageServerTime) }
	}

	public var userHostmask: String?
	private var userNicknameStorage: String?
	public var userNickname: String {
		get { userNicknameStorage ?? config.nickname }
		set { userNicknameStorage = newValue }
	}

	/// Forgets the nickname the server assigned, so `userNickname` falls back
	/// to the configured one. The property itself is not optional, so this
	/// cannot be expressed as an assignment through it.
	func forgetUserNickname() {
		userNicknameStorage = nil
	}

	public var preAwayUserNickname: String?
	/** Several features install a post-disconnect action (reconnect, destroy-after-quit,
	 STS upgrade, server redirect). A single slot meant whichever installed last silently
	 replaced the others; every registered action now runs. */
	var disconnectCallbacks: [() -> Void] = []
	/** Both delays are cancellable so that a reconnect inside the delay window
	 cannot have a stale block act on the new session. */
	var pendingDisconnectTask: Task<Void, Never>?
	var pendingConnectionTask: Task<Void, Never>?
	/// The post-registration work the client used to schedule with
	/// `perform(_:afterDelay:)`: the ZNC autojoin retry, the first ISON sweep,
	/// and one rejoin per channel the server kicked us out of.
	var postRegistrationAutoJoinTask: Task<Void, Never>?
	var trackedUserPopulationTask: Task<Void, Never>?
	var rejoinTasks: [String: Task<Void, Never>] = [:]
	public var connectType: IRCClientConnectMode = .normal
	public var disconnectType: IRCClientDisconnectMode = .normal
	public var capabilities: ClientIRCv3SupportedCapability = []
	var socket: Connection?
	var capabilityNegotiationIsPaused = false
	/// Capability names still waiting to be sent, in the order they were queued.
	var pendingCapabilityRequests: [String] = []
	/// Capability names the server acknowledged, in the order they arrived.
	var enabledCapabilityNames: [String] = []
	var offeredCapabilities: [String: [String]] = [:]
	/// Lowercased capability name to the exact spelling the server advertised.
	var lastAwayMessage: String?
	var saslOfferedMechanisms: [String]?
	var saslScramClient: SCRAMClient?
	var saslIncomingPayload: String?
	var saslMechanism: String?
	var saslTriedMechanisms: [String] = []
	var temporaryServerAddressOverride: String?
	var temporaryServerPortOverride: UInt16 = 0
	var performedSTSUpgrade = false
	var forceSecuredConnectionOnNextConnect = false
	var sidebarItemIsExpanded = false {
		didSet { markConfigurationStaleIfChanged(from: oldValue, to: sidebarItemIsExpanded) }
	}

	var isTerminating = false
	var configurationIsStale = false
	var isPerformingConnectCommands = false
	public var isAutojoined = false
	public var isAutojoining = false
	var reconnectEnabledBecauseOfSleepMode = false
	var timeoutWarningShownToUser = false
	var invokingISONCommandForFirstTime = false
	var inWhoisResponse = false
	var inWhowasResponse = false
	var reconnectEnabled = false
	var connectDelay: UInt = 0
	var lastServerSelected = UInt(NSNotFound)
	var tryingNicknameNumber: UInt = 0
	var tryingNicknameSentNickname: String?
	var channelListPrivate: [IRCChannel] = []
	/** `findChannel(_:)` sits on the path of nearly every inbound line, so the
	 channel list is mirrored by casefolded name. The mirror is rebuilt whenever
	 the list or a channel's configuration changes; a lookup still verifies its
	 hit and falls back to a scan, because a rename or a new CASEMAPPING can
	 arrive without either. */
	var channelsByFoldedName: [String: IRCChannel] = [:]
	public weak var lastSelectedChannel: IRCChannel?
	var addressBookMatchCache: AddressBookMatchCache!
	var collapsedNetsplitBatch: Any?
	public var isConnectedToZNC = false
	var successfulConnects: UInt = 0
	var isonTimer: ClientTimer!
	var whoTimer: ClientTimer!
	var autojoinTimer: ClientTimer!
	var autojoinNextJoinTimer: ClientTimer!
	var autojoinDelayedWarningTimer: ClientTimer!
	var pongTimer: ClientTimer!
	var reconnectTimer: ClientTimer!
	var retryTimer: ClientTimer!
	var autojoinDelayedWarningCount: UInt = 0
	var channelsToAutojoin: [IRCChannel]?
	var requestedCommands: ClientRequestedCommands!
	var rawDataLogQuery: IRCChannel?
	var hiddenCommandResponsesQuery: IRCChannel?
	var lastWhoRequestChannelListIndex: UInt = 0
	var typingTracker: TypingTracker!
	var nextMessageReplyIdentifier: String?
	var nextLineDeliveryState: LogLineDeliveryState = .none
	var nextLineReplyToMessageIdentifier: String?
	var logFile: FileLogger?
	/** Whether a logging session banner has been written and not yet closed. A line
	 counter cannot express this: writing the banner is itself a write. */
	public var logFileSessionIsOpen = false
	var chatHistoryPrependChannel: IRCChannel?
	var chatHistoryPrependedLines: [LogLine]?
	var batchMessages: MessageBatchContainer!
	/// Casefolded targets whose history request the server refused.
	var chatHistoryFailedTargets: Set<String> = []
	/// Casefolded targets with a history request in flight.
	var chatHistoryPendingBeforeTargets: Set<String> = []
	/// The newest read marker sent per channel, keyed by channel identifier.
	var readMarkerSentDates: [String: Date] = [:]
	var readMarkerPendingChannels: [IRCChannel] = []
	var readMarkerTimer: ClientTimer!
	private let notifications = NotificationSubscriptions()
	/// Nicknames seen in the netsplit batch being collapsed, per channel
	/// identifier, in the order they arrived.
	var collapsedNetsplitNicknames: [String: [String]]?
	var pendingDeliveries: [String: LabeledDelivery] = [:]
	var labelForBatchToken: [String: String] = [:]
	var labelCounter: UInt = 0
	var zncBouncerIsSendingCertificateInfo = false
	var zncBouncerIsPlayingBackHistory = false
	var zncBouncerCertificateChainDataMutable: String?
	/// The typing state last sent to the server, keyed by channel identifier.
	var typingStateSent: [String: TypingState] = [:]
	/// When `.active` was last sent, keyed by channel identifier.
	var typingActiveSentAt: [String: Date] = [:]
	/// The pending "paused" notification per channel, keyed by identifier.
	var typingPauseTasks: [String: Task<Void, Never>] = [:]
	var trackedUsers: AddressBookUserTrackingContainer!
	/// Users the client has seen, keyed by their casefolded nickname.
	var usersByNickname: [String: User] = [:]
	/** The state that belongs to a person rather than to one `User` value: the
	 channels they are in, the away-message clock, the removal timer. Keyed by
	 identity so an edit or a rename keeps it. */
	var userStores: [User.ID: UserPersistentStore] = [:]
	/// Timed commands the user scheduled, keyed by their identifier.
	var timedCommandsByIdentifier: [String: TimedCommand] = [:]

	/** Preferences and services this client reads instead of reaching for the
	 application's singletons. The world it belongs to keeps the preference half
	 current; a client made without one gets the live values and no window.

	 Behind a lock because the preference values are read from the printing and
	 connection queues while the main actor republishes them. */
	private nonisolated let environmentStorage: Mutex<ClientEnvironment> // nonisolated: let

	nonisolated var environment: ClientEnvironment { // nonisolated: pure
		get { environmentStorage.withLock { $0 } }
		set { environmentStorage.withLock { $0 = newValue } }
	}

	@available(*, unavailable, message: "Use init(config:) or init(configDictionary:)")
	override public init() {
		fatalError("Unavailable")
	}

	@MainActor public convenience init(config: IRCClientConfig) {
		self.init(config: config, environment: .shared)
	}

	@MainActor init(config: IRCClientConfig, environment: ClientEnvironment) {
		self.config = config
		environmentStorage = Mutex(environment)
		super.init()
		writePasswordsToKeychain()
		prepareInitialState()
	}

	isolated deinit {
		notifications.cancelAll()
		[
			autojoinTimer, autojoinNextJoinTimer, autojoinDelayedWarningTimer,
			isonTimer, pongTimer, reconnectTimer, retryTimer, whoTimer, readMarkerTimer,
		].forEach { $0?.stop() }
		postRegistrationAutoJoinTask?.cancel()
		trackedUserPopulationTask?.cancel()
		rejoinTasks.values.forEach { $0.cancel() }
	}

	/** `NSObject.description` is nonisolated, so it cannot read the main-actor
	 configuration and support info the text is built from. The text is published
	 here instead whenever one of the values it names changes. */
	private let descriptionSnapshot = Mutex("<IRCClient>")

	override public nonisolated var description: String { // nonisolated: pure
		descriptionSnapshot.withLock { $0 }
	}

	/// Republishes the text `description` returns.
	func refreshDescription() {
		let text = "<IRCClient [\(networkNameAlt)]: \(serverAddress ?? "(null)")>"
		descriptionSnapshot.withLock { $0 = text }
	}

	override public var uniqueIdentifier: String {
		config.uniqueIdentifier
	}

	override public var name: String {
		config.connectionName
	}

	override public var label: String {
		config.connectionName
	}

	override public var isClient: Bool {
		true
	}

	override public var isActive: Bool {
		isLoggedIn
	}

	override public var associatedClient: IRCClient! {
		get { self }
		set {}
	}

	override public var associatedChannel: IRCChannel? {
		nil
	}

	override public var numberOfChildren: Int {
		Int(channelCount)
	}

	override public func child(at index: Int) -> TreeItem? {
		channel(at: UInt(index))
	}

	@MainActor func prepareInitialState() {
		batchMessages = MessageBatchContainer()
		typingTracker = TypingTracker(client: self)
		addressBookMatchCache = AddressBookMatchCache(client: self)
		trackedUsers = AddressBookUserTrackingContainer(client: self)
		requestedCommands = ClientRequestedCommands()
		lastMessageServerTime = config.lastMessageServerTime
		refreshDescription()

		autojoinTimer = makeTimer { $0.onAutojoinTimer() }
		autojoinNextJoinTimer = makeTimer { $0.onAutojoinNextJoinTimer() }
		autojoinDelayedWarningTimer = makeTimer { $0.onAutojoinDelayedWarningTimer() }
		isonTimer = makeTimer { $0.onISONTimer() }
		reconnectTimer = makeTimer { $0.onReconnectTimer() }
		retryTimer = makeTimer { $0.onRetryTimer() }
		pongTimer = makeTimer { $0.onPongTimer() }
		whoTimer = makeTimer { $0.onWhoTimer() }
		readMarkerTimer = makeTimer { $0.onReadMarkerTimer() }
	}

	private func makeTimer(_ action: @MainActor @escaping (IRCClient) -> Void) -> ClientTimer {
		ClientTimer { [weak self] _ in
			guard let self else { return }
			action(self)
		}
	}

	/// Registers an action to run once the current connection has finished closing.
	func addDisconnectCallback(_ callback: @escaping () -> Void) {
		disconnectCallbacks.append(callback)
	}

	/// Runs and clears every registered post-disconnect action.
	func invokeDisconnectCallbacks() {
		let callbacks = disconnectCallbacks
		disconnectCallbacks.removeAll()

		for callback in callbacks {
			callback()
		}
	}

	private func markConfigurationStaleIfChanged<T: Equatable>(from oldValue: T, to newValue: T) {
		guard oldValue != newValue else { return }
		configurationIsStale = true
		Task { @MainActor [environment] in
			environment.world?.savePeriodically()
		}
	}
}
