/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

@objc(IRCClient)
open class IRCClient: TreeItem, @MainActor ConnectionDelegate {
	#if DEBUG
		var linePrintObserver: ((IRCLinePrintRequest) -> Void)?
	#endif

	@objc public dynamic var config: IRCClientConfig {
		didSet { refreshDescription() }
	}

	@objc public dynamic lazy var supportInfo = IRCISupportInfo(client: self)
	/** The ISUPPORT prefix and case-mapping values, republished by `supportInfo`
	 whenever they change. Channel members rank, compare and mark themselves on
	 the printing queue and must not read the live table for them. */
	nonisolated let userPrefixes = Mutex(IRCUserPrefixTable())
	@objc public dynamic var cachedHighlights: [HighlightLogEntry] = []
	@objc public dynamic var server: Server?
	@objc public dynamic var isConnecting = false
	@objc public dynamic var isConnected = false {
		didSet { refreshDescription() }
	}

	@objc public dynamic var isLoggedIn = false {
		didSet { refreshDescription() }
	}

	@objc public dynamic var isQuitting = false
	@objc dynamic var isDisconnecting = false
	@objc public dynamic var userIsAway = false
	@objc public dynamic var userIsIRCop = false
	@objc public dynamic var userIsIdentifiedWithNickServ = false
	@objc public dynamic var isWaitingForNickServ = false
	@objc public dynamic var serverHasNickServ = false
	@objc public dynamic var lastMessageReceived: TimeInterval = 0
	@objc public dynamic var lastMessageServerTime: TimeInterval = 0 {
		didSet { markConfigurationStaleIfChanged(from: oldValue, to: lastMessageServerTime) }
	}

	@objc public dynamic var userHostmask: String?
	private var userNicknameStorage: String?
	@objc public dynamic var userNickname: String {
		get { userNicknameStorage ?? config.nickname }
		set { userNicknameStorage = newValue }
	}

	@objc public dynamic var preAwayUserNickname: String?
	/** Several features install a post-disconnect action (reconnect, destroy-after-quit,
	 STS upgrade, server redirect). A single slot meant whichever installed last silently
	 replaced the others; every registered action now runs. */
	var disconnectCallbacks: [() -> Void] = []
	/** Migrating these delays from -performSelector:afterDelay: to asyncAfter left them
	 uncancellable; the work items exist so that a reconnect within the delay window
	 does not have a stale block act on the new session. */
	var pendingDisconnectWorkItem: DispatchWorkItem?
	var pendingConnectionWorkItem: DispatchWorkItem?
	@objc public dynamic var connectType: IRCClientConnectMode = .normal
	@objc public dynamic var disconnectType: IRCClientDisconnectMode = .normal
	public var capabilities: ClientIRCv3SupportedCapability = []
	@objc dynamic var socket: Connection?
	var capabilityNegotiationIsPaused = false
	/// Capability names still waiting to be sent, in the order they were queued.
	var pendingCapabilityRequests: [String] = []
	/// Capability names the server acknowledged, in the order they arrived.
	var enabledCapabilityNames: [String] = []
	var offeredCapabilities: [String: [String]] = [:]
	/// Lowercased capability name to the exact spelling the server advertised.
	var offeredCapabilityNames: [String: String] = [:]
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
	@objc dynamic var sidebarItemIsExpanded = false {
		didSet { markConfigurationStaleIfChanged(from: oldValue, to: sidebarItemIsExpanded) }
	}

	var isTerminating = false
	var configurationIsStale = false
	var isPerformingConnectCommands = false
	@objc public dynamic var isAutojoined = false
	@objc public dynamic var isAutojoining = false
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
	@objc public dynamic weak var lastSelectedChannel: IRCChannel?
	var addressBookMatchCache: AddressBookMatchCache!
	var collapsedNetsplitBatch: Any?
	@objc public dynamic var isConnectedToZNC = false
	var successfulConnects: UInt = 0
	var isonTimer: TimerImplementation!
	var whoTimer: TimerImplementation!
	var autojoinTimer: TimerImplementation!
	var autojoinNextJoinTimer: TimerImplementation!
	var autojoinDelayedWarningTimer: TimerImplementation!
	var pongTimer: TimerImplementation!
	var reconnectTimer: TimerImplementation!
	var retryTimer: TimerImplementation!
	var autojoinDelayedWarningCount: UInt = 0
	var channelsToAutojoin: [IRCChannel]?
	var requestedCommands: ClientRequestedCommands!
	var rawDataLogQuery: IRCChannel?
	var hiddenCommandResponsesQuery: IRCChannel?
	var lastWhoRequestChannelListIndex: UInt = 0
	var typingTracker: TypingTracker!
	var nextMessageReplyIdentifier: String?
	var nextLineDeliveryState: TVCLogLineDeliveryState = .none
	var nextLineReplyToMessageIdentifier: String?
	var logFile: FileLogger?
	/** Whether a logging session banner has been written and not yet closed. A line
	 counter cannot express this: writing the banner is itself a write. */
	@objc public dynamic var logFileSessionIsOpen = false
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
	var readMarkerTimer: TimerImplementation!
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
	/// Timed commands the user scheduled, keyed by their identifier.
	var timedCommandsByIdentifier: [String: TimedCommand] = [:]

	@available(*, unavailable, message: "Use init(config:) or init(configDictionary:)")
	override public init() {
		fatalError("Unavailable")
	}

	@objc(initWithConfigDictionary:)
	@MainActor public convenience init(configDictionary: [String: Any]) {
		self.init(config: IRCClientConfig(dictionary: configDictionary))
	}

	@objc(initWithConfig:)
	@MainActor public init(config: IRCClientConfig) {
		self.config = config
		super.init()
		writePasswordsToKeychain()
		prepareInitialState()
	}

	isolated deinit {
		NotificationCenter.default.removeObserver(self)
		[
			autojoinTimer, autojoinNextJoinTimer, autojoinDelayedWarningTimer,
			isonTimer, pongTimer, reconnectTimer, retryTimer, whoTimer, readMarkerTimer,
		].forEach { $0?.stop() }
		NSObject.cancelPreviousPerformRequests(withTarget: self)
	}

	/** `NSObject.description` is nonisolated, so it cannot read the main-actor
	 configuration and support info the text is built from. The text is published
	 here instead whenever one of the values it names changes. */
	private let descriptionSnapshot = Mutex("<IRCClient>")

	override public nonisolated var description: String {
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

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(willDestroyChannel(_:)),
			name: .ircWorldWillDestroyChannel,
			object: nil
		)
	}

	private func makeTimer(_ action: @MainActor @escaping (IRCClient) -> Void) -> TimerImplementation {
		TimerImplementation.timer { [weak self] _ in
			Task { @MainActor [weak self] in
				guard let self else { return }
				action(self)
			}
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
		Task { @MainActor in
			NSObject.applicationController().world.savePeriodically()
		}
	}
}
