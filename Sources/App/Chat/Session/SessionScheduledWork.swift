// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Delayed work the session started and must be able to cancel.

 Each delay is cancellable so that a reconnect inside its window cannot have a
 stale block act on the new session. */
struct SessionScheduledWork {
	/// The disconnect that follows a `QUIT` if the server does not close first.
	var delayedDisconnect: SessionTimer?
	/// A connect or reconnect waiting out its delay.
	var connection: Task<Void, Never>?
	/// Confirmations the user has not answered yet, by request.
	var confirmations: [UUID: Task<Void, Never>] = [:]
	/// Channels to join again after a kick, by conversation identifier.
	var rejoins: [String: SessionTimer] = [:]

	mutating func cancelConnection() {
		connection?.cancel()
		connection = nil
	}

	/// What ending the session's pending work cancels. Not the delayed
	/// disconnect, which is what ends the connection.
	mutating func cancelPending() {
		confirmations.values.forEach { $0.cancel() }
		confirmations.removeAll()
		cancelConnection()
		rejoins.values.forEach { $0.stop() }
		rejoins.removeAll()
	}

	/// Everything, for a session that is going away.
	func cancelAll() {
		delayedDisconnect?.stop()
		connection?.cancel()
		rejoins.values.forEach { $0.stop() }
		confirmations.values.forEach { $0.cancel() }
	}
}
