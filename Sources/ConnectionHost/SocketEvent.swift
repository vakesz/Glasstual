// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Security

/// Everything the transport reports, in the order it happened.
///
/// The socket publishes the results of its async Network.framework operations
/// here, and the host reads them from one `AsyncStream` in wire order.
enum SocketEvent: Sendable {
	case willConnectToProxy(host: String, port: UInt16)
	case connected(host: String?)
	case secured(protocolVersion: tls_protocol_version_t, cipherSuite: tls_ciphersuite_t)
	/// The complete lines of one read. The transport reads no further until
	/// `acknowledged` finishes, which the host hands to the application's reply.
	case received([Data], acknowledged: AsyncStream<Void>.Continuation)
	case willSend(Data)
	case didSend
	case closedReadStream
	case disconnected(ConnectionError?)
}
