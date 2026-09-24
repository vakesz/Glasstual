// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Network
import Security

/** The target is nonisolated by default, so the enum needs no claim of its own:
 it holds a Network.framework connection, which is a reference, and the `value`
 marker it used to carry said the opposite. */
private enum TransportConnection: Sendable {
	case tcp(NetworkConnection<TCP>)
	case tls(NetworkConnection<TLS>)

	func receive(atMost maximumLength: Int) async throws -> (Data, Bool) {
		switch self {
		case let .tcp(connection):
			let message = try await connection.receive(atLeast: 1, atMost: maximumLength)
			return (message.content, message.metadata.endOfStream)
		case let .tls(connection):
			let message = try await connection.receive(atLeast: 1, atMost: maximumLength)
			return (message.content, message.metadata.endOfStream)
		}
	}

	func send(_ data: Data) async throws {
		switch self {
		case let .tcp(connection):
			try await connection.send(data)
		case let .tls(connection):
			try await connection.send(data)
		}
	}

	var remoteEndpoint: NWEndpoint? {
		switch self {
		case let .tcp(connection):
			connection.remoteEndpoint
		case let .tls(connection):
			connection.remoteEndpoint
		}
	}

	var tlsMetadata: sec_protocol_metadata_t? {
		guard case let .tls(connection) = self,
		      let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
		else {
			return nil
		}

		return metadata.securityProtocolMetadata
	}

	/** The state transitions this transport acts on, as values.

	 `onStateUpdate` is generic over the protocol stack, so its two states are
	 two unrelated types; the handler touches nothing but the continuation,
	 which is what lets it be registered from either case. Register before the
	 first read: establishment starts with that read, and a transition
	 delivered before the stream exists is a transition nobody hears.

	 `waiting` counts as a failure. Network.framework parks a connection there
	 when the peer hung up mid-handshake, refused the port or the name did not
	 resolve, and leaves it parked until the network path changes — which for
	 a server that just said no is never. The application has its own retry
	 timer, so the error is reported now rather than when the connect deadline
	 gives up half a minute later. */
	func stateTransitions() -> AsyncStream<TransportTransition> {
		let (stream, continuation) = AsyncStream<TransportTransition>.makeStream()

		switch self {
		case let .tcp(connection): Self.forwardStates(of: connection, to: continuation)
		case let .tls(connection): Self.forwardStates(of: connection, to: continuation)
		}

		return stream
	}

	private static func forwardStates(
		of connection: NetworkConnection<some SendableMetatype>,
		to continuation: AsyncStream<TransportTransition>.Continuation
	) {
		connection.onStateUpdate { _, state in
			switch state {
			case .ready: continuation.yield(.ready)
			case let .waiting(error), let .failed(error): continuation.yield(.failed(error))
			default: break
			}
		}
	}
}

/// What `TransportConnection.stateTransitions()` reports.
private nonisolated enum TransportTransition: Sendable {
	case ready
	case failed(NWError)
}

