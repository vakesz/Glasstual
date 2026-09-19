// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Whether and when the session comes back after a connection ends.

 Reconnecting is not one flag: a disconnect the user asked for must not come
 back, one the sleep handler caused must, and the interval between attempts
 grows with how many have already failed. */
struct ReconnectSchedule {
	/// Whether the next disconnect should be followed by a reconnect.
	var isEnabled = false
	/// Whether ``isEnabled`` was set by going to sleep rather than by the
	/// user, which is what tells waking up to reconnect.
	var isEnabledForSleepMode = false
	/// How many attempts have been scheduled since the last successful
	/// registration, which is what the backoff is computed from.
	var attemptCount: UInt = 0
	/// Seconds to wait before the connection this schedule is holding back.
	var connectDelay: UInt = 0
	/// Whether the user has already been told this connection went quiet, so
	/// that the warning is printed once rather than every timeout.
	var timeoutWarningShown = false
	let timer: SessionTimer
}

enum ConnectionTimerPolicy {
	static let pingInterval: TimeInterval = 270
	static let pongCheckInterval: TimeInterval = 30
	static let reconnectInterval: TimeInterval = 20
	static let maximumReconnectInterval: TimeInterval = 300
	static let retryInterval: TimeInterval = 240
	static let timeoutInterval: TimeInterval = 360

	/** How long to wait before reconnection attempt number `attempt`.

	 A fixed twenty seconds forever is a session that keeps knocking at the same
	 rate whether the server bounced once or has been down since yesterday, and
	 a network outage has every session on it knock in lockstep. The delay
	 doubles from twenty seconds to a five-minute ceiling, and `jitter` — a
	 fraction the caller draws at random — takes up to a quarter of it back off
	 again so that the attempts spread out instead of arriving together. */
	static func reconnectDelay(attempt: UInt, jitter: Double) -> TimeInterval {
		// Capped before the shift so that a long-running session cannot overflow it.
		let doublings = min(attempt, 8)
		let backoff = min(reconnectInterval * TimeInterval(1 << doublings), maximumReconnectInterval)
		let spread = backoff * 0.25 * min(max(jitter, 0), 1)

		return max(1, backoff - spread)
	}

	enum PongAction: Equatable {
		case none
		case ping
		case warnTimeout
		case disconnect
	}

	static func pongAction(
		elapsed: TimeInterval,
		eofReceived: Bool,
		disconnectOnTimeout: Bool,
		pingEnabled: Bool,
		warningAlreadyShown: Bool
	) -> PongAction {
		if elapsed >= timeoutInterval {
			if eofReceived || disconnectOnTimeout {
				return .disconnect
			}
			return warningAlreadyShown ? .none : .warnTimeout
		}
		if elapsed >= pingInterval, pingEnabled {
			return .ping
		}
		return .none
	}
}

extension ServerSession {
	func stopAllTimers() {
		stopAutojoinTimer()
		stopAutojoinDelayedWarningTimer()
		cancelPendingAutojoin()
		stopISONTimer()
		stopReconnectTimer()
		stopRetryTimer()
		stopPongTimer()
		stopSASLTimeoutTimer()
		stopWhoTimer()
		readMarkers.timer.stop()
	}

	func startPongTimer() {
		guard !pongTimer.isActive else { return }
		pongTimer.start(ConnectionTimerPolicy.pongCheckInterval, repeats: true)
	}

	func stopPongTimer() {
		guard pongTimer.isActive else { return }
		pongTimer.stop()
	}

	func onPongTimer() {
		guard isLoggedIn else {
			stopPongTimer()
			return
		}

		let elapsed = Date().timeIntervalSince1970 - lastMessageReceived
		switch ConnectionTimerPolicy.pongAction(
			elapsed: elapsed,
			eofReceived: socket?.EOFReceived ?? false,
			disconnectOnTimeout: config.performDisconnectOnPongTimer,
			pingEnabled: config.performPongTimer,
			warningAlreadyShown: reconnect.timeoutWarningShown
		) {
		case .disconnect:
			printDebugInformation(String(localized: .IRC.minutesHaveElapsedSinceLastResponse(Float(elapsed / 60))), in: nil)
			disconnect()
		case .warnTimeout:
			reconnect.timeoutWarningShown = true
			printDebugInformation(String(localized: .IRC.minutesHaveElapsedSinceLastResponseFromThis(Float(elapsed / 60))), in: nil)
		case .ping:
			if let serverAddress {
				sendPing(serverAddress)
			}
		case .none:
			break
		}
	}

	/** Schedules the next reconnection attempt.

	 The run is one-shot rather than repeating because each attempt waits longer
	 than the last: a disconnect that leaves `reconnect.isEnabled` set brings the
	 session back here, and `onReconnectTimer` re-arms the schedule itself when
	 the attempt it started never got as far as connecting. */
	func startReconnectTimer() {
		guard isTerminating == false else { return }
		let enabled = reconnect.isEnabledForSleepMode
			? !config.autoSleepModeDisconnect
			: config.autoReconnect
		guard enabled, !reconnect.timer.isActive else { return }
		let delay = ConnectionTimerPolicy.reconnectDelay(
			attempt: reconnect.attemptCount,
			jitter: .random(in: 0 ... 1)
		)
		reconnect.attemptCount &+= 1
		reconnect.timer.start(delay, repeats: false)
	}

	func stopReconnectTimer() {
		guard reconnect.timer.isActive else { return }
		reconnect.timer.stop()
	}

	func onReconnectTimer() {
		guard !isConnecting, !isConnected else { return }

		connect(.reconnect)

		/* `connect` refuses while the machine is asleep, while the session is
		 quitting, and when there is no endpoint to take. Nothing else would put
		 the schedule back, so it is put back here rather than letting the one
		 refusal end automatic reconnection for the session. */
		guard !isConnecting, !isConnected, !isTerminating, reconnect.isEnabled else { return }

		startReconnectTimer()
	}

	func startRetryTimer() {
		guard !retryTimer.isActive else { return }
		retryTimer.start(ConnectionTimerPolicy.retryInterval)
	}

	func stopRetryTimer() {
		guard retryTimer.isActive else { return }
		retryTimer.stop()
	}

	func onRetryTimer() {
		guard isConnected else { return }
		addDisconnectCallback { [weak self] in
			self?.connect(.retry)
		}
		disconnect()
	}
}

extension ServerSession {
	func noteReachabilityChanged(_ reachable: Bool) {
		guard reachable == false else { return }
		disconnectOnReachabilityChange()
	}

	/** Tears the session down when the network the user was on has gone.

	 Only a logged-in session is worth disconnecting, and only when the user
	 asked for it: a session still registering has nothing to quit, and one that
	 stays connected across a network change is the default. */
	func disconnectOnReachabilityChange() {
		guard isLoggedIn, config.performDisconnectOnReachabilityChange else { return }

		disconnectType = .reachabilityChange
		reconnect.isEnabled = true
		disconnect()
	}
}
