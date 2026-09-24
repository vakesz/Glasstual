// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os
import Security

private nonisolated let connectionLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "Connection"
)

/** Everything the connection host reports. NSXPC delivers these on its own
 queue; they are drained on the main actor in arrival order so that the session
 sees them in wire order. */
private enum ConnectionEvent: Sendable {
	case willConnectToProxy(host: String, port: UInt16)
	case didConnect(host: String?)
	case didSecure(protocolType: tls_protocol_version_t, cipherSuite: tls_ciphersuite_t)
	case didCloseReadStream
	case didDisconnect(error: Error?)
	/// One read's lines, and the reply that lets the host read the next.
	case didReceive([Data], acknowledge: @Sendable () -> Void)
	case requestInsecureCertificateTrust(TrustDecisionHandler)
	case willSend(Data)
	case didSendData
	case serviceFailed(Error)
	case serviceInterrupted
	case serviceInvalidated
}

/** The object NSXPC exports for the host's callbacks.

 `RemoteConnectionClientProtocol` refines `Sendable` so the connection host can
 push through the proxy from inside its actor. That makes every conformer
 `Sendable`, which `Connection` — main-actor state, and plenty of it — cannot
 be, so the conformance lives on this instead. It holds nothing but the event
 continuation and hands every callback straight to it. */
private final class ConnectionClientShim: NSObject, RemoteConnectionClientProtocol {
	private let events: AsyncStream<ConnectionEvent>.Continuation

	init(events: AsyncStream<ConnectionEvent>.Continuation) {
		self.events = events

		super.init()
	}

	/* Every callback below arrives on the NSXPC queue. They only hand the value
	 to `events`; the main actor does the work, in the order the host sent it. */

	func willConnect(toProxy proxyHost: String, port proxyPort: UInt16) {
		events.yield(.willConnectToProxy(host: proxyHost, port: proxyPort))
	}

	func didConnect(toHost host: String?) {
		events.yield(.didConnect(host: host))
	}

	func didSecureConnection(
		withProtocolType protocolType: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t
	) {
		events.yield(.didSecure(protocolType: protocolType, cipherSuite: cipherSuite))
	}

	func didCloseReadStream() {
		events.yield(.didCloseReadStream)
	}

	func didDisconnect(withError disconnectError: Error?) {
		events.yield(.didDisconnect(error: disconnectError))
	}

	func didReceive(_ lines: [Data], acknowledge: @escaping @Sendable () -> Void) {
		events.yield(.didReceive(lines, acknowledge: acknowledge))
	}

	func requestInsecureCertificateTrust(_ trustBlock: @escaping TrustDecisionHandler) {
		events.yield(.requestInsecureCertificateTrust(trustBlock))
	}

	func willSend(_ data: Data) {
		events.yield(.willSend(data))
	}

	func didSendData() {
		events.yield(.didSendData)
	}
}

/** Owned by `ServerSession` on the main actor. The connection host's callbacks
 arrive on an NSXPC queue and are forwarded through `events`, which the main
 actor drains in order; nothing else on this type is touched off-main. */
final class Connection {
	private(set) weak var session: ServerSession?
	private(set) var config: ConnectionConfig
	private(set) var isConnected = false
	private(set) var isConnectedWithClientSideCertificate = false
	private(set) var isConnecting = false
	private(set) var isDisconnecting = false
	private(set) var isSecured = false
	private(set) var certificateTrustWasOverridden = false

	/// Whether TLS is established *and* the server's chain validated on its own.
	///
	/// Distinct from ``isSecured``, which is also true when the user clicked
	/// through the trust panel or the connection is configured to skip chain
	/// validation. Anything that outlives the connection — an STS policy, for
	/// instance — has to key on this instead.
	var isSecuredWithValidatedCertificate: Bool {
		isSecured
			&& certificateTrustWasOverridden == false
			&& config.connectionShouldValidateCertificateChain
	}

	private(set) var EOFReceived = false
	private(set) var connectedAddress: String?
	private(set) var uniqueIdentifier: String

	/** The longest line this server carries, CR LF included.

	 `LINELEN` as 005 advertised it, and the RFC's 512 until one does — which is
	 also what a reconnect goes back to, because the next server has not said
	 anything yet. Everything upstream already sizes its text from the same
	 figure; this is where the assembled line is measured against it. */
	var maximumLineLength = ProtocolLimits.maximumBodyLength + ProtocolLimits.lineTerminatorLength

