// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Network

/** The established connection a DCC feature talks over, plain or TLS.

 The two differ only in the protocol type Network.framework is specialised on,
 so ``DCCTransfer`` and ``DirectChatSocket`` hold this instead of becoming
 generic, and read and write the same bytes either way. */
nonisolated enum DCCConnection: Sendable {
	case plain(NetworkConnection<TCP>)
	/// A TLS connection whose peer has been decided on, and what it negotiated.
	case secure(NetworkConnection<TLS>, DCCSecureSessionInfo)

	/// `nil` for a plain connection.
	var secureSession: DCCSecureSessionInfo? {
		guard case let .secure(_, session) = self else { return nil }
		return session
	}

	/// Writes bytes; empty data with `endOfStream` half-closes.
	func send(_ data: Data, endOfStream: Bool = false) async throws {
		switch self {
		case let .plain(connection): try await connection.send(data, endOfStream: endOfStream)
		case let .secure(connection, _): try await connection.send(data, endOfStream: endOfStream)
		}
	}

	/// Reads whatever the peer has sent, and reports whether the peer is done.
	func receive() async throws -> (Data?, Bool) {
		switch self {
		case let .plain(connection):
			let message = try await connection.receive(atLeast: 1, atMost: DCCTransport.bufferSize)
			return (message.content, message.metadata.endOfStream)
		case let .secure(connection, _):
			let message = try await connection.receive(atLeast: 1, atMost: DCCTransport.bufferSize)
			return (message.content, message.metadata.endOfStream)
		}
	}
}
