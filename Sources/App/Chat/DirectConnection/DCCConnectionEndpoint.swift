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
	/// Dials a peer that is already listening.
	static func connect(
		toHost host: String,
		port: UInt16,
		interfaceName: String?,
		timeout: Duration?
	) async throws -> NetworkConnection<TCP> {
		guard host.isEmpty == false, let networkPort = NWEndpoint.Port(rawValue: port) else {
			throw DCCTransferError.badParameter
		}

		let parameters = DCCTransport.parameters(interfaceName: interfaceName, connectTimeout: timeout)
		let connection = NetworkConnection<TCP>(
			to: .hostPort(host: NWEndpoint.Host(host), port: networkPort),
			using: .parameters(initialParameters: parameters) { TCP() }
		)

		try await DCCTransport.withTimeout(timeout, failingWith: .connectTimeout) {
			/* Typed Network connections establish on first I/O. Empty data puts no
			 bytes on the stream but makes the connected event truthful. */
			try await connection.send(Data())
		}

		return connection
	}

	/** Binds the first port in `portRange` that a listener actually reaches.

	 `deadline` is the whole window binding and waiting for the peer share, not a
	 budget for each of them in turn: applying the timeout to each gave a slow
	 bind twice what the caller asked for. Pass the same instant to
	 ``accept(on:expectedPeerAddress:sendTimeout:deadline:log:)``. */
	static func bind(
		portRange: ClosedRange<UInt16>,
		deadline: ContinuousClock.Instant?
	) async throws -> DCCTransport.ListeningSession {
		try await DCCTransport.withDeadline(deadline, failingWith: .connectTimeout) {
			try await DCCTransport.startListener(portRange: portRange)
		}
	}

	/** Takes the one connection the peer makes to a bound listener.

	 A connection from anywhere other than `expectedPeerAddress` is refused and
	 the wait goes on; an empty expectation accepts the first arrival, which is
	 what is left whenever the offer named no address. One listener serves one
	 connection, so the port closes the moment a peer is accepted rather than
	 leaving somebody else a window to reach it. */
	static func accept(
		on session: DCCTransport.ListeningSession,
		expectedPeerAddress: String,
		sendTimeout: Duration?,
		deadline: ContinuousClock.Instant?,
		log: Logger
	) async throws -> NetworkConnection<TCP> {
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

					/* Typed Network connections establish on first I/O. Empty data
					 puts no bytes on the stream but makes the connected event
					 truthful. */
					try await DCCTransport.withTimeout(sendTimeout, failingWith: .connectTimeout) {
						try await candidate.send(Data())
					}

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

	/// Reads whatever the peer has sent, and reports whether the peer is done.
	static func receive(on connection: NetworkConnection<TCP>) async throws -> (Data?, Bool) {
		let message = try await connection.receive(atLeast: 1, atMost: DCCTransport.bufferSize)

		return (message.content, message.metadata.endOfStream)
	}

	/** Refuses one inbound connection.

	 Half-closing tells whoever dialled that the port is not going to answer,
	 rather than leaving them holding a socket that never carries anything, and
	 releasing the last reference lets the stack finish tearing it down. */
	private static func reject(_ connection: NetworkConnection<TCP>) async {
		try? await connection.send(Data(), endOfStream: true)
	}
}
