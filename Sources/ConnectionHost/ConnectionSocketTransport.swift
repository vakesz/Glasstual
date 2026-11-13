// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Network

enum TransportConnection: Sendable {
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
nonisolated enum TransportTransition: Sendable {
	case ready
	case failed(NWError)
}
