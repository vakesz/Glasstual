// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Which server the next connect dials, and which one the current connection dialled.
struct EndpointSelection {
	/// Where the next connect goes, when it is not the next configured server.
	var pending: PendingIRCEndpoint?
	/// The configured server this connection selected, while it lasts. `nil`
	/// for an explicit endpoint that is none of them.
	var current: ServerEndpoint?
	/// The index in `config.serverList` the last connect attempt dialled, or
	/// `nil` when none has been dialled yet. It survives teardown, so the next
	/// attempt moves on to the next server.
	var lastIndex: UInt?

	/// What one connect dials.
	struct Target: Equatable {
		let host: String
		let port: UInt16
		let secured: Bool
		let reason: PendingIRCEndpoint.Reason?
	}

	/** Takes the pending endpoint, or advances the rotation over `servers`.

	 A pending endpoint whose host is a valid address is dialled as it is. Any
	 other connect takes the server `retrying` names, or the one after the last
	 dialled, wrapping at the end. `servers` must not be empty. */
	mutating func take(from servers: [ServerEndpoint], retrying identifier: String?) -> Target {
		precondition(servers.isEmpty == false)
		let endpoint = pending
		pending = nil
		current = endpoint?.credentialEndpoint(among: servers)
		if let endpoint, endpoint.host.isValidInternetAddress {
			return Target(host: endpoint.host, port: endpoint.port, secured: endpoint.secured, reason: endpoint.reason)
		}

		let retryIndex = servers.firstIndex { $0.uniqueIdentifier == identifier }
		let nextIndex = retryIndex.map(UInt.init)
			?? lastIndex.map { ($0 + 1) % UInt(servers.count) } ?? 0
		lastIndex = nextIndex
		let selected = servers[Int(nextIndex)]
		current = selected
		return Target(
			host: selected.serverAddress,
			port: selected.serverPort,
			secured: selected.prefersSecuredConnection,
			reason: endpoint?.reason
		)
	}
}