/// The structured-concurrency Network.framework transport, as an actor.
///
/// The connection's establishment, reads, writes and lifetime are all async
/// operations. The actor owns the connection, line buffer and state flags;
/// what the host needs to know comes back through `events`, in wire order.
actor ConnectionSocket {
	private enum Phase: Equatable {
		case idle
		case connecting
		case connected
		case disconnecting(wasConnected: Bool)
	}

	/// Maximum bytes requested from the transport in a single read.
	private static let maximumDataLength = 64 * 1024

	/// Maximum bytes buffered while waiting for a newline. A peer that never
	/// sends one is disconnected instead of growing memory forever.
	private static let maximumBufferedLineLength = 1024 * 1024 // 1 MiB

	/// Seconds allowed for the transport to reach the ready state.
	private static let connectTimeout: TimeInterval = 30

	/// Seconds the application is given to answer the certificate prompt. The
	/// reply block belongs to the other side of an XPC connection, so a
	/// dismissed panel or an interrupted connection can mean no answer ever
	/// arrives; the handshake must not wait on that forever.
	private static let trustPromptTimeout: TimeInterval = 300

	nonisolated let config: ConnectionConfig
	nonisolated let uniqueIdentifier: String

	/// The application, for the one question the transport has to ask mid
	/// handshake. `RemoteConnectionClientProtocol` refines `Sendable`, so the
	/// proxy is as usable from the TLS verify block as it is from the actor.
	private nonisolated let client: any RemoteConnectionClientProtocol

	/// What the async certificate validator learned about the peer's chain.
	private var trustExport = TLSTrustExport()

	private let events: AsyncStream<SocketEvent>.Continuation

	private var connection: TransportConnection?
	/** The task that supervises this transport's dials.

	 A handshake that found no cipher suite in common ends the dial, not the
	 transport: the supervisor has one more to run. So a close cancels
	 ``dialTask`` and this one keeps deciding, which is also why an owner's close
	 is told apart from the transport's own through ``closedByOwner``. */
	private var connectionTask: Task<Void, Never>?
	private var dialTask: Task<ConnectionError?, Never>?
	/** Frames the reads into IRC lines.

	 The terminator is CRLF, and a server whose MOTD file has CRLF endings
	 writes `CR CR LF`, so every trailing CR goes with the terminator; a line
	 with nothing left in it is not a message. */
	private var framer = LineFramer(
		maximumLineLength: ConnectionSocket.maximumBufferedLineLength,
		stripsCarriageReturns: true,
		dropsEmptyLines: true
	)
	private var connectTimeoutTask: Task<Void, Never>?
	private var trustAnswer: AsyncStream<Bool>.Continuation?
	/// State callbacks and deadlines can finish after a failed dial has already
	/// handed this socket to its legacy retry. Only the current dial may act on
	/// them.
	private var dialGeneration = 0

	private var phase = Phase.idle
	private var connecting: Bool {
		phase == .connecting || phase == .disconnecting(wasConnected: false)
	}

	private var connected: Bool {
		phase == .connected || phase == .disconnecting(wasConnected: true)
	}

	private var disconnecting: Bool {
		if case .disconnecting = phase {
			return true
		}

		return false
	}

	private var secured = false
	private var sending = false

	private var alternateDisconnectError: ConnectionError?

	/// Whether the owner asked for this transport to close. A close it asked for
	/// is never answered by another dial.
	private var closedByOwner = false

	/// Whether the dial in flight offers the suites with no forward secrecy, so
	/// that the fallback is offered once and once only.
	private var offeredLegacyCipherSuites = false

	/** The OSStatus of the TLS failure that ended the dial, when that is what
	 ended it.

	 Kept as the number: the legacy retry is decided from the code, and by the
	 time the failure is a `ConnectionError` it is a sentence. */
	private var tlsFailureCode: Int?

	var disconnected: Bool {
		phase == .idle
	}

	init(
		config: ConnectionConfig,
		client: any RemoteConnectionClientProtocol,
		events: AsyncStream<SocketEvent>.Continuation
	) {
		self.config = config
		self.client = client
		self.events = events

		uniqueIdentifier = UUID().uuidString
	}

	// MARK: - Open/Close

	func open() {
		guard disconnected, disconnecting == false else { return }
		config.diagnostics?.record(.transportStarted)

		if let proxyEndpoint {
			events.yield(.willConnectToProxy(host: proxyEndpoint.host, port: proxyEndpoint.port))
		}

		phase = .connecting
		dialGeneration += 1

		scheduleConnectTimeout()

		connectionTask = Task { [weak self] in
			guard let self else { return }

			await runConnection()
		}
	}

	/** Begins closing at the owner's request, and reports whether a
	 `.disconnected` event will follow.

	 The owner waits for that event before letting go of the transport, so this
	 has to be honest about it. A close already under way is still on its way to
	 one. `false` means there is nothing to wait for: the transport never
	 dialled, or has already finished. */
	@discardableResult
	func close() -> Bool {
		/* Recorded before the guard: a close asked for while the transport was
		 already ending its own dial still has to stop the legacy retry. */
		closedByOwner = true

		return endDial()
	}

	/** Ends the dial in flight, recording why.

	 The transport's own failures arrive here. Whether one more dial follows is
	 ``runConnection()``'s decision; this stops the dial and nothing else. */
	@discardableResult
	private func fail(with error: ConnectionError) -> Bool {
		guard disconnected == false || disconnecting else { return false }

		/* The reason is recorded whether or not a close is already under way: a
		 read failure and a write failure land in the same turn, and a plain
		 `close()` carries none at all, so dropping the error here was how a
		 disconnect the transport had a reason for reached the client as one it
		 did not. The first reason given is the one that caused the close. */
		if alternateDisconnectError == nil {
			alternateDisconnectError = error
		}

		return endDial()
	}

	private func endDial() -> Bool {
		guard disconnecting == false else { return true }
		guard disconnected == false else { return false }

		phase = .disconnecting(wasConnected: connected)

		cancelConnectTimeout()

		trustAnswer?.finish()
		trustAnswer = nil
		dialTask?.cancel()

		return true
	}

	private func resetState() {
		phase = .idle
		secured = false
		sending = false

		alternateDisconnectError = nil
		closedByOwner = false
		offeredLegacyCipherSuites = false
		tlsFailureCode = nil

		cancelConnectTimeout()

		connectionTask = nil
		dialTask = nil
		connection = nil

		framer.reset()
	}

	// MARK: - Connect Timeout

	private func scheduleConnectTimeout() {
		cancelConnectTimeout()
		let generation = dialGeneration

		connectTimeoutTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(Self.connectTimeout), clock: .continuous)

			guard Task.isCancelled == false, let self else { return }

			await onConnectTimeout(generation: generation)
		}
	}

	private func cancelConnectTimeout() {
		connectTimeoutTask?.cancel()
		connectTimeoutTask = nil
	}

	private func onConnectTimeout(generation: Int) {
		guard generation == dialGeneration else { return }
		connectTimeoutTask = nil

		guard connecting, connected == false, disconnecting == false else { return }

		let identifier = uniqueIdentifier
		let timeout = Self.connectTimeout

		ConnectionHostLog.connection.error(
			"Connection \(identifier, privacy: .public) timed out after \(timeout, privacy: .public) seconds"
		)

		fail(with: .other(message: String(localized: .ConnectionErrors.connectionTimedOut)))
	}

	// MARK: - Connection task

	/** Dials, and dials once more without forward secrecy when the peer accepted
	 none of the suites the selection offered.

	 The selected suites are offered first on every connect, so a server that has
	 since been fixed is reached the right way with no state to clear. The second
	 dial is part of the same connection attempt: it costs the application no
	 reconnect-backoff step, because as far as the application is concerned this
	 transport has not failed yet. */
	private func runConnection() async {
		let failure = await dial(offeringLegacyCipherSuites: false)

		guard retriesWithoutForwardSecrecy else {
			onDisconnect(with: failure)

			return
		}

		prepareForLegacyDial()

		/* The second dial can establish and then run for hours. Its eventual
		 failure belongs to that connection, and a certificate rejection during
		 its handshake must also retain its own classification. */
		let legacyFailure = await dial(offeringLegacyCipherSuites: true)

		onDisconnect(with: legacyFailure)
	}

	/** One dial, and the reason it ended — nil when it ended with none.

	 Its own task, so that ending the dial — the owner's close, or this
	 transport's answer to a failure — cancels the dial without cancelling the
	 supervisor that may still have the legacy retry to run. */
	private func dial(offeringLegacyCipherSuites offering: Bool) async -> ConnectionError? {
		offeredLegacyCipherSuites = offering

		let task = Task { [weak self] () -> ConnectionError? in
			guard let self else { return nil }

			return await performDial(offeringLegacyCipherSuites: offering)
		}

		dialTask = task

		let failure = await task.value

		dialTask = nil

		return failure
	}

	private func performDial(offeringLegacyCipherSuites offering: Bool) async -> ConnectionError? {
		do {
			let endpoint = NWEndpoint.hostPort(
				host: NWEndpoint.Host(config.serverAddress),
				port: NWEndpoint.Port(integerLiteral: config.serverPort)
			)
			if config.connectionPrefersSecuredConnection {
				let parameters = NWParametersBuilder.parameters {
					constructedTLS(offeringLegacyCipherSuites: offering)
				}
				try ConnectionParameters.applyProxy(config, to: parameters.parameters, uniqueIdentifier: uniqueIdentifier)

				try await withNetworkConnection(
					to: endpoint,
					using: parameters
				) { connection in
					try await use(.tls(connection))
				}
			} else {
				let parameters = NWParametersBuilder.parameters { ConnectionParameters.tcp(for: config) }
				try ConnectionParameters.applyProxy(config, to: parameters.parameters, uniqueIdentifier: uniqueIdentifier)

				try await withNetworkConnection(
					to: endpoint,
					using: parameters
				) { connection in
					try await use(.tcp(connection))
				}
			}

			return alternateDisconnectError
		} catch is CancellationError {
			return alternateDisconnectError
		} catch {
			noteTLSFailure(error)

			return alternateDisconnectError ?? ConnectionError.translating(error)
		}
	}

	/** Whether the dial that just ended is the one failure this transport answers
	 by dialling again itself.

	 Everything the connection has done so far is part of the question: a
	 transport that connected, secured itself or saw the peer's certificate did
	 agree on a suite, and a close the owner asked for is not something to answer
	 with another dial. */
	private var retriesWithoutForwardSecrecy: Bool {
		SecureTransportSupport.retriesWithLegacyCipherSuites(
			afterErrorCode: tlsFailureCode,
			legacySuitesAlreadyOffered: offeredLegacyCipherSuites,
			peerCertificateSeen: trustExport.certificateChain.isEmpty == false
		)
			&& closedByOwner == false
			&& connected == false
			&& secured == false
	}

	/// Puts the transport back where ``open()`` left it, for the one extra dial.
	private func prepareForLegacyDial() {
		let identifier = uniqueIdentifier

		ConnectionHostLog.connection.notice(
			"Connection \(identifier, privacy: .public) found no cipher suite in common; offering the legacy suites once"
		)

		tlsFailureCode = nil
		alternateDisconnectError = nil
		trustExport = TLSTrustExport()
		connection = nil
		phase = .connecting
		dialGeneration += 1

		framer.reset()

		config.diagnostics?.record(.transportStarted)
		scheduleConnectTimeout()
	}

	/// Records the OSStatus of a TLS failure, which is what the legacy retry is
	/// decided from.
	private func noteTLSFailure(_ error: any Error) {
		switch error {
		case let .tls(code) as NWError:
			tlsFailureCode = Int(code)
		case let error as NSError where SecureTransportSupport.isTLSError(error):
			tlsFailureCode = error.code
		default:
			break
		}
	}

	private func use(_ connection: TransportConnection) async throws {
		self.connection = connection
		let generation = dialGeneration

		try Task.checkCancellation()

		/* Typed connections establish lazily when the first operation starts.
		 Network.framework holds sends behind DNS, proxy and TLS establishment;
		 a failed handshake is reported by the first async operation. So the
		 connection handed to us here has no TLS metadata yet, and what was
		 negotiated is only knowable once it reports itself ready. */
		let transitions = connection.stateTransitions()

		let readiness = Task { [weak self] in
			for await transition in transitions {
				switch transition {
				case .ready:
					await self?.onReady(generation: generation)
				case let .failed(error):
					await self?.onTransportFailure(error, generation: generation)
				}
			}
		}

		defer { readiness.cancel() }

		try await read(from: connection, generation: generation)
	}

	private func onConnect() {
		cancelConnectTimeout()

		phase = .connected

		/* When a proxy is in use the remote endpoint is the proxy, not the
		 server, so report nil as the host contract asks. */
		events.yield(.connected(host: proxyEndpoint == nil ? connectedHost : nil))
	}

	/// The transport finished establishing, so the handshake — if there was
	/// one — has run and its metadata is readable.
	private func onReady(generation: Int) {
		guard generation == dialGeneration, connecting, disconnecting == false else { return }

		config.diagnostics?.record(.transportReady)
		onConnect()
		onSecured()
	}

	/// The transport reported it cannot establish. Only an establishing
	/// connection is closed here: once ready, a drop is reported by the read
	/// that fails, and a close already under way keeps its own error.
	private func onTransportFailure(_ error: NWError, generation: Int) {
		guard generation == dialGeneration, connecting, connected == false, disconnecting == false else { return }

		config.diagnostics?.record(.transportFailed)
		noteTLSFailure(error)
		fail(with: ConnectionError.translating(error))
	}

	private func onSecured() {
		/* Announced once. A plain TCP connection has no metadata to report and
		 so never becomes secured; a connection that drops back to preparing and
		 returns to ready negotiated nothing new. */
		guard secured == false,
		      let protocolVersion = tlsNegotiatedProtocol,
		      let cipherSuite = tlsNegotiatedCipherSuite
		else {
			return
		}

		secured = true

		events.yield(.secured(protocolVersion: protocolVersion, cipherSuite: cipherSuite))
	}

	/// Reports the transport gone, with the reason the dials it ran settled on.
	private func onDisconnect(with error: ConnectionError?) {
		resetState()

		events.yield(.disconnected(error))

		/* Nothing follows a disconnect, so the host's event loop can end here
		 rather than waiting on a stream nobody will write to again. */
		events.finish()
	}

	// MARK: - Read & Write

	private func read(from connection: TransportConnection, generation: Int) async throws {
		while connecting || connected, disconnecting == false {
			let message = try await connection.receive(atMost: Self.maximumDataLength)
			try Task.checkCancellation()
			// A completed read also proves readiness if its state callback is still queued.
			onReady(generation: generation)

			let (content, isComplete) = message

			/* The final bytes (typically an ERROR line with the reason for the
			 disconnect) can arrive together with the EOF. */
			let lines = content.isEmpty ? [] : readIn(content)

			if lines.isEmpty == false {
				/* The end-to-end flow control: nothing more is read until the
				 application has handled these lines and said so, so a server
				 that outpaces it fills the TCP window instead of a queue between
				 the processes. Ending the connection cancels this task, which
				 ends the wait too. The wait never occupies the host's command or
				 writer task. */
				let (acknowledgement, acknowledged) = AsyncStream<Void>.makeStream()
				events.yield(.received(lines, acknowledged: acknowledged))
				for await _ in acknowledgement {}
				try Task.checkCancellation()
			}

			if isComplete {
				if framer.hasPartialLine {
					throw ConnectionError.socket(error: NSError(domain: NSPOSIXErrorDomain, code: Int(EPROTO)))
				}
				events.yield(.closedReadStream)

				return
			}
		}
	}

	/** Cuts `data` into lines and returns the ones it completes, in order.

	 A line too long to buffer closes the connection, and nothing after it on
	 this read is framed. The lines before it are still the server's, and they
	 go out ahead of the disconnect. */
	private func readIn(_ data: Data) -> [Data] {
		guard disconnected == false, disconnecting == false else { return [] }

		do {
			return try framer.lines(appending: data)
		} catch {
			fail(with: .other(message: String(localized: .ConnectionErrors.peerLineTooLong)))

			return error.completedLines
		}
	}

	/** Sends `data`, reporting whether it was taken.

	 Only one write is in flight at a time, and this is where that is decided:
	 the claim on `sending` is made without an intervening suspension, so a
	 caller that is told `false` knows the data was not sent and can queue it
	 again. Deciding it anywhere else meant two callers could both pass the
	 check and the loser's line would be dropped with nobody told. */
	func write(_ data: Data) async -> Bool {
		guard connected, disconnecting == false, sending == false, let connection else {
			return false
		}

		sending = true

		await startWriting(data, over: connection)

		return true
	}

	private func startWriting(_ data: Data, over connection: TransportConnection) async {
		events.yield(.willSend(data))

		do {
			try await connection.send(data)
		} catch {
			sending = false
			fail(with: ConnectionError.translating(error))

			return
		}

		/* Cleared before the disconnect check: returning with it still set left
		 the writer believing a send was in flight, and nothing else clears it. */
		sending = false

		guard disconnecting == false else { return }

		events.yield(.didSend)
	}

	// MARK: - Secure Connection Information

	/// What the application shows in its certificate panels. The `SecTrust` the
	/// chain came from stayed in the verify block; this is all values.
	func secureConnectionInformation() -> SecureConnectionInformation {
		let export = trustExport

		return SecureConnectionInformation(
			policyName: export.policyName ?? (config.serverAddress.isIPAddress ? config.serverAddress : nil),
			protocolVersion: tlsNegotiatedProtocol ?? tlsProtocolVersionUnknown,
			cipherSuite: tlsNegotiatedCipherSuite ?? tlsCipherSuiteUnknown,
			certificateChain: export.certificateChain,
			trustFailureDescription: export.failureDescription
		)
	}

	private var tlsNegotiatedProtocol: tls_protocol_version_t? {
		tlsMetadata.map(sec_protocol_metadata_get_negotiated_tls_protocol_version)
	}

	private var tlsNegotiatedCipherSuite: tls_ciphersuite_t? {
		tlsMetadata.map(sec_protocol_metadata_get_negotiated_tls_ciphersuite)
	}

	private var tlsMetadata: sec_protocol_metadata_t? {
		connected ? connection?.tlsMetadata : nil
	}

	private var connectedHost: String? {
		guard case let .hostPort(host, _)? = connection?.remoteEndpoint else { return nil }

		switch host {
		case let .name(address, _):
			return address
		case let .ipv4(address):
			return address.rawValue.IPv4Address
		case let .ipv6(address):
			return address.rawValue.IPv6Address
		@unknown default:
			return nil
		}
	}
}