	/// The host's callbacks, in arrival order, on their way to the main actor.
	private nonisolated let events: AsyncStream<ConnectionEvent>
	private nonisolated let eventContinuation: AsyncStream<ConnectionEvent>.Continuation
	private nonisolated let clientShim: ConnectionClientShim
	private var eventTask: Task<Void, Never>?
	private let closeClock: TimerClock
	private let diagnostics: ConnectionDiagnostics
	private let recordTermination: (ConnectionTermination) -> Void
	private let makeService: () -> NSXPCConnection
	private var closeDeadlineTask: Task<Void, Never>?
	private var localCloseRequested = false
	/// Whether the disconnect has already been reported. Read by the files
	/// that carry the rest of `Connection`; only this one sets it.
	private(set) var terminal = false
	private var pendingStartupEvent: ConnectionDiagnostics.Event?
	private var recordedFirstJoin = false

	private var serviceConnection: NSXPCConnection?
	/// The object exported to the connection host, and the seam tests drive
	/// callbacks through without a live service.
	var callbackReceiver: any RemoteConnectionClientProtocol {
		clientShim
	}

	/// What answers a pending trust request once the user has decided. Stored
	/// here, and read and written only by ConnectionTrustPrompt.swift.
	var trustResponse: TrustDecisionHandler?

	convenience init(config: ConnectionConfig, onSession session: ServerSession) {
		self.init(config: config, onSession: session, closeClock: .continuous)
	}

	init(
		config: ConnectionConfig,
		onSession session: ServerSession,
		closeClock: TimerClock,
		recordTermination: @escaping (ConnectionTermination) -> Void = { $0.record() },
		makeService: @escaping () -> NSXPCConnection = {
			NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		}
	) {
		self.closeClock = closeClock
		diagnostics = config.diagnostics ?? ConnectionDiagnostics()
		self.recordTermination = recordTermination
		self.makeService = makeService
		self.session = session
		self.config = config
		uniqueIdentifier = UUID().uuidString
		(events, eventContinuation) = AsyncStream.makeStream()
		clientShim = ConnectionClientShim(events: eventContinuation)
		startDeliveringEvents()
	}

	isolated deinit {
		closeDeadlineTask?.cancel()
		serviceConnection?.invalidate()
		eventContinuation.finish()
		eventTask?.cancel()
	}

	/// Drains the host's callbacks on the main actor in the order they arrived.
	private func startDeliveringEvents() {
		eventTask = Task { [weak self, events] in
			for await event in events {
				guard let self else { return }
				if case let .didReceive(lines, acknowledge) = event {
					await receive(lines)
					/* Answered once the lines are handled, whatever became of
					 the connection meanwhile: the host is waiting on this reply
					 before it reads again. */
					acknowledge()
				} else {
					handle(event)
				}
			}
		}
	}

	/** Hands one read's lines to the session, in order.

	 The main actor is given back between every few lines so that a long burst —
	 a `/LIST`, a bouncer's playback — does not hold up drawing. Nothing arrives
	 behind the burst meanwhile: the host reads the next one only after the
	 acknowledgement. */
	private func receive(_ lines: [Data]) async {
		var batchingSession: ServerSession?
		defer { batchingSession?.finishInboundMemberPresentationUpdates() }

		for (index, line) in lines.enumerated() {
			guard let session else { return }
			/* A renderer at capacity must be allowed to drain. Finish the native
			 list snapshot before giving the main actor away. The same boundary is
			 used every 64 lines and before the host's acknowledgement. */
			if batchingSession == nil || !session.renderAdmission.hasCapacity {
				batchingSession?.finishInboundMemberPresentationUpdates()
				batchingSession = nil
				await session.renderAdmission.waitForCapacity()
			}
			guard !Task.isCancelled, terminal == false, session.socket === self else { return }
			if batchingSession == nil {
				session.beginInboundMemberPresentationUpdates()
				batchingSession = session
			}
			if let string = convertFromCommonEncoding(line) {
				session.connectionDidReceive(string)
			}
			if (index + 1).isMultiple(of: Self.linesPerTurn) {
				batchingSession?.finishInboundMemberPresentationUpdates()
				batchingSession = nil
				await Task.yield()
			}
		}
		batchingSession?.finishInboundMemberPresentationUpdates()
		batchingSession = nil
		await session?.renderAdmission.waitForCapacity()
	}

