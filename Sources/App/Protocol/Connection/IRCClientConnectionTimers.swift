/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

enum IRCClientConnectionTimerPolicy {
	static let pingInterval: TimeInterval = 270
	static let pongCheckInterval: TimeInterval = 30
	static let reconnectInterval: TimeInterval = 20
	static let maximumReconnectInterval: TimeInterval = 300
	static let retryInterval: TimeInterval = 240
	static let timeoutInterval: TimeInterval = 360

	/** How long to wait before reconnection attempt number `attempt`.

	 A fixed twenty seconds forever is a client that keeps knocking at the same
	 rate whether the server bounced once or has been down since yesterday, and
	 a network outage has every client on it knock in lockstep. The delay
	 doubles from twenty seconds to a five-minute ceiling, and `jitter` — a
	 fraction the caller draws at random — takes up to a quarter of it back off
	 again so that the attempts spread out instead of arriving together. */
	static func reconnectDelay(attempt: UInt, jitter: Double) -> TimeInterval {
		// Capped before the shift so that a long-running client cannot overflow it.
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

@MainActor
public extension IRCClient {
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
		readMarkerTimer.stop()
	}

	func startPongTimer() {
		guard !pongTimer.isActive else { return }
		pongTimer.start(IRCClientConnectionTimerPolicy.pongCheckInterval, repeats: true)
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
		switch IRCClientConnectionTimerPolicy.pongAction(
			elapsed: elapsed,
			eofReceived: socket?.EOFReceived ?? false,
			disconnectOnTimeout: config.performDisconnectOnPongTimer,
			pingEnabled: config.performPongTimer,
			warningAlreadyShown: timeoutWarningShownToUser
		) {
		case .disconnect:
			printDebugInformation(IRCConnectionStrings.timeout(minutes: elapsed / 60), in: nil)
			disconnect()
		case .warnTimeout:
			timeoutWarningShownToUser = true
			printDebugInformation(IRCConnectionStrings.possibleTimeout(minutes: elapsed / 60), in: nil)
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
	 than the last: a disconnect that leaves `reconnectEnabled` set brings the
	 client back here, and `onReconnectTimer` re-arms the schedule itself when
	 the attempt it started never got as far as connecting. */
	func startReconnectTimer() {
		guard isTerminating == false else { return }
		let enabled = reconnectEnabledBecauseOfSleepMode
			? !config.autoSleepModeDisconnect
			: config.autoReconnect
		guard enabled, !reconnectTimer.isActive else { return }
		let delay = IRCClientConnectionTimerPolicy.reconnectDelay(
			attempt: reconnectAttemptCount,
			jitter: .random(in: 0 ... 1)
		)
		reconnectAttemptCount &+= 1
		reconnectTimer.start(delay, repeats: false)
	}

	func stopReconnectTimer() {
		guard reconnectTimer.isActive else { return }
		reconnectTimer.stop()
	}

	func onReconnectTimer() {
		guard !isConnecting, !isConnected else { return }

		connect(.reconnect)

		/* `connect` refuses while the machine is asleep, while the client is
		 quitting, and when there is no endpoint to take. Nothing else would put
		 the schedule back, so it is put back here rather than letting the one
		 refusal end automatic reconnection for the session. */
		guard !isConnecting, !isConnected, !isTerminating, reconnectEnabled else { return }

		startReconnectTimer()
	}

	func startRetryTimer() {
		guard !retryTimer.isActive else { return }
		retryTimer.start(IRCClientConnectionTimerPolicy.retryInterval)
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