// MARK: - Parameters

private extension ConnectionSocket {
	/// Where this connection dials, when a proxy stands in front of the server.
	var proxyEndpoint: (host: String, port: UInt16)? {
		ConnectionParameters.proxyEndpoint(for: config)
	}

	/** The configured handshake, with the one thing the configuration cannot
	 answer: whether this peer's certificate chain is acceptable.

	 The validator is the same on both dials. A downgrade to the legacy suites
	 changes what is negotiated and nothing about who the peer has to be. */
	func constructedTLS(offeringLegacyCipherSuites: Bool) -> TLS {
		let generation = dialGeneration

		return ConnectionParameters.tls(
			for: config,
			offeringLegacyCipherSuites: offeringLegacyCipherSuites
		).certificateValidator { [weak self] _, trust in
			guard let self else { return false }

			let diagnostics = config.diagnostics
			diagnostics?.record(.certificateEvaluationStarted)
			let evaluation = Self.evaluateCertificate(trust)
			diagnostics?.record(.certificateEvaluationCompleted)

			return await validateCertificate(evaluation, generation: generation)
		}
	}
}

// MARK: - Trust

/// What the service learned about the peer's certificate chain.
///
/// Produced and consumed by the socket actor's async TLS validation path. The
/// `SecTrust` it came from never escapes the validator.
private struct TLSTrustExport: Sendable {
	var policyName: String?
	var certificateChain: [Data] = []

