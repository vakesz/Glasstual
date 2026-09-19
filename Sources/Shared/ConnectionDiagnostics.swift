// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

/// A shared monotonic origin correlates app and XPC milestones without recording
/// server names, account names, credentials, or IRC message contents.
nonisolated struct ConnectionDiagnostics: Codable, Sendable, Equatable {
	let identifier: UUID
	let requestedAt: TimeInterval

	init() {
		identifier = UUID()
		requestedAt = ProcessInfo.processInfo.systemUptime
	}

	enum Event: String, Codable, Sendable {
		case requested, serviceRequested, hostStarted, transportStarted
		case certificateEvaluationStarted, certificateEvaluationCompleted, certificateAccepted
		case transportReady, transportFailed, capabilitiesCompleted, registered, identificationWritten, authenticated
		case firstJoin, disconnected
	}

	/** One `Logger`, and `debug` rather than `info`.

	 Every milestone here is a timing trace: a dozen of them per connection
	 attempt, useful only when someone is measuring where a connection spends
	 its time. `debug` is the level the unified log keeps out of the persisted
	 store and out of `log show` unless it is asked for, which is what makes the
	 trace free to emit on every attempt. The state a developer or a user acts
	 on — connected, secured, disconnected, failed — is logged by the paths that
	 decide it, at the level that decision deserves.

	 The subsystem is the application's, rather than the running product's: both
	 processes record into this trace, and one connection attempt is one sequence
	 of milestones in one log stream whichever side emitted them. */
	private static let logger = Logger(subsystem: LogSubsystem.application, category: "ConnectionDiagnostics")

	func record(_ event: Event) {
		let elapsed = ProcessInfo.processInfo.systemUptime - requestedAt
		Self.logger.debug(
			"Attempt \(identifier.uuidString, privacy: .public) \(event.rawValue, privacy: .public) elapsed=\(elapsed, privacy: .public)s"
		)
	}
}
