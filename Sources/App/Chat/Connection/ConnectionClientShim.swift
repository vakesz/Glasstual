// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os
import Security

/** The object NSXPC exports for the host's callbacks.

 `RemoteConnectionClientProtocol` refines `Sendable` so the connection host can
 push through the proxy from inside its actor. That makes every conformer
 `Sendable`, which `Connection` — main-actor state, and plenty of it — cannot
 be, so the conformance lives on this instead. It holds nothing but the event
 continuation and hands every callback straight to it. */
final class ConnectionClientShim: NSObject, RemoteConnectionClientProtocol {
	private let events: AsyncStream<ConnectionEvent>.Continuation

	init(events: AsyncStream<ConnectionEvent>.Continuation) {
		self.events = events

		super.init()
	}

	/* Every callback below arrives on the NSXPC queue. They only hand the value
	 to `events`; the main actor does the work, in the order the host sent it. */

	func willConnect(toProxy proxyHost: String, port proxyPort: UInt16) {
		events.yield(.willConnectToProxy(host: proxyHost, port: proxyPort))
	}

	func didConnect(toHost host: String?) {
		events.yield(.didConnect(host: host))
	}

	func didSecureConnection(
		withProtocolType protocolType: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t,
		leafCertificate: Data?
	) {
		events.yield(.didSecure(protocolType: protocolType, cipherSuite: cipherSuite, leafCertificate: leafCertificate))
	}

	func didCloseReadStream() {
		events.yield(.didCloseReadStream)
	}

	func didDisconnect(withError disconnectError: Error?) {
		events.yield(.didDisconnect(error: disconnectError))
	}

	func didReceive(_ lines: [Data], acknowledge: @escaping @Sendable () -> Void) {
		events.yield(.didReceive(lines, acknowledge: acknowledge))
	}

	func requestInsecureCertificateTrust(_ trustBlock: @escaping TrustDecisionHandler) {
		events.yield(.requestInsecureCertificateTrust(trustBlock))
	}

	func willSend(_ data: Data) {
		events.yield(.willSend(data))
	}

	func didSendData() {
		events.yield(.didSendData)
	}

	func didNegotiateWebSocketSubprotocol(_ subprotocol: String?) {
		events.yield(.negotiatedWebSocketSubprotocol(subprotocol))
	}
}