	/// How many lines are handled before the main actor is offered to other work.
	private static let linesPerTurn = 64

	private func handle(_ event: ConnectionEvent) {
		guard terminal == false, session?.socket === self else {
			if case let .requestInsecureCertificateTrust(response) = event {
				response(false)
			}
			return
		}
		switch event {
		case let .willConnectToProxy(host, port):
			session?.connectionWillConnect(toProxy: host, port: port)
		case let .didConnect(host):
			guard isDisconnecting == false else { return }
			connectedAddress = host
			isConnecting = false
			isConnected = true
			session?.connectionDidConnect()
		case let .didSecure(protocolType, cipherSuite):
			guard isDisconnecting == false else { return }
			isSecured = true
			isConnectedWithClientSideCertificate = config.identityClientSideCertificate != nil
			session?.connectionDidSecure(protocolType: protocolType, cipherSuite: cipherSuite)
		case .didCloseReadStream:
			EOFReceived = true
			session?.connectionDidCloseReadStream()
		case let .didDisconnect(error):
			didDisconnect(with: error, trigger: .hostDisconnect)
		case .didReceive:
			/* Delivered by `receive(_:)`, which the event loop awaits so that
			 the acknowledgement follows the last line. */
			break
		case let .requestInsecureCertificateTrust(response):
			openInsecureCertificateTrustPanel(response)
		case let .willSend(data):
			willWrite(data)
		case .didSendData:
			didWrite()
		case let .serviceFailed(error):
			didDisconnect(with: error, trigger: .serviceFailure)
		case .serviceInterrupted:
			handleServiceInvalidation(trigger: .serviceInterrupted)
		case .serviceInvalidated:
			handleServiceInvalidation(trigger: .serviceInvalidated)
		}
	}

	private func willWrite(_ data: Data) {
		guard let string = convertFromCommonEncoding(data) else { return }
		pendingStartupEvent = if StartupCommandPolicy.identifiesNickServOnWire(string) {
			.identificationWritten
		} else if !recordedFirstJoin, Message(line: string)?.remoteCommand == .join {
			.firstJoin
		} else {
			nil
		}
		session?.connectionWillSend(string)
	}

	private func didWrite() {
		if let event = pendingStartupEvent {
			config.diagnostics?.record(event)
			if event == .identificationWritten {
				session?.noteNickServIdentificationWritten()
			}
			if event == .firstJoin {
				recordedFirstJoin = true
			}
		}
		pendingStartupEvent = nil
	}

	private func handleServiceInvalidation(trigger: ConnectionTermination.Trigger) {
		if isDisconnecting {
			didDisconnect(with: nil, trigger: trigger)
		} else {
			let error = NSError(
				domain: connectionErrorDomain,
				code: Int(ConnectionErrorCode.other.rawValue),
				userInfo: [NSLocalizedDescriptionKey: String(localized: .IRC.connectionServiceClosedUnexpectedly)]
			)
			didDisconnect(with: error, trigger: trigger)
		}
	}

	/** Records that this connection is no longer one the system vouched for.

	 Set when a chain that failed validation is put in front of the user, and
	 never cleared for the life of the connection: whatever the user answers,
	 nothing that outlives the session may be taken from this peer. */
	func noteCertificateTrustOverridden() {
		certificateTrustWasOverridden = true
	}

	func resetState() {
		/* The next server advertises its own `LINELEN`, or none at all. */
		maximumLineLength = ProtocolLimits.maximumBodyLength + ProtocolLimits.lineTerminatorLength
		isConnecting = false
		isConnected = false
		isConnectedWithClientSideCertificate = false
		isDisconnecting = false
		EOFReceived = false
		isSecured = false
		certificateTrustWasOverridden = false
		connectedAddress = nil
	}

	private func invalidateProcess() {
		guard let serviceConnection else { return }
		connectionLogger.debug("Invalidating IRC connection service")
		serviceConnection.invalidate()
		self.serviceConnection = nil
	}

