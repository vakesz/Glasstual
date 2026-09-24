// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/* Portions of the SASL implementation originated in Colloquy's Chat Core.
 Copyright © 2000 - 2012 the Colloquy IRC Client. Redistribution is permitted
 under the three-clause BSD license reproduced in Acknowledgements.pdf. */

extension Notification.Name {
	static let serverSessionConfigWasUpdated = Self("Glasstual.serverSessionConfigWasUpdated")
	static let serverSessionConversationListWasModified = Self("Glasstual.serverSessionConversationListWasModified")
	static let serverSessionWillConnect = Self("Glasstual.serverSessionWillConnect")
	static let serverSessionDidConnect = Self("Glasstual.serverSessionDidConnect")
	static let serverSessionWillSendQuit = Self("Glasstual.serverSessionWillSendQuit")
	static let serverSessionWillDisconnect = Self("Glasstual.serverSessionWillDisconnect")
	static let serverSessionDidDisconnect = Self("Glasstual.serverSessionDidDisconnect")
	nonisolated static let serverSessionUserNicknameChanged = Self("Glasstual.serverSessionUserNicknameChanged")
}

class ServerSession: ChatItem {
	#if DEBUG
		var linePrintObserver: ((LinePrintRequest) -> Void)?
	#endif

	/* The three seams a test double replaces live in the class body rather than
	 in the extensions that hold the rest of the transport and dispatch, because
	 Swift only dispatches a class-body method through the vtable. */

	/// Writes one already-framed line to the server.
	func sendLine(_ line: String) {
		guard isConnected else {
			printDebugInformation(toConsole: String(localized: .IRC.failedToSendDataToServer))
			return
		}

		socket?.sendLine(line)
		chatSession?.noteMessageSent(length: UInt(line.count))
	}

	/// Sends one `CAP` subcommand, with its argument when the subcommand takes
	/// one.
	func sendCapability(_ subcommand: String, data: String?) {
		guard isConnected else { return }

		var arguments = [subcommand]

		if let data {
			arguments.append(data)
		}

		send(.cap, arguments: arguments)
	}

	/// Hands one parsed message to the inbound state machine.
	func processIncomingMessage(_ message: Message) {
		processIncomingMessageOnMainActor(message)
	}

	var config: ServerConfig {
		didSet {
			if oldValue.uniqueIdentifier != config.uniqueIdentifier {
				sessionCredentials.forget()
			}
			sessionCredentials.apply(config.pendingKeychainEdits)
		}
	}

	var sessionCredentials = SessionCredentials()

	lazy var supportInfo = ISupport()
	/** The ISUPPORT prefix and case-mapping values as they stand now.

	 A member is stamped with a copy when the list creates or edits one, because
	 a member does not know its session and ranks, compares and marks itself on
	 the printing queue: what crosses that boundary is the `Sendable` table
	 value, never the table `supportInfo` keeps. */
	var currentUserPrefixes: UserPrefixTable {
		supportInfo.userPrefixes
	}

	var cachedHighlights: [HighlightRecord] = []
	/// The endpoint this connection selected, while it lasts.
	var server: ServerEndpoint?
	/** Keychain items belonging to endpoints the user deleted while the session
	 was still connected to one of them. They are removed once the connection
	 ends, so the live connection keeps its password until then. */
	var retiredServerKeychainItems: Set<KeychainItem> = []
	var connectionState = SessionConnectionState()
	var isConnecting: Bool {
		connectionState.isConnecting
	}

	var isConnected: Bool {
		connectionState.isConnected
	}

	/// KVO: `ServerChannelList` watches this through `publisher(for:)`
	/// to end a listing when the connection drops.
	@objc dynamic var isLoggedIn = false {
		didSet {
			/* Registration is the only evidence the endpoint is actually usable,
			 so it is what clears the reconnect backoff. Clearing it on a
			 successful socket connection would let a server that drops the
			 connection during registration be retried every twenty seconds. */
			if isLoggedIn {
				reconnect.attemptCount = 0
			}
			output?.updateMemberListVisibilityForSelection()
			chatSession?.noteLoginStateChanged()
		}
	}

