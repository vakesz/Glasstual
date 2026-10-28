// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Network
import Security

/** The target is nonisolated by default, so the enum needs no claim of its own:
 it holds a Network.framework connection, which is a reference, and the `value`
 marker it used to carry said the opposite. */
/// The structured-concurrency Network.framework transport, as an actor.
///
/// The connection's establishment, reads, writes and lifetime are all async
/// operations. The actor owns the connection, line buffer and state flags;
/// what the host needs to know comes back through `events`, in wire order.
actor ConnectionSocket {
	enum Phase: Equatable {
		case idle
		case connecting
		case connected
		case disconnecting(wasConnected: Bool)
	}

	/// Maximum bytes requested from the transport in a single read.
	static let maximumDataLength = 64 * 1024

	/// Maximum bytes buffered while waiting for a newline. A peer that never
	/// sends one is disconnected instead of growing memory forever.
	static let maximumBufferedLineLength = 1024 * 1024 // 1 MiB

	/// Seconds allowed for the transport to reach the ready state.
	static let connectTimeout: TimeInterval = 30

	/// Seconds the application is given to answer the certificate prompt. The
	/// reply block belongs to the other side of an XPC connection, so a
	/// dismissed panel or an interrupted connection can mean no answer ever
	/// arrives; the handshake must not wait on that forever.
	static let trustPromptTimeout: TimeInterval = 300

	nonisolated let config: ConnectionConfig
	nonisolated let uniqueIdentifier: String

	/// The application, for the one question the transport has to ask mid
	/// handshake. `RemoteConnectionClientProtocol` refines `Sendable`, so the
	/// proxy is as usable from the TLS verify block as it is from the actor.
	nonisolated let client: any RemoteConnectionClientProtocol

	/// What the async certificate validator learned about the peer's chain.
	var trustExport = TLSTrustExport()

	let events: AsyncStream<SocketEvent>.Continuation

	var connection: TransportConnection?
	/** The task that supervises this transport's dials.

	 A handshake that found no cipher suite in common ends the dial, not the
	 transport: the supervisor has one more to run. So a close cancels
	 ``dialTask`` and this one keeps deciding, which is also why an owner's close
	 is told apart from the transport's own through ``closedByOwner``. */
	var connectionTask: Task<Void, Never>?
	var dialTask: Task<ConnectionError?, Never>?
	/** Frames the reads into IRC lines.

	 The terminator is CRLF, and a server whose MOTD file has CRLF endings
	 writes `CR CR LF`, so every trailing CR goes with the terminator; a line
	 with nothing left in it is not a message. */
	var framer = LineFramer(
		maximumLineLength: ConnectionSocket.maximumBufferedLineLength,
		stripsCarriageReturns: true,
		dropsEmptyLines: true
	)
	var connectTimeoutTask: Task<Void, Never>?
	var trustAnswer: AsyncStream<Bool>.Continuation?
	/// State callbacks and deadlines can finish after a failed dial has already
	/// handed this socket to its legacy retry. Only the current dial may act on
	/// them.
	var dialGeneration = 0

	var phase = Phase.idle
	var connecting: Bool {
		phase == .connecting || phase == .disconnecting(wasConnected: false)
	}

	var connected: Bool {
		phase == .connected || phase == .disconnecting(wasConnected: true)
	}

	var disconnecting: Bool {
		if case .disconnecting = phase {
			return true
		}

		return false
	}

	var secured = false
	var sending = false

	var alternateDisconnectError: ConnectionError?
	/// A terminal event has entered the stream. The host must keep its reader
	/// alive until it delivers that event, even though this socket has already
	/// returned to `.idle`.
	var disconnectEventPending = false

	/// Whether the owner asked for this transport to close. A close it asked for
	/// is never answered by another dial.
	var closedByOwner = false

	/// Whether the dial in flight offers the suites with no forward secrecy, so
	/// that the fallback is offered once and once only.
	var offeredLegacyCipherSuites = false

	/** The OSStatus of the TLS failure that ended the dial, when that is what
	 ended it.

	 Kept as the number: the legacy retry is decided from the code, and by the
	 time the failure is a `ConnectionError` it is a sentence. */
	var tlsFailureCode: Int?

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
	 one, and a terminal event already queued still needs delivery. `false`
	 means there is nothing to wait for because the transport never dialled. */
	@discardableResult
	func close() -> Bool {
		/* Recorded before the guard: a close asked for while the transport was
		 already ending its own dial still has to stop the legacy retry. */
		closedByOwner = true

		return endDial() || disconnectEventPending
	}

	/** Ends the dial in flight, recording why.

	 The transport's own failures arrive here. Whether one more dial follows is
	 ``runConnection()``'s decision; this stops the dial and nothing else. */
	@discardableResult
	func fail(with error: ConnectionError) -> Bool {
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

	func endDial() -> Bool {
		guard disconnecting == false else { return true }
		guard disconnected == false else { return false }

		phase = .disconnecting(wasConnected: connected)

		cancelConnectTimeout()

		trustAnswer?.finish()
		trustAnswer = nil
		dialTask?.cancel()

		return true
	}

	func resetState() {
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

	func scheduleConnectTimeout() {
		cancelConnectTimeout()
		let generation = dialGeneration

		connectTimeoutTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(Self.connectTimeout), clock: .continuous)

			guard Task.isCancelled == false, let self else { return }

			await onConnectTimeout(generation: generation)
		}
	}

	func cancelConnectTimeout() {
		connectTimeoutTask?.cancel()
		connectTimeoutTask = nil
	}

	func onConnectTimeout(generation: Int) {
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

	var tlsNegotiatedProtocol: tls_protocol_version_t? {
		tlsMetadata.map(sec_protocol_metadata_get_negotiated_tls_protocol_version)
	}

	var tlsNegotiatedCipherSuite: tls_ciphersuite_t? {
		tlsMetadata.map(sec_protocol_metadata_get_negotiated_tls_ciphersuite)
	}

	var tlsMetadata: sec_protocol_metadata_t? {
		connected ? connection?.tlsMetadata : nil
	}

	var connectedHost: String? {
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
