// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// The transport and shutdown status of one server connection attempt.
/// A connected transport remains connected while QUIT or close is in flight;
/// callers stop treating it as usable by also checking the shutdown status.
struct SessionConnectionState {
	enum Transport {
		case idle
		case preparingCredentials
		case connecting
		case connected
	}

	enum Shutdown {
		case none
		case quitting
		case disconnecting
		case disconnectingAfterQuit
	}

	private(set) var transport: Transport
	private(set) var shutdown: Shutdown

	init(transport: Transport = .idle, shutdown: Shutdown = .none) {
		self.transport = transport
		self.shutdown = shutdown
	}

	var isConnecting: Bool {
		transport == .preparingCredentials || transport == .connecting
	}

	var isConnected: Bool {
		transport == .connected
	}

	var isQuitting: Bool {
		shutdown == .quitting || shutdown == .disconnectingAfterQuit
	}

	var isDisconnecting: Bool {
		shutdown == .disconnecting || shutdown == .disconnectingAfterQuit
	}

	var canConnect: Bool {
		transport == .idle && shutdown == .none
	}

	mutating func beginPreparation() {
		transport = .preparingCredentials
		shutdown = .none
	}

	mutating func finishPreparation() {
		transport = .connecting
	}

	mutating func didConnect() {
		transport = .connected
	}

	mutating func beginQuit() {
		shutdown = .quitting
	}

	mutating func beginDisconnect() {
		shutdown = isQuitting ? .disconnectingAfterQuit : .disconnecting
	}

	/// Credential work has no socket to finish closing. This transition also
	/// releases a cancelled attempt so its disconnect callbacks can reconnect.
	mutating func cancelPreparation() {
		guard transport == .preparingCredentials else { return }
		transport = .idle
		if shutdown == .quitting {
			shutdown = .none
		} else if shutdown == .disconnectingAfterQuit {
			shutdown = .disconnecting
		}
	}

	mutating func clearTransport() {
		transport = .idle
	}

	mutating func clearShutdown() {
		shutdown = .none
	}
}
