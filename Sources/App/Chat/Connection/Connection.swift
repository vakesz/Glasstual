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

	/// What stands behind the certificate of an established TLS connection.
	enum CertificateAssurance: Equatable {
		/// The system accepted the server's chain.
		case validated
		/// The chain failed, and the user was shown why and chose to continue.
		case acceptedByUser
		/// The connection is set not to check the chain, so nothing says it is the server it claims.
		case unverified
	}

	/// How far the server's certificate can be relied on, or nil before TLS is up.
	var certificateAssurance: CertificateAssurance? {
		guard isSecured else { return nil }
		if certificateTrustWasOverridden {
			return .acceptedByUser
		}
		return config.connectionShouldValidateCertificateChain ? .validated : .unverified
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
	private let closeClock: TimerClock
	private let diagnostics: ConnectionDiagnostics
	private let recordTermination: (ConnectionTermination) -> Void
	private let makeService: () -> NSXPCConnection
	/// The read being handed to the session, while one is.
	private var receiveTask: Task<Void, Never>?
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

	/// Only this connection may finish or dismiss its pending certificate prompt.
	var certificateTrustRequest: CertificateTrustRequest?

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
		certificateTrustRequest?.cancel()
		closeDeadlineTask?.cancel()
		serviceConnection?.invalidate()
		eventContinuation.finish()
	}

	/// Drains the host's callbacks on the main actor in the order they arrived.
	private func startDeliveringEvents() {
		Task { [weak self, events] in
			for await event in events {
				guard let self else {
					Self.answerUnhandled(event)
					continue
				}
				if case let .didReceive(lines, acknowledge) = event {
					/* A task of its own, so that terminating the connection can
					 cancel a read parked behind the renderer. The loop still waits
					 for it, which keeps what follows in order, and awaiting a task's
					 value does not cancel it. */
					let reading = Task { await receive(lines) }
					receiveTask = reading
					await reading.value
					receiveTask = nil
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

	/// Answers an event the connection is gone to handle, so the reply it
	/// carries is not left unsent.
	private static func answerUnhandled(_ event: ConnectionEvent) {
		switch event {
		case let .didReceive(_, acknowledge):
			acknowledge()
		case let .requestInsecureCertificateTrust(response):
			response(false)
		default:
			break
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
			guard let session, !terminal, session.socket === self else { return }
			if !session.isLoggedIn, !session.canContinueConnecting {
				session.cancelReconnect()
				close()
				return
			}
			/* A renderer at capacity must be allowed to drain. Finish the native
			 list snapshot before giving the main actor away. The same boundary is
			 used every 64 lines and before the host's acknowledgement. */
			if batchingSession == nil || !session.renderAdmission.hasCapacity {
				batchingSession?.finishInboundMemberPresentationUpdates()
				batchingSession = nil
				await session.renderAdmission.waitForCapacity()
			}
			guard !Task.isCancelled, terminal == false, session.socket === self else { return }
			if !session.isLoggedIn, !session.canContinueConnecting {
				session.cancelReconnect()
				close()
				return
			}
			if batchingSession == nil {
				session.beginInboundMemberPresentationUpdates()
				batchingSession = session
			}
			if let string = convertFromCommonEncoding(line) {
				let signposter = PerformanceSignposts.signposter
				let interval = signposter.beginInterval("InboundLine")
				session.connectionDidReceive(string)
				signposter.endInterval("InboundLine", interval)
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

	/// Whether a connect or secure event may still advance this connection. A
	/// session that can no longer continue connecting closes it instead.
	private func admitConnectionProgress() -> Bool {
		guard isDisconnecting == false else { return false }
		guard session?.canContinueConnecting == true else {
			session?.cancelReconnect()
			close()
			return false
		}

		return true
	}

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
			guard admitConnectionProgress() else { return }
			connectedAddress = host
			isConnecting = false
			isConnected = true
			session?.connectionDidConnect()
		case let .didSecure(protocolType, cipherSuite):
			guard admitConnectionProgress() else { return }
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
			requestCertificateTrust(response)
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
		guard terminal == false, session?.canContinueConnecting == true,
		      isConnecting == false, isConnected == false, isDisconnecting == false else { return }
		config.diagnostics?.record(.serviceRequested)
		warmProcessIfNeeded()
		isConnecting = true
		let events = eventContinuation
		guard let proxy = remoteObjectProxy(errorHandler: { events.yield(.serviceFailed($0)) }) else {
			handleServiceInvalidation(trigger: .serviceFailure)
			return
		}
		// Validate the XPC envelope locally so a coding failure retries promptly
		// instead of waiting for the reconnect timer.
		let envelope = ConnectionConfigEnvelope(config: config)
		guard ConnectionConfigEnvelope.roundTrip(envelope) != nil else {
			handleServiceInvalidation(trigger: .serviceFailure)
			return
		}
		proxy.open(with: envelope)

		if SettingsKeys.Internals.appSleepDisabled.value {
			proxy.disableAppNap()
		}

		proxy.disableSuddenTermination()
	}

	func close() {
		guard terminal == false, isDisconnecting == false else { return }
		beginCloseDeadline()
		cancelCertificateTrustRequest()

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

		return session.decodeIRCLine(data)
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
		cancelCertificateTrustRequest()
		resetState()
		if session?.socket === self {
			session?.connectionDidDisconnect(error: error)
		}
		/* A read waiting on the renderer would keep this connection alive until
		 the backlog drained. It returns at its next check and is acknowledged
		 like any other. */
		receiveTask?.cancel()
		/* Finished rather than cancelled: cancelling ends the loop at once and
		 drops what is still buffered, and the host is waiting on the reply a
		 `didReceive` carries while the trust prompt waits on its answer. What
		 is left is handled as terminal events, which answer and do nothing else. */
		eventContinuation.finish()
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
