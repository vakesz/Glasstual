// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os
import Security

/** Everything the connection host reports. NSXPC delivers these on its own
 queue; they are drained on the main actor in arrival order so that the session
 sees them in wire order. */
enum ConnectionEvent: Sendable {
	case willConnectToProxy(host: String, port: UInt16)
	case didConnect(host: String?)
	case didSecure(protocolType: tls_protocol_version_t, cipherSuite: tls_ciphersuite_t, leafCertificate: Data?)
	case didCloseReadStream
	case didDisconnect(error: Error?)
	/// One read's lines, and the reply that lets the host read the next.
	case didReceive([Data], acknowledge: @Sendable () -> Void)
	case requestInsecureCertificateTrust(TrustDecisionHandler)
	case willSend(Data)
	case didSendData
	/// The WebSocket upgrade finished; nil when the server chose no subprotocol.
	case negotiatedWebSocketSubprotocol(String?)
	case serviceFailed(Error)
	case serviceInterrupted
	case serviceInvalidated
}
