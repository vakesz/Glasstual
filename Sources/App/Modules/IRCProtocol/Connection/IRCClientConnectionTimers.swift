/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
	static let retryInterval: TimeInterval = 240
	static let timeoutInterval: TimeInterval = 360

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
	@objc(stopAllTimers)
	func stopAllTimers() {
		stopAutojoinTimer()
		stopAutojoinDelayedWarningTimer()
		stopAutojoinNextJoinTimer()
		stopISONTimer()
		stopReconnectTimer()
		stopRetryTimer()
		stopPongTimer()
		stopWhoTimer()
	}

	@objc(startPongTimer)
	func startPongTimer() {
		guard !pongTimer.timerIsActive else { return }
		pongTimer.start(IRCClientConnectionTimerPolicy.pongCheckInterval, onRepeat: true)
	}

	@objc(stopPongTimer)
	func stopPongTimer() {
		guard pongTimer.timerIsActive else { return }
		pongTimer.stop()
	}

	@objc(onPongTimer)
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

	@objc(startReconnectTimer)
	func startReconnectTimer() {
		let enabled = reconnectEnabledBecauseOfSleepMode
			? !config.autoSleepModeDisconnect
			: config.autoReconnect
		guard enabled, !reconnectTimer.timerIsActive else { return }
		reconnectTimer.start(IRCClientConnectionTimerPolicy.reconnectInterval, onRepeat: true)
	}

	@objc(stopReconnectTimer)
	func stopReconnectTimer() {
		guard reconnectTimer.timerIsActive else { return }
		reconnectTimer.stop()
	}

	@objc(onReconnectTimer)
	func onReconnectTimer() {
		guard !isConnecting, !isConnected else { return }
		connect(.reconnect)
	}

	@objc(startRetryTimer)
	func startRetryTimer() {
		guard !retryTimer.timerIsActive else { return }
		retryTimer.start(IRCClientConnectionTimerPolicy.retryInterval)
	}

	@objc(stopRetryTimer)
	func stopRetryTimer() {
		guard retryTimer.timerIsActive else { return }
		retryTimer.stop()
	}

	@objc(onRetryTimer)
	func onRetryTimer() {
		guard isConnected else { return }
		addDisconnectCallback { [weak self] in
			self?.connect(.retry)
		}
		disconnect()
	}
}