	var isQuitting: Bool {
		connectionState.isQuitting
	}

	var isDisconnecting: Bool {
		connectionState.isDisconnecting
	}

	var userIsIRCop = false
	/// Whether the user is present, and the nickname and message that stand in
	/// for them while they are not.
	var away = AwayStatus()
	/// What the network's nickname service has made of this session.
	var nickServ = NickServIdentification()
	var lastMessageReceived: TimeInterval = 0
	var lastMessageServerTime: TimeInterval = 0 {
		didSet { markConfigurationStaleIfChanged(from: oldValue, to: lastMessageServerTime) }
	}

	var userHostmask: String?
	private var userNicknameStorage: String?
	var userNickname: String {
		get { userNicknameStorage ?? config.nickname }
		set { userNicknameStorage = newValue }
	}

	/// Forgets the nickname the server assigned, so `userNickname` falls back
	/// to the configured one. The property itself is not optional, so this
	/// cannot be expressed as an assignment through it.
	func forgetUserNickname() {
		userNicknameStorage = nil
	}

	/** Several features install a post-disconnect action (reconnect, destroy-after-quit,
	 STS upgrade, server redirect). A single slot meant whichever installed last silently
	 replaced the others; every registered action now runs. */
	var disconnectCallbacks: [() -> Void] = []
	/** Both delays are cancellable so that a reconnect inside the delay window
	 cannot have a stale block act on the new session. */
	var pendingDisconnectTask: Task<Void, Never>?
	var pendingConnectionTask: Task<Void, Never>?
	var credentialLoader: @Sendable ([KeychainItem]) async -> [KeychainItem: String] = {
		await KeychainSecretLoader.passwords(for: $0)
	}

	var startup = StartupState()
	var trackedUserPopulationTask: Task<Void, Never>?
	var rejoinTasks: [String: Task<Void, Never>] = [:]
	var pendingConfirmationTasks: [UUID: Task<Void, Never>] = [:]
	var renderAdmission = RenderAdmission()
	/// Member ordering and native-list presentation for one bounded inbound read
	/// turn. Lists enroll only when they change; protocol lookups remain immediate.
	private var inboundMemberPresentationLists: [ObjectIdentifier: ConversationMembers]?

	func beginInboundMemberPresentationUpdates() {
		precondition(inboundMemberPresentationLists == nil)
		inboundMemberPresentationLists = [:]
	}

	func finishInboundMemberPresentationUpdates() {
		guard let lists = inboundMemberPresentationLists else { return }
		inboundMemberPresentationLists = nil
		for list in lists.values {
			list.endPresentationUpdates()
		}
	}

	func deferMemberPresentation(_ list: ConversationMembers) {
		guard inboundMemberPresentationLists != nil else { return }
		let identifier = ObjectIdentifier(list)
		guard inboundMemberPresentationLists?[identifier] == nil else { return }
		inboundMemberPresentationLists?[identifier] = list
		list.beginInboundPresentationUpdates()
	}

	var outboundTextProducer: OutboundTextProducer?
	var connectType: SessionConnectMode = .normal
	var disconnectType: SessionDisconnectMode = .normal
	/// The whole of `CAP` negotiation: what the server offered, what is still
	/// outstanding, what it acknowledged, and the bitset those project onto.
	var capabilityNegotiation = CapabilityNegotiationState()
	/// What `capabilityNegotiation` projects onto: the acknowledged names plus
	/// the SASL and ISUPPORT facts. Read-only, because the negotiation is what
	/// decides it.
	var capabilities: CapabilitySet {
		capabilityNegotiation.capabilities
	}

	/// Capability names the server acknowledged, in the order they arrived.
	var enabledCapabilityNames: [String] {
		capabilityNegotiation.acknowledgedNames
	}

