// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/* Portions of the SASL implementation originated in Colloquy's Chat Core.
 Copyright © 2000 - 2012 the Colloquy IRC Client. Redistribution is permitted
 under the three-clause BSD license reproduced in Acknowledgements.pdf. */

struct ServerSessionConfigWasUpdated: SubjectMessage {
	typealias Subject = ServerSession

	nonisolated static let name = Notification.Name("Glasstual.serverSessionConfigWasUpdated")

	let subject: ServerSession
}

struct ServerSessionConversationListWasModified: SubjectMessage {
	typealias Subject = ServerSession

	nonisolated static let name = Notification.Name("Glasstual.serverSessionConversationListWasModified")

	let subject: ServerSession
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
		dispatchIncomingMessage(message)
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

	/// The server the user allowed to receive the account password although its
	/// certificate was not checked. Kept beside the credentials rather than in
	/// them, which every connect clears: the answer holds for as long as the
	/// session talks to that host and port.
	var credentialConsent: CredentialConsent?

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
	/// Which server the next connect dials, and which one this connection dialled.
	var endpoints = EndpointSelection()
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
			/* A registration that holds is the only evidence the endpoint is
			 usable, so teardown clears the reconnect backoff from this time.
			 Clearing it on connecting or on 001 would let a server that drops
			 the connection around registration be retried every twenty seconds. */
			reconnect.registeredAt = isLoggedIn ? ProcessInfo.processInfo.systemUptime : nil
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

	/// Who the server says this connection is.
	var identity = SessionIdentity()
	/// Whether the user is present, and the nickname and message that stand in
	/// for them while they are not.
	var away = AwayStatus()
	/// What the network's nickname service has made of this session.
	var nickServ = NickServIdentification()
	var lastMessageServerTime: TimeInterval = 0 {
		didSet { markConfigurationStaleIfChanged(from: oldValue, to: lastMessageServerTime) }
	}

	/// The nickname the server assigned, or the configured one before it has.
	var userNickname: String {
		get { identity.assignedNickname ?? config.nickname }
		set { identity.assignedNickname = newValue }
	}

	/** Several features install a post-disconnect action (reconnect, destroy-after-quit,
	 STS upgrade, server redirect). A single slot meant whichever installed last silently
	 replaced the others; every registered action now runs. */
	var disconnectCallbacks: [() -> Void] = []
	/// Delayed work the session started and must be able to cancel.
	var scheduled = SessionScheduledWork()
	var credentialLoader: @Sendable ([KeychainItem]) async -> [KeychainItem: String] = {
		await KeychainSecretLoader.passwords(for: $0)
	}

	var startup = StartupState()

	/// Paces the settling delay after connect commands; tests step their own.
	var startupClock = TimerClock.continuous
	/// Paces the reaping of users who share no channel; tests step their own.
	var userRemovalClock = TimerClock.continuous
	/// The scripts this session started that are still running.
	let scriptTasks = ScriptTaskBag()
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
	/// An account registration on this connection, beside the SASL exchange.
	var accountRegistration = AccountRegistrationSession()
	/// What `draft/metadata-2` keeps for this connection besides the profiles.
	var metadata = MetadataSession()
	var sts = STSUpgradeState()
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
	var whoisReply: WhoisReply?
	var conversationListPrivate: [Conversation] = []
	/** `findConversation(_:)` sits on the path of nearly every inbound line, so the
	 conversation list is mirrored by casefolded name. The mirror is rebuilt
	 whenever the list or a conversation's configuration changes; a lookup still
	 verifies its hit. A miss is only trusted while the index was folded under
	 the CASEMAPPING now in force; names change only through paths that
	 rebuild it. */
	var conversationIndex = ConversationNameIndex()
	weak var lastSelectedConversation: Conversation?
	/** The conversation the reader typed the command being carried out in, for
	 as long as it is being carried out and no longer.

	 A question that command raises appears there, where the reader is
	 looking; one the server raises later has no command behind it and
	 appears where it always did. */
	weak var commandConversation: Conversation?
	let addressBookMatchCache = AddressBookMatchCache()
	/// The netsplit or netjoin batch being collapsed into one summary line, and
	/// the nicknames it has named so far.
	var netsplitCollapse = NetsplitCollapse()
	/// The bouncer session, when the server on the other end is a ZNC.
	var znc = ZNCSession()
	/// What the connection knows about soju's bouncer networks.
	var bouncer = BouncerSession()
	var successfulConnects: UInt = 0
	/// ISON and WHO polling for tracked users and away status.
	var presencePolling: PresencePolling
	/// The channels waiting to be joined, and the pacing they are joined at.
	var autojoin: AutojoinSchedule
	/// When the server was last heard from, and the PING timer that watches it.
	var liveness: ConnectionLiveness
	let retryTimer: SessionTimer
	let requestedCommands = SessionRequestedCommands()
	var rawDataLogConsole: Conversation?
	var hiddenCommandResponsesConsole: Conversation?
	lazy var typingTracker = TypingTracker(session: self)
	lazy var typingSender = TypingSender(session: self)
	var replies = PendingReplies()
	/// The chat history this session has asked for and is still waiting on.
	var chatHistory = ChatHistorySession()
	let batchMessages = MessageBatchContainer()
	/// Where each conversation's read marker has got to.
	var readMarkers: ReadMarkerTracker
	private let notifications = NotificationSubscriptions()
	/// The messages whose labelled answer has not arrived yet.
	var labeledResponses = LabeledResponseRegistry()
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
	/// The questions about DCC connections waiting on the user.
	var dccDecisions = DCCPendingDecisions()
	/// The packs this connection asked XDCC bots for and is waiting on. The
	/// file-transfer window lists them, so it hears of every change.
	var xdccRequests = XDCCRequestLedger() {
		didSet {
			fileTransfers?.xdccRequestsDidChange(on: self)
		}
	}

	/// Messages sent without a local print, whose echo is dropped rather than shown.
	var unprintedEchoes = UnprintedEchoRegistry()
	/// How far this connection has got with registering.
	var registration = ConnectionRegistration()

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
		presencePolling = PresencePolling(
			isonTimer: timerOwner.makeTimer { $0.onISONTimer() },
			whoTimer: timerOwner.makeTimer { $0.onWhoTimer() }
		)
		liveness = ConnectionLiveness(pongTimer: timerOwner.makeTimer { $0.onPongTimer() })
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
		scheduled.cancelAll()
		outboundTextProducer?.cancel()
		notifications.cancelAll()
		[
			autojoin.timer, autojoin.delayedWarningTimer,
			presencePolling.isonTimer, liveness.pongTimer, reconnect.timer, retryTimer, presencePolling.whoTimer, readMarkers.timer,
			sasl.timeoutTimer,
		].forEach { timer in timer.stop() }
		startup.cancel()
		scriptTasks.cancelAll()
		presencePolling.populationTask?.stop()
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
