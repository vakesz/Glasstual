/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2018 Codeux Software, LLC & respective contributors.
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

import CocoaExtensions
import Foundation
import Network
import Security

private nonisolated enum IRCNetworkConnection: Sendable { // nonisolated: value
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
		case let .tcp(connection):
			connection.onStateUpdate { _, state in
				switch state {
				case .ready: continuation.yield(.ready)
				case let .waiting(error), let .failed(error): continuation.yield(.failed(error))
				default: break
				}
			}
		case let .tls(connection):
			connection.onStateUpdate { _, state in
				switch state {
				case .ready: continuation.yield(.ready)
				case let .waiting(error), let .failed(error): continuation.yield(.failed(error))
				default: break
				}
			}
		}

		return stream
	}
}

/// What `IRCNetworkConnection.stateTransitions()` reports.
private nonisolated enum TransportTransition: Sendable { // nonisolated: value
	case ready
	case failed(NWError)
}

/// The structured-concurrency Network.framework transport, as an actor.
///
/// The connection's establishment, reads, writes and lifetime are all async
/// operations. The actor owns the connection, line buffer and state flags;
/// what the host needs to know comes back through `events`, in wire order.
actor ConnectionSocket {
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

	private static let torProxyAddress = "127.0.0.1"
	private static let torProxyPort: UInt16 = 9150

	nonisolated let config: IRCConnectionConfig // nonisolated: let
	nonisolated let uniqueIdentifier: String // nonisolated: let

	/// The application, for the one question the transport has to ask mid
	/// handshake. `RemoteConnectionClientProtocol` refines `Sendable`, so the
	/// proxy is as usable from the TLS verify block as it is from the actor.
	private nonisolated let client: any RemoteConnectionClientProtocol // nonisolated: let

	/// What the async certificate validator learned about the peer's chain.
	private var trustExport = TLSTrustExport()

	private let events: AsyncStream<SocketEvent>.Continuation

	private var connection: IRCNetworkConnection?
	private var connectionTask: Task<Void, Never>?
	/// The part of a line that arrived without its terminator, waiting for the
	/// read that completes it.
	private var readInBuffer = Data()
	private var connectTimeoutTask: Task<Void, Never>?
	private var trustAnswer: AsyncStream<Bool>.Continuation?

	private var connecting = false
	private var connected = false
	private var disconnecting = false
	private var secured = false
	private var sending = false

	private var alternateDisconnectError: ConnectionError?

	var disconnected: Bool {
		connecting == false && connected == false
	}

	init(
		config: IRCConnectionConfig,
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

		connecting = true

		scheduleConnectTimeout()

		connectionTask = Task { [weak self] in
			guard let self else { return }

			await runConnection()
		}
	}

	func close() {
		guard disconnected == false, disconnecting == false else { return }

		disconnecting = true

		cancelConnectTimeout()

		trustAnswer?.finish()
		trustAnswer = nil
		connectionTask?.cancel()
	}

	func close(with error: ConnectionError) {
		guard disconnected == false, disconnecting == false else { return }

		alternateDisconnectError = error

		close()
	}

	func close(with message: String) {
		close(with: ConnectionError.other(message: message))
	}

	private func resetState() {
		connecting = false
		connected = false
		disconnecting = false
		secured = false
		sending = false

		alternateDisconnectError = nil

		cancelConnectTimeout()

		connectionTask = nil
		connection = nil

		readInBuffer.removeAll()
	}

	// MARK: - Connect Timeout

	private func scheduleConnectTimeout() {
		cancelConnectTimeout()

		connectTimeoutTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(Self.connectTimeout), clock: .continuous)

			guard Task.isCancelled == false, let self else { return }

			await onConnectTimeout()
		}
	}

	private func cancelConnectTimeout() {
		connectTimeoutTask?.cancel()
		connectTimeoutTask = nil
	}

	private func onConnectTimeout() {
		connectTimeoutTask = nil

		guard connecting, connected == false else { return }

		let identifier = uniqueIdentifier
		let timeout = Self.connectTimeout

		ConnectionHostLog.connection.error(
			"Connection \(identifier, privacy: .public) timed out after \(timeout, privacy: .public) seconds"
		)

		close(with: String(localized: .ConnectionErrors.connectionTimedOut))
	}

	// MARK: - Connection task

	private func runConnection() async {
		do {
			let endpoint = NWEndpoint.hostPort(
				host: NWEndpoint.Host(config.serverAddress),
				port: NWEndpoint.Port(integerLiteral: config.serverPort)
			)
			if config.connectionPrefersSecuredConnection {
				let parameters = NWParametersBuilder.parameters { constructedTLS() }
				try applyProxy(to: parameters.parameters)

				try await withNetworkConnection(
					to: endpoint,
					using: parameters
				) { connection in
					try await use(.tls(connection))
				}
			} else {
				let parameters = NWParametersBuilder.parameters { constructedTCP() }
				try applyProxy(to: parameters.parameters)

				try await withNetworkConnection(
					to: endpoint,
					using: parameters
				) { connection in
					try await use(.tcp(connection))
				}
			}

			onDisconnect(with: nil)
		} catch is CancellationError {
			onDisconnect(with: nil)
		} catch {
			onDisconnect(with: error)
		}
	}

	private func use(_ connection: IRCNetworkConnection) async throws {
		self.connection = connection

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
					await self?.onReady()
				case let .failed(error):
					await self?.onTransportFailure(error)
				}
			}
		}

		defer { readiness.cancel() }

		try await read(from: connection)
	}

	private func onConnect() {
		cancelConnectTimeout()

		connecting = false
		connected = true

		/* When a proxy is in use the remote endpoint is the proxy, not the
		 server, so report nil as the host contract asks. */
		events.yield(.connected(host: proxyEndpoint == nil ? connectedHost : nil))
	}

	/// The transport finished establishing, so the handshake — if there was
	/// one — has run and its metadata is readable.
	private func onReady() {
		guard connecting, disconnecting == false else { return }

		config.diagnostics?.record(.transportReady)
		onConnect()
		onSecured()
	}

	/// The transport reported it cannot establish. Only an establishing
	/// connection is closed here: once ready, a drop is reported by the read
	/// that fails, and a close already under way keeps its own error.
	private func onTransportFailure(_ error: NWError) {
		guard connecting, connected == false, disconnecting == false else { return }

		config.diagnostics?.record(.transportFailed)
		close(with: connectionError(from: error))
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

	private func onDisconnect(with error: Error?) {
		var payload: ConnectionError?

		if let alternateDisconnectError {
			payload = alternateDisconnectError
		} else if let error {
			payload = connectionError(from: error)
		}

		resetState()

		events.yield(.disconnected(payload))

		/* Nothing follows a disconnect, so the host's event loop can end here
		 rather than waiting on a stream nobody will write to again. */
		events.finish()
	}

	// MARK: - Read & Write

	private func read(from connection: IRCNetworkConnection) async throws {
		while connecting || connected, disconnecting == false {
			let message = try await connection.receive(atMost: Self.maximumDataLength)
			try Task.checkCancellation()
			// A completed read also proves readiness if its state callback is still queued.
			onReady()

			let (content, isComplete) = message

			/* The final bytes (typically an ERROR line with the reason for the
			 disconnect) can arrive together with the EOF. */
			if content.isEmpty == false {
				readIn(content)
				let (drained, continuation) = AsyncStream<Void>.makeStream()
				events.yield(.readDrained(continuation))
				// This wait never occupies the host's command or writer task.
				for await _ in drained {}
				try Task.checkCancellation()
			}

			if isComplete {
				if readInBuffer.isEmpty == false {
					throw ConnectionError.socket(error: NSError(domain: NSPOSIXErrorDomain, code: Int(EPROTO)))
				}
				events.yield(.closedReadStream)

				return
			}
		}
	}

	/** Cuts `data` into lines and reports each one as it completes.

	 Terminators are found a line at a time rather than a byte at a time, and
	 the common case — a read that carries whole lines and nothing was left
	 over — hands each line straight out of the read without touching the
	 buffer at all. Only a partial line is copied, and only once: the buffer
	 keeps its allocation across lines and is never rescanned. */
	private func readIn(_ data: Data) {
		guard disconnected == false, disconnecting == false else { return }

		var remaining = data[...]

		while let terminator = remaining.firstIndex(of: 0x0A) {
			let line = remaining[..<terminator]
			remaining = remaining[remaining.index(after: terminator)...]

			if readInBuffer.isEmpty {
				/* A whole line inside one read. A read is bounded by
				 `maximumDataLength`, well under the line ceiling. */
				let trimmed = line.last == 0x0D ? line.dropLast() : line

				if trimmed.isEmpty == false {
					events.yield(.received(Data(trimmed)))
				}

				continue
			}

			guard bufferPartialLine(line) else { return }

			if readInBuffer.last == 0x0D {
				readInBuffer.removeLast()
			}
			if readInBuffer.isEmpty == false {
				events.yield(.received(readInBuffer))
			}
			readInBuffer.removeAll(keepingCapacity: true)
		}

		guard remaining.isEmpty == false else { return }

		_ = bufferPartialLine(remaining)
	}

	/// Holds `bytes` until the rest of their line arrives, disconnecting a peer
	/// that grows one past the ceiling. Reports whether framing may continue.
	private func bufferPartialLine(_ bytes: Data.SubSequence) -> Bool {
		guard readInBuffer.count + bytes.count <= Self.maximumBufferedLineLength else {
			close(with: String(localized: .ConnectionErrors.peerLineTooLong))
			return false
		}

		readInBuffer.append(contentsOf: bytes)

		return true
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

	private func startWriting(_ data: Data, over connection: IRCNetworkConnection) async {
		events.yield(.willSend(data))

		do {
			try await connection.send(data)
		} catch {
			sending = false
			close(with: connectionError(from: error))

			return
		}

		guard disconnecting == false else { return }

		sending = false
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

extension ConnectionSocket {
	private var proxyEndpoint: (host: String, port: UInt16)? {
		switch config.proxyType {
		case .socks5, .HTTP:
			guard let host = config.proxyAddress, host.isEmpty == false else {
				return nil
			}

			return (host: host, port: config.proxyPort)
		case .tor:
			return (host: Self.torProxyAddress, port: Self.torProxyPort)
		case .none, .automatic:
			return nil
		@unknown default:
			return nil
		}
	}

	private func constructedTCP() -> TCP {
		switch config.addressType {
		case .v4:
			TCP { IP().version(.v4) }
		case .v6:
			TCP { IP().version(.v6) }
		default:
			TCP()
		}
	}

	private func constructedTLS() -> TLS {
		var tls = TLS { constructedTCP() }
			.version(min: SecureTransportSupport.minimumProtocolType)

		if let clientCertificate = ClientSideCertificate.load(from: config) {
			let identity = sec_identity_create_with_certificates(
				clientCertificate.identity,
				[clientCertificate.certificate] as CFArray
			)

			if let identity {
				tls = tls.localIdentity(identity)
			}
		}

		if config.cipherSuites == .none {
			tls = tls.cipherSuiteGroups([.default])
		} else {
			let suites = SecureTransportSupport.cipherSuites(
				inCollection: config.cipherSuites,
				includeDeprecated: config.connectionPrefersModernCiphersOnly == false
			).compactMap { tls_ciphersuite_t(rawValue: $0.uint16Value) }

			tls = tls.cipherSuites(suites)
		}

		tls = tls.certificateValidator { [weak self] _, trust in
			guard let self else { return false }

			let diagnostics = config.diagnostics
			diagnostics?.record(.certificateEvaluationStarted)
			let evaluation = Self.evaluateCertificate(trust)
			diagnostics?.record(.certificateEvaluationCompleted)

			return await validateCertificate(evaluation)
		}

		return tls
	}

	private func applyProxy(to parameters: NWParameters) throws {
		switch config.proxyType {
		case .none:
			parameters.preferNoProxies = true
		case .automatic:
			/* The default privacy context consults the system proxy settings
			 (including PAC) so there is nothing to configure. */
			parameters.preferNoProxies = false
		case .socks5, .HTTP, .tor:
			guard let endpoint = proxyEndpoint else {
				throw ConnectionError.other(message: String(localized: .ConnectionErrors.proxyAddressMissing))
			}

			let nwEndpoint = NWEndpoint.hostPort(
				host: NWEndpoint.Host(endpoint.host),
				port: NWEndpoint.Port(integerLiteral: endpoint.port)
			)

			var proxyConfiguration = if config.proxyType == .HTTP {
				ProxyConfiguration(httpCONNECTProxy: nwEndpoint)
			} else {
				ProxyConfiguration(socksv5Proxy: nwEndpoint)
			}

			/* A proxy the user asked for must be used; never fall back to a
			 direct connection. */
			proxyConfiguration.allowFailover = false

			if config.proxyType != .tor,
			   let username = config.proxyUsername, username.isEmpty == false,
			   let password = config.proxyPassword, password.isEmpty == false
			{
				proxyConfiguration.applyCredential(username: username, password: password)
			}

			let privacyContext = NWParameters.PrivacyContext(description: "Glasstual.IRCConnection.\(uniqueIdentifier)")

			privacyContext.proxyConfigurations = [proxyConfiguration]

			parameters.setPrivacyContext(privacyContext)

			parameters.preferNoProxies = false
		@unknown default:
			throw ConnectionError.other(message: String(localized: .ConnectionErrors.unsupportedProxyType))
		}
	}

	private func translateError(_ error: NWError) -> ConnectionError {
		switch error {
		case let .dns(errorCode):
			ConnectionError(nwDNSError: errorCode)
		case let .posix(errorCode):
			ConnectionError(nwPOSIXError: errorCode.rawValue)
		case let .tls(errorCode):
			ConnectionError(nwTLSError: errorCode)
		case .wifiAware:
			ConnectionError(otherError: "Wi-Fi Aware error")
		@unknown default:
			ConnectionError(otherError: error.localizedDescription)
		}
	}

	private func connectionError(from error: Error) -> ConnectionError {
		if let error = error as? ConnectionError {
			return error
		}

		if let error = error as? NWError {
			return translateError(error)
		}

		return ConnectionError(socketError: error)
	}
}

// MARK: - Trust

private extension ConnectionSocket {
	/// Evaluates the peer inside Network.framework's async TLS handshake. A
	/// recoverable failure suspends the handshake while the application asks the
	/// user, so no traffic needs to be buffered behind a separate trust gate.
	nonisolated static func evaluateCertificate( // nonisolated: pure
		_ trust: sec_trust_t
	) -> TLSTrustEvaluation {
		/* sec_trust_copy_ref() follows the Create Rule; the result is +1. */
		let trustRef = sec_trust_copy_ref(trust).takeRetainedValue()

		var evaluationError: CFError?
		let trusted = SecTrustEvaluateWithError(trustRef, &evaluationError)
		let failureDescription = trusted
			? nil
			: ((evaluationError as Error?)?.localizedDescription ?? "Unknown error")

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

	func validateCertificate(_ evaluation: TLSTrustEvaluation) async -> Bool {
		guard connecting, disconnecting == false else { return false }
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

		client.ircConnectionRequestInsecureCertificateTrust { trusted in
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

// MARK: - Error Translation

private extension ConnectionError {
	static let dnsErrorReasons: [Int: String] = [
		kDNSServiceErr_NoError: "No error",
		kDNSServiceErr_NoSuchName: "No such name",
		kDNSServiceErr_NoMemory: "No memory",
		kDNSServiceErr_BadParam: "Bad parameter",
		kDNSServiceErr_BadReference: "Bad reference",
		kDNSServiceErr_BadState: "Bad state",
		kDNSServiceErr_BadFlags: "Bad flags",
		kDNSServiceErr_Unsupported: "Unsupported",
		kDNSServiceErr_NotInitialized: "Not initialized",
		kDNSServiceErr_AlreadyRegistered: "Already registered",
		kDNSServiceErr_NameConflict: "Name conflict",
		kDNSServiceErr_Invalid: "Invalid",
		kDNSServiceErr_Firewall: "Firewall",
		kDNSServiceErr_Incompatible: "Incompatible",
		kDNSServiceErr_BadInterfaceIndex: "Bad interface index",
		kDNSServiceErr_Refused: "Refused",
		kDNSServiceErr_NoSuchRecord: "No such record",
		kDNSServiceErr_NoAuth: "No authentication",
		kDNSServiceErr_NoSuchKey: "No such key",
		kDNSServiceErr_NATTraversal: "NAT traversal",
		kDNSServiceErr_DoubleNAT: "Double NAT",
		kDNSServiceErr_BadTime: "Bad time",
		kDNSServiceErr_BadSig: "Bad signature",
		kDNSServiceErr_BadKey: "Bad key",
		kDNSServiceErr_Transient: "Transient",
		kDNSServiceErr_ServiceNotRunning: "Service not running",
		kDNSServiceErr_NATPortMappingUnsupported: "NAT port mapping unsupported",
		kDNSServiceErr_NATPortMappingDisabled: "NAT port mapping disabled",
		kDNSServiceErr_NoRouter: "No router",
		kDNSServiceErr_PollingMode: "Polling mode",
		kDNSServiceErr_Timeout: "Timeout",
	]

	init(nwDNSError: DNSServiceErrorType) {
		let errorCode = Int(nwDNSError)
		let errorReason = Self.dnsErrorReasons[errorCode] ?? "Unknown"

		let errorMessage = ConnectionErrorLocalization.formatted(
			.ConnectionErrors.dnsError(errorReason, errorCode),
			errorReason,
			errorCode
		)

		let nsError = NSError(
			domain: "NWErrorDomainDNS",
			code: errorCode,
			userInfo: [NSLocalizedDescriptionKey: errorMessage]
		)

		self.init(socketError: nsError)
	}

	init(nwPOSIXError: Int32) {
		let errorCode = Int(nwPOSIXError)

		let errorReason = if let errorReasonC = strerror(nwPOSIXError) {
			String(cString: errorReasonC)
		} else {
			"Unknown"
		}

		let errorMessage = ConnectionErrorLocalization.formatted(
			.ConnectionErrors.posixError(errorReason, errorCode),
			errorReason,
			errorCode
		)

		let nsError = NSError(
			domain: "NWErrorDomainPOSIX",
			code: errorCode,
			userInfo: [NSLocalizedDescriptionKey: errorMessage]
		)

		self.init(socketError: nsError)
	}

	init(nwTLSError: OSStatus) {
		self.init(tlsError: Int(nwTLSError))
	}
}

private enum ConnectionErrorLocalization {
	static func formatted(_ resource: LocalizedStringResource, _ arguments: CVarArg...) -> String {
		let bundle = Bundle(for: ConnectionErrorLocalizationBundleToken.self)
		let format = bundle.localizedString(forKey: resource.key, value: nil, table: resource.table)
		return String(format: format, arguments: arguments)
	}
}

private final class ConnectionErrorLocalizationBundleToken {}