	var socket: Connection?
	/// The SASL exchange, from the mechanisms the server offered to the reply
	/// it is waiting on.
	var sasl: SASLSession
	var pendingEndpoint: PendingIRCEndpoint?
	var performedSTSUpgrade = false
	var sidebarItemIsExpanded = false {
		didSet { markConfigurationStaleIfChanged(from: oldValue, to: sidebarItemIsExpanded) }
	}

	/** Whether the session is on its way out, for good or for a relaunch.

	 Setting it is the one place the session's scheduled work is cancelled, so
	 no teardown path has to remember the list. Every one of them sets this
	 first and then does only what is its own. */
	var isTerminating = false {
		didSet {
			guard isTerminating else { return }
			cancelPendingSessionTasks()
			cancelDelayedDisconnect()
			reconnect.isEnabled = false
			reconnect.isEnabledForSleepMode = false
			stopAllTimers()
			removeTimedCommands()
			removeRequestedCommands()
		}
	}

	var terminationPostflightFinished = false
	var configurationIsStale = false
	var isPerformingConnectCommands: Bool {
		startup.commands == .dispatching
	}

	var didPerformConnectCommands: Bool {
		startup.commands == .settling || startup.commands == .ready
	}

	var connectCommandsHaveSettled: Bool {
		startup.commands == .ready
	}

	var isAutojoined: Bool {
		get { startup.joining == .completed }
		set {
			if newValue {
				startup.joining = .completed
			} else if startup.joining == .completed {
				startup.joining = .pending
			}
		}
	}

	var isAutojoining: Bool {
		get { startup.joining == .scheduled }
		set {
			if newValue {
				startup.joining = .scheduled
			} else if startup.joining == .scheduled {
				startup.joining = .pending
			}
		}
	}

	/// When and whether the session comes back after the connection ends.
	var reconnect: ReconnectSchedule
	var invokingISONCommandForFirstTime = false
	var inWhoisResponse = false
	var inWhowasResponse = false
	/// The index in `config.serverList` the last connect attempt dialled, or
	/// `nil` when none has been dialled yet.
	var lastServerSelected: UInt?
	/// Which alternate nickname registration is on, and the one it sent.
	var nicknameRetry = NicknameRetry()
	var conversationListPrivate: [Conversation] = []
	/** `findConversation(_:)` sits on the path of nearly every inbound line, so the
	 conversation list is mirrored by casefolded name. The mirror is rebuilt
	 whenever the list or a conversation's configuration changes; a lookup still
	 verifies its hit and falls back to a scan, because a rename or a new
	 CASEMAPPING can arrive without either. */
	var conversationIndex = CasefoldedIndex<Conversation>()
	weak var lastSelectedConversation: Conversation?
	let addressBookMatchCache = AddressBookMatchCache()
	/// The netsplit or netjoin batch being collapsed into one summary line, and
	/// the nicknames it has named so far.
	var netsplitCollapse = NetsplitCollapse()
	/// The bouncer session, when the server on the other end is a ZNC.
	var znc = ZNCSession()
	var successfulConnects: UInt = 0
	let isonTimer: SessionTimer
	let whoTimer: SessionTimer
	/// The channels waiting to be joined, and the pacing they are joined at.
	var autojoin: AutojoinSchedule
	let pongTimer: SessionTimer
	let retryTimer: SessionTimer
	let requestedCommands = SessionRequestedCommands()
	var rawDataLogConsole: Conversation?
	var hiddenCommandResponsesConsole: Conversation?
	var lastWhoRequestConversationListIndex: UInt = 0
	lazy var typingTracker = TypingTracker(session: self)
	var nextMessageReplyIdentifier: String?
	var nextLineDeliveryState: ChatLineDeliveryState = .none
	var nextLineReplyToMessageIdentifier: String?
	/// The chat history this session has asked for and is still waiting on.
	var chatHistory = ChatHistorySession()
	let batchMessages = MessageBatchContainer()
	/// Where each conversation's read marker has got to.
	var readMarkers: ReadMarkerTracker
	private let notifications = NotificationSubscriptions()
	/// The messages whose labelled answer has not arrived yet.
	var labeledResponses = LabeledResponseRegistry()
	/// The typing state last sent to the server, keyed by conversation identifier.
	var typingStateSent: [String: TypingState] = [:]
	/// When `.active` was last sent, keyed by conversation identifier.
	var typingActiveSentAt: [String: Date] = [:]
	/// The pending "paused" notification per conversation, keyed by identifier.
	var typingPauseTasks: [String: Task<Void, Never>] = [:]
	let trackedUsers = AddressBookUserTrackingContainer()
	/// Users the session has seen, keyed by their casefolded nickname.
	var userIndex = CasefoldedIndex<User>()
	/** The state that belongs to a person rather than to one `User` value: the
	 channels they are in, the away-message clock, the removal timer. Keyed by
	 identity so an edit or a rename keeps it. */
	var userStores: [User.ID: UserPersistentStore] = [:]
	/// Timed commands the user scheduled, keyed by their identifier.
	var timedCommandsByIdentifier: [String: TimedCommand] = [:]
	/// How many CTCP queries this connection has answered lately. Main-actor
	/// state on the session that answers them, so it goes when the session does.
	var ctcpReplyThrottle = CTCPReplyThrottle()
	/// How many unsolicited DCC offers this connection has taken lately.
	var dccOfferThrottle = DCCOfferThrottle()