	/// Why the system did not trust the chain. nil when it did, or when the
	/// chain has not been evaluated yet.
	var failureDescription: String?
}

private struct TLSTrustEvaluation: Sendable {
	var export: TLSTrustExport
	var isRecoverableFailure: Bool
}

private extension ConnectionSocket {
	/// Evaluates the peer inside Network.framework's async TLS handshake. A
	/// recoverable failure suspends the handshake while the application asks the
	/// user, so no traffic needs to be buffered behind a separate trust gate.
	/** A `static` member of an actor is already outside its isolation, so this
	 needs no `nonisolated` of its own — and it could not honestly carry the
	 `pure` claim the keyword used to require: `sec_trust_t` is a reference, and
	 evaluating a chain reads the trust store. */
	static func evaluateCertificate(
		_ trust: sec_trust_t
	) -> TLSTrustEvaluation {
		/* sec_trust_copy_ref() follows the Create Rule; the result is +1. */
		let trustRef = sec_trust_copy_ref(trust).takeRetainedValue()

		var evaluationError: CFError?
		let trusted = SecTrustEvaluateWithError(trustRef, &evaluationError)
		let failureDescription = trusted
			? nil
			: ((evaluationError as Error?)?.localizedDescription
				?? String(localized: .ConnectionErrors.unknownError))

		var evaluationResult: SecTrustResultType = .invalid
		SecTrustGetTrustResult(trustRef, &evaluationResult)

		return TLSTrustEvaluation(
			export: TLSTrustExport(
				policyName: SecureTransportSupport.policyName(in: trustRef),
				certificateChain: SecureTransportSupport.certificates(in: trustRef) ?? [],
				failureDescription: failureDescription
			),
			isRecoverableFailure: evaluationResult == .recoverableTrustFailure
		)
	}