	/// Starts the connection service, unless one is already running.
	private func warmProcessIfNeeded() {
		guard serviceConnection == nil else { return }

		connectionLogger.debug("Warming IRC connection service")
		let connection = makeService()
		connection.remoteObjectInterface = RemoteConnectionInterface.server()
		connection.exportedInterface = RemoteConnectionInterface.client()
		connection.exportedObject = callbackReceiver
		connection.interruptionHandler = { [weak self] in
			self?.eventContinuation.yield(.serviceInterrupted)
			connectionLogger.info("IRC connection service interrupted")
		}
		connection.invalidationHandler = { [weak self] in
			self?.eventContinuation.yield(.serviceInvalidated)
			connectionLogger.info("IRC connection service invalidated")
		}
		connection.resume()
		serviceConnection = connection
	}

	/// The host, as far as anything on this side of the boundary sees it. The
	/// outgoing-line and trust-prompt files talk to the service through this.
	func remoteObjectProxy(
		errorHandler: ((Error) -> Void)? = nil
	) -> RemoteConnectionServerProtocol? {
		serviceConnection?.remoteObjectProxyWithErrorHandler { error in
			connectionLogger.error("IRC connection service error: \(error.localizedDescription, privacy: .public)")
			errorHandler?(error)
		} as? RemoteConnectionServerProtocol
	}

	func open() {
		guard terminal == false, session?.isTerminating == false,
		      isConnecting == false, isConnected == false, isDisconnecting == false else { return }
		config.diagnostics?.record(.serviceRequested)
		warmProcessIfNeeded()
		isConnecting = true
		let events = eventContinuation
		guard let proxy = remoteObjectProxy(errorHandler: { events.yield(.serviceFailed($0)) }) else {
			handleServiceInvalidation(trigger: .serviceFailure)
			return
		}
		proxy.open(with: ConnectionConfigEnvelope(config: config))

		if SettingsKeys.Internals.appSleepDisabled.value {
			remoteObjectProxy()?.disableAppNap()
		}

		remoteObjectProxy()?.disableSuddenTermination()
	}

	func close() {
		guard terminal == false, isDisconnecting == false else { return }
		beginCloseDeadline()
		closeInsecureCertificateTrustPanel()

		if isConnecting || isConnected {
			isDisconnecting = true
			remoteObjectProxy()?.close()
		} else {
			didDisconnect(with: nil, trigger: .localClose)
		}
	}

	/// QUIT starts this before its two-second grace period, keeping the total at five seconds.
	func beginCloseDeadline() {
		guard terminal == false, closeDeadlineTask == nil else { return }
		localCloseRequested = true
		closeDeadlineTask = Task { [weak self, closeClock] in
			await closeClock.wait(5)
			guard Task.isCancelled == false, let self else { return }
			connectionLogger.error("IRC connection did not close within five seconds; invalidating service")
			didDisconnect(with: nil, trigger: .closeDeadline)
		}
	}

	private func convertFromCommonEncoding(_ data: Data) -> String? {
		guard let session else { return nil }

		return session.convert(fromCommonEncoding: data)
	}

	private func didDisconnect(with error: Error?, trigger: ConnectionTermination.Trigger) {
		guard terminal == false else { return }
		terminal = true
		let nsError = error as NSError?
		recordTermination(ConnectionTermination(
			attemptIdentifier: diagnostics.identifier,
			elapsed: ProcessInfo.processInfo.systemUptime - diagnostics.requestedAt,
			trigger: trigger,
			phase: terminationPhase,
			localCloseRequested: localCloseRequested,
			receivedEOF: EOFReceived,
			disconnectMode: .effective(
				configured: session?.disconnectType ?? .normal,
				errorDomain: nsError?.domain,
				errorCode: nsError?.code
			),
			errorDomain: nsError?.domain,
			errorCode: nsError?.code
		))
		closeDeadlineTask?.cancel()
		closeDeadlineTask = nil
		invalidateProcess()
		closeInsecureCertificateTrustPanel()
		resetState()
		if session?.socket === self {
			session?.connectionDidDisconnect(error: error)
		}
		eventContinuation.finish()
		eventTask?.cancel()
	}

	private var terminationPhase: ConnectionTermination.Phase {
		if recordedFirstJoin {
			return .joined
		}
		if session?.isLoggedIn == true {
			return session?.startup.authentication == .confirmed ? .authenticated : .registered
		}
		if isSecured {
			return .secured
		}
		if isConnected {
			return .connected
		}
		return isConnecting ? .connecting : .requested
	}
}