	/** Settings and services this session reads instead of reaching for the
	 application's singletons. The chat session it belongs to keeps the setting half
	 current; a session made without one gets the live values and no window. */
	var environment: ChatEnvironment

	@available(*, unavailable, message: "Use init(config:) or init(configDictionary:)")
	override init() {
		fatalError("Unavailable")
	}

	convenience init(config: ServerConfig) {
		self.init(config: config, environment: .application)
	}

	init(config: ServerConfig, environment: ChatEnvironment) {
		/* Every timer the session owns is a `let`, so it exists for as long as the
		 session does and no path can read one before it is built. That means
		 building them before `super.init()`, where `self` cannot be captured yet,
		 so each action resolves its session through the box below once the
		 superclass has run. */
		let timerOwner = SessionTimerOwner()
		self.timerOwner = timerOwner
		isonTimer = timerOwner.makeTimer { $0.onISONTimer() }
		whoTimer = timerOwner.makeTimer { $0.onWhoTimer() }
		pongTimer = timerOwner.makeTimer { $0.onPongTimer() }
		retryTimer = timerOwner.makeTimer { $0.onRetryTimer() }
		readMarkers = ReadMarkerTracker(timer: timerOwner.makeTimer { $0.onReadMarkerTimer() })
		autojoin = AutojoinSchedule(
			timer: timerOwner.makeTimer { $0.onAutojoinTimer() },
			delayedWarningTimer: timerOwner.makeTimer { $0.onAutojoinDelayedWarningTimer() }
		)
		reconnect = ReconnectSchedule(timer: timerOwner.makeTimer { $0.onReconnectTimer() })
		sasl = SASLSession(timeoutTimer: timerOwner.makeTimer { $0.onSASLTimeoutTimer() })
		self.config = config
		self.environment = environment
		super.init()
		timerOwner.session = self
		writePasswordsToKeychain()
		lastMessageServerTime = config.lastMessageServerTime
	}

	/// Resolves the session for the timers built before `super.init()`.
	private let timerOwner: SessionTimerOwner

	isolated deinit {
		sasl.scramTask?.cancel()
		pendingDisconnectTask?.cancel()
		pendingConnectionTask?.cancel()
		outboundTextProducer?.cancel()
		notifications.cancelAll()
		[
			autojoin.timer, autojoin.delayedWarningTimer,
			isonTimer, pongTimer, reconnect.timer, retryTimer, whoTimer, readMarkers.timer,
			sasl.timeoutTimer,
		].forEach { timer in timer.stop() }
		startup.cancel()
		trackedUserPopulationTask?.cancel()
		rejoinTasks.values.forEach { $0.cancel() }
		pendingConfirmationTasks.values.forEach { $0.cancel() }
		labeledResponses.deadlineTask?.cancel()
	}

