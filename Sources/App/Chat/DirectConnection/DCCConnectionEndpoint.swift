// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Network
import os

/// How the two ends of a DCC connection find each other.
nonisolated enum DCCEndpoint: Sendable {
	/// Dial the peer, which is already listening.
	case connect(host: String, port: UInt16, interfaceName: String?, timeout: Duration?)
	/// Listen for the peer on the first port in the range that binds.
	case listen(portRange: ClosedRange<UInt16>)
}

/** Establishing the one connection a DCC feature talks over.

 A file transfer and a direct chat reach their peer the same two ways: dial the
 address the offer named, or bind a port and take the single connection the peer
 makes to it. Both ways live here, so what is left in ``DCCTransfer`` and
 ``DirectChatSocket`` is only what differs between them — a byte count and an
 acknowledgement protocol on one side, line framing on the other.

 The listener never outlives the call that waits on it. ``accept(on:expectedPeerAddress:sendTimeout:deadline:log:)``
 cancels it when the peer arrives, when the deadline passes and when the caller
 gives up, so no caller has to hold the listener in order to close a port. */
nonisolated enum DCCConnectionEndpoint {
	/// A bound port waiting for the peer, plain or TLS.
	enum ListeningSession: Sendable {
		case plain(DCCTransport.ListeningSession<TCP>)
		case secure(DCCTransport.ListeningSession<TLS>, DCCTLSHandshake)

		var port: UInt16 {
			switch self {
			case let .plain(session): session.port
			case let .secure(session, _): session.port
			}
		}
	}

	/// Dials a peer that is already listening.
	///
	/// With a handshake the connection is TLS with this side as the client,
	/// and it is not returned until the peer has been decided on. The timeout
	/// then also covers that decision, which may be a person's.
	static func connect(
		toHost host: String,
		port: UInt16,
		interfaceName: String?,
		timeout: Duration?,
		handshake: DCCTLSHandshake? = nil
	) async throws -> DCCConnection {
		guard host.isEmpty == false, let networkPort = NWEndpoint.Port(rawValue: port) else {
			throw DCCTransferError.badParameter
		}

		let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: networkPort)

		guard let handshake else {
			let parameters = DCCTransport.parameters(interfaceName: interfaceName, connectTimeout: timeout)
			let connection = NetworkConnection<TCP>(
				to: endpoint,
				using: .parameters(initialParameters: parameters) { TCP() }
			)

			try await DCCTransport.withTimeout(timeout, failingWith: .connectTimeout) {
				/* Typed Network connections establish on first I/O. Empty data puts
				 no bytes on the stream but makes the connected event truthful. */
				try await connection.send(Data())
			}

			return .plain(connection)
		}

		let tls = try handshake.options(connectTimeout: timeout)
		let connection = NetworkConnection<TLS>(
			to: endpoint,
			using: .parameters { tls }.localEndpoint(DCCTransport.localEndpoint(interfaceName: interfaceName))
		)
		let establishment = (timeout ?? handshake.configuration.handshakeTimeout) + handshake.configuration.decisionTimeout

		let session = try await establish(connection, handshake: handshake, timeout: establishment)

		return .secure(connection, session)
	}

	/** Binds the first port in `portRange` that a listener actually reaches.

	 `deadline` is the whole window binding and waiting for the peer share, not a
	 budget for each of them in turn: applying the timeout to each gave a slow
	 bind twice what the caller asked for. Pass the same instant to
	 ``accept(on:expectedPeerAddress:sendTimeout:deadline:log:)``. With a
	 handshake the listener is TLS, with this side as the server. */
	static func bind(
		portRange: ClosedRange<UInt16>,
		deadline: ContinuousClock.Instant?,
		handshake: DCCTLSHandshake? = nil
	) async throws -> ListeningSession {
		try await DCCTransport.withDeadline(deadline, failingWith: .connectTimeout) {
			guard let handshake else {
				return try await .plain(DCCTransport.startListener(portRange: portRange))
			}
			return try await .secure(DCCTransport.startListener(portRange: portRange, handshake: handshake), handshake)
		}
	}

	/** Takes the one connection the peer makes to a bound listener.

	 A connection from anywhere other than `expectedPeerAddress` is refused and
	 the wait goes on; an empty expectation accepts the first arrival, which is
	 what is left whenever the offer named no address. One listener serves one
	 connection, so the port closes the moment a peer is accepted rather than
	 leaving somebody else a window to reach it.

	 `deadline` bounds the wait for the peer. A TLS peer's handshake, and the
	 decision about it, run after the port has closed and are bounded by the
	 handshake's own timeouts instead, so a person deciding does not keep the
	 port open. */
	static func accept(
		on session: ListeningSession,
		expectedPeerAddress: String,
		sendTimeout: Duration?,
		deadline: ContinuousClock.Instant?,
		log: Logger
	) async throws -> DCCConnection {
		switch session {
		case let .plain(listener):
			let connection = try await arrival(
				on: listener,
				expectedPeerAddress: expectedPeerAddress,
				deadline: deadline,
				log: log
			) { candidate in
				/* Typed Network connections establish on first I/O. Empty data
				 puts no bytes on the stream but makes the connected event
				 truthful. */
				try await DCCTransport.withTimeout(sendTimeout, failingWith: .connectTimeout) {
					try await candidate.send(Data())
				}
			} reject: { candidate in
				/* Half-closing tells whoever dialled that the port is not going to
				 answer, rather than leaving them holding a socket that never
				 carries anything. */
				try? await candidate.send(Data(), endOfStream: true)
			}
			return .plain(connection)
		case let .secure(listener, handshake):
			/* A refused TLS candidate is never started: starting it would run its
			 handshake, and with it the decision about a peer nobody accepted.
			 Releasing it is what closes it. */
			let connection = try await arrival(
				on: listener,
				expectedPeerAddress: expectedPeerAddress,
				deadline: deadline,
				log: log,
				establish: { _ in },
				reject: { _ in }
			)
			let establishment = (sendTimeout ?? handshake.configuration.handshakeTimeout)
				+ handshake.configuration.decisionTimeout
			let session = try await establish(connection, handshake: handshake, timeout: establishment)
			return .secure(connection, session)
		}
	}

	/// Waits within `deadline` for the first acceptable arrival, closes the
	/// listener, and establishes the arrival with `establish` before the
	/// deadline is released.
	private static func arrival<ApplicationProtocol: NetworkProtocolOptions & SendableMetatype>(
		on session: DCCTransport.ListeningSession<ApplicationProtocol>,
		expectedPeerAddress: String,
		deadline: ContinuousClock.Instant?,
		log: Logger,
		establish: @escaping @Sendable (NetworkConnection<ApplicationProtocol>) async throws -> Void,
		reject: @escaping @Sendable (NetworkConnection<ApplicationProtocol>) async -> Void
	) async throws -> NetworkConnection<ApplicationProtocol> {
		/* Cancelling the listener's task is what finishes the stream of arrivals,
		 and therefore what ends the wait below. It is done on every way out,
		 including the caller giving up while the peer is still absent: nothing
		 else can reach the listener from here. */
		defer { session.task.cancel() }

		return try await withTaskCancellationHandler {
			try await DCCTransport.withDeadline(deadline, failingWith: .connectTimeout) {
				var rejectedAPeer = false

				for await candidate in session.connections {
					try Task.checkCancellation()

					guard DCCTransport.connection(candidate, isFrom: expectedPeerAddress) else {
						log.error("Rejected a DCC connection from an address other than the one the offer named")
						rejectedAPeer = true
						await reject(candidate)

						continue
					}

					session.task.cancel()
					try await establish(candidate)

					return candidate
				}

				if rejectedAPeer {
					throw DCCTransferError.rejectedPeerAddress
				}

				throw DCCTransferError.closedByPeer
			}
		} onCancel: {
			session.task.cancel()
		}
	}

	/** Runs a TLS connection's handshake, including the decision about the
	 peer, and fails unless both complete within `timeout`.

	 Empty data puts no bytes on the stream but starts the connection, and the
	 send does not return until the handshake has finished. A peer that
	 presented no certificate is decided on after that, still before any byte
	 moves. The failure names the validator's refusal when there was one.

	 A handshake that fails moves the connection to `failed`, and the send that
	 was waiting on it does not always hear: it then stays suspended until
	 `timeout`, which is minutes long because it has to cover a person deciding.
	 The connection's own state is therefore watched beside the send, and
	 whichever reports first ends the wait. The handler is registered before the
	 send, which is what starts the connection. */
	private static func establish(
		_ connection: NetworkConnection<TLS>,
		handshake: DCCTLSHandshake,
		timeout: Duration
	) async throws -> DCCSecureSessionInfo {
		let (failures, failure) = AsyncStream<NWError>.makeStream(bufferingPolicy: .bufferingOldest(1))
		connection.onStateUpdate { _, state in
			if case let .failed(error) = state {
				failure.yield(error)
			}
		}

		do {
			return try await DCCTransport.withTimeout(timeout, failingWith: .connectTimeout) {
				try await withThrowingTaskGroup(of: Void.self) { group in
					defer { group.cancelAll() }
					group.addTask { try await connection.send(Data()) }
					group.addTask {
						for await error in failures {
							throw error
						}
						/* The stream only ends for a cancelled task. Returning here
						 would read as the send having answered. */
						throw CancellationError()
					}
					try await group.next()
				}
				return try await handshake.establishedSession(of: connection)
			}
		} catch {
			throw await handshake.failure(for: handshakeFailure(of: connection, reportedAs: error))
		}
	}

	/** Why the handshake failed, when the connection says it did.

	 A failed handshake closes the socket, and the send waiting on it can report
	 the closed socket instead of the TLS failure that closed it. */
	private static func handshakeFailure(of connection: NetworkConnection<TLS>, reportedAs error: Error) -> Error {
		guard error is NWError, case let .failed(cause) = connection.state, case .tls = cause else { return error }
		return cause
	}
}
