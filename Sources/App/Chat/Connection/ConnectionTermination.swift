// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/// The terminal transition, captured before teardown erases the connection state.
/// It carries no server, account, IRC payload, or error-description text.
nonisolated struct ConnectionTermination: Sendable {
	enum Trigger: String, Sendable {
		case hostDisconnect, serviceFailure, serviceInterrupted, serviceInvalidated, closeDeadline, localClose
	}

	enum Phase: String, Sendable {
		case requested, connecting, connected, secured, registered, authenticated, joined
	}

	let attemptIdentifier: UUID
	let elapsed: TimeInterval
	let trigger: Trigger
	let phase: Phase
	let localCloseRequested: Bool
	let receivedEOF: Bool
	let disconnectMode: SessionDisconnectMode
	let errorDomain: String?
	let errorCode: Int?

	private static let logger = Logger(subsystem: LogSubsystem.current, category: "ConnectionTermination")

	func record() {
		let domain = errorDomain ?? "none"
		let code = errorCode.map(String.init) ?? "none"
		let mode = String(describing: disconnectMode)
		let level: OSLogType = errorDomain != nil && !localCloseRequested ? .error : .info
		Self.logger.log(level: level, """
		Attempt \(attemptIdentifier.uuidString, privacy: .public) ended \
		elapsed=\(elapsed, privacy: .public)s trigger=\(trigger.rawValue, privacy: .public) \
		phase=\(phase.rawValue, privacy: .public) localClose=\(localCloseRequested, privacy: .public) \
		eof=\(receivedEOF, privacy: .public) mode=\(mode, privacy: .public) \
		errorDomain=\(domain, privacy: .public) errorCode=\(code, privacy: .public)
		""")
	}
}
