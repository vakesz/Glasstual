// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// When the server was last heard from, and the PING timer that watches it.
struct ConnectionLiveness {
	let pongTimer: SessionTimer
	var lastMessageReceived: TimeInterval = 0
	/// Whether the user has already been told this connection went quiet, so
	/// that the warning is printed once rather than every timeout.
	var timeoutWarningShown = false

	mutating func resetForTeardown() {
		lastMessageReceived = 0
		timeoutWarningShown = false
	}
}

extension ServerSession {
	func startPongTimer() {
		guard !liveness.pongTimer.isActive else { return }
		liveness.pongTimer.start(ConnectionTimerPolicy.pongCheckInterval, repeats: true)
	}

	func stopPongTimer() {
		guard liveness.pongTimer.isActive else { return }
		liveness.pongTimer.stop()
	}

	func onPongTimer() {
		guard isLoggedIn else {
			stopPongTimer()
			return
		}

		let elapsed = Date().timeIntervalSince1970 - liveness.lastMessageReceived
		switch ConnectionTimerPolicy.pongAction(
			elapsed: elapsed,
			eofReceived: socket?.EOFReceived ?? false,
			disconnectOnTimeout: config.performDisconnectOnPongTimer,
			pingEnabled: config.performPongTimer,
			warningAlreadyShown: liveness.timeoutWarningShown
		) {
		case .disconnect:
			printDebugInformation(String(localized: .IRC.minutesHaveElapsedSinceLastResponse(Float(elapsed / 60))), in: nil)
			disconnect()
		case .warnTimeout:
			liveness.timeoutWarningShown = true
			printDebugInformation(String(localized: .IRC.minutesHaveElapsedSinceLastResponseFromThis(Float(elapsed / 60))), in: nil)
		case .ping:
			if let serverAddress {
				sendPing(serverAddress)
			}
		case .none:
			break
		}
	}
}