	func validateCertificate(_ evaluation: TLSTrustEvaluation, generation: Int) async -> Bool {
		guard generation == dialGeneration, connecting, disconnecting == false else { return false }
		trustExport = evaluation.export

		guard let failureDescription = evaluation.export.failureDescription else {
			config.diagnostics?.record(.certificateAccepted)
			return true
		}

		let serverAddress = config.serverAddress

		guard config.connectionShouldValidateCertificateChain else {
			ConnectionHostLog.connection.error(
				"Certificate chain for '\(serverAddress, privacy: .public)' failed validation but the connection is configured to ignore that: \(failureDescription, privacy: .public)"
			)

			return true
		}

		ConnectionHostLog.connection.error(
			"Certificate chain for '\(serverAddress, privacy: .public)' failed validation: \(failureDescription, privacy: .public)"
		)

		guard evaluation.isRecoverableFailure else {
			return false
		}

		return await requestInsecureTrust()
	}

	/** Asks the application whether to proceed with a chain the system refused.

	 The reply block is the application's to invoke, across XPC, and there are
	 real paths where it never is: the trust panel closed programmatically, or
	 the connection interrupted while it was open. Waiting on that forever
	 strands this actor — and with it the socket, the client proxy and the event
	 stream — for the life of a service process that every connection shares. So
	 the wait is bounded, and cancelling the connection ends it too. Both of
	 those answer `false`, which is the answer the system already gave. */
	func requestInsecureTrust() async -> Bool {
		let (answers, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
		trustAnswer = continuation
		cancelConnectTimeout()

		client.requestInsecureCertificateTrust { trusted in
			continuation.yield(trusted)
			continuation.finish()
		}

		let deadline = Task {
			try? await Task.sleep(for: .seconds(Self.trustPromptTimeout), clock: .continuous)

			continuation.finish()
		}

		defer {
			deadline.cancel()
			trustAnswer = nil
			if connecting, disconnecting == false {
				scheduleConnectTimeout()
			}
		}

		for await trusted in answers {
			return trusted && connecting && disconnecting == false && Task.isCancelled == false
		}

		let identifier = uniqueIdentifier

		ConnectionHostLog.connection.error(
			"Certificate trust prompt for connection \(identifier, privacy: .public) went unanswered"
		)

		return false
	}
}