	override var uniqueIdentifier: String {
		config.uniqueIdentifier
	}

	override var name: String {
		config.connectionName
	}

	override var label: String {
		config.connectionName
	}

	override var isSession: Bool {
		true
	}

	override var isActive: Bool {
		isLoggedIn
	}

	override var associatedSession: ServerSession? {
		get { self }
		set {}
	}

	override var associatedConversation: Conversation? {
		nil
	}

	override var numberOfChildren: Int {
		Int(conversationCount)
	}

	/// The base declares the index as an `Int`, so a caller can name a position
	/// no child occupies; there is no conversation there either way.
	override func child(at index: Int) -> ChatItem? {
		UInt(exactly: index).flatMap(conversation(at:))
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

	/** Notes a change worth writing back and asks the chat session to write it.

	 `lastMessageServerTime` changes on every inbound line a modern network
	 sends, so this used to allocate a `Task` and take a main-actor hop per
	 message for work `savePeriodically()` then threw away. Both setters are
	 already on the main actor, so the call is direct. */
	private func markConfigurationStaleIfChanged<T: Equatable>(from oldValue: T, to newValue: T) {
		guard oldValue != newValue else { return }
		configurationIsStale = true
		environment.chatSession?.savePeriodically()
	}
}

enum SessionConnectMode: UInt, Sendable {
	case normal
	case retry
	case reconnect
}

enum SessionDisconnectMode: UInt, Sendable {
	case normal
	case computerSleep
	case badCertificate
	case reachabilityChange
	case serverRedirect

	/// What the console says the connection ended for.
	var reasonText: String {
		switch self {
		case .normal: String(localized: .IRC.miscellaneousMessagesRelatedDisconnected)
		case .computerSleep: String(localized: .IRC.disconnectedForSleepMode)
		case .badCertificate: String(localized: .IRC.disconnectedFromServerBecause)
		case .serverRedirect: String(localized: .IRC.disconnectedForServerRedirect)
		case .reachabilityChange: String(localized: .IRC.disconnectedFromServerBecauseTheInternet)
		@unknown default: String(localized: .IRC.miscellaneousMessagesRelatedDisconnected)
		}
	}
}

extension ServerSession {
	var networkName: String? {
		supportInfo.networkNameFormatted
	}

	var networkNameAlt: String {
		networkName ?? config.connectionName
	}

	var serverAddress: String? {
		supportInfo.serverAddress ?? socket?.config.serverAddress ?? server?.serverAddress
	}

	var isReconnecting: Bool {
		reconnect.timer.isActive
	}

	var isSecured: Bool {
		socket?.isSecured ?? false
	}

	var zncBouncerCertificateChainData: Data? {
		guard znc.isConnected,
		      znc.isSendingCertificateInfo == false,
		      let certificateData = znc.certificateChainText
		else { return nil }
		return certificateData.data(using: .ascii)
	}
}

/// The name questions a connection answers with its own ISUPPORT: whether a
/// name is the local user's, how the server folds it, and what kind of name
/// it is.
extension ServerSession {
	func messageIsFromMyself(_ message: Message) -> Bool {
		nicknameIsMyself(message.senderNickname ?? "")
	}

	func nicknameIsMyself(_ nickname: String) -> Bool {
		casefoldNickname(userNickname) == casefoldNickname(nickname)
	}

	func casefoldNickname(_ nickname: String) -> String {
		supportInfo.casefoldString(nickname)
	}

	func stringIsNickname(_ string: String) -> Bool {
		string.isHostmaskNickname(on: self) && string.isChannelName(on: self) == false
	}

	func stringIsChannelName(_ string: String) -> Bool {
		string.isChannelName(on: self)
	}

	func stringIsChannelNameOrZero(_ string: String) -> Bool {
		stringIsChannelName(string) || string == "0"
	}
}
