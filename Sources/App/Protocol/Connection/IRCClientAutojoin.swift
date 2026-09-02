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

enum IRCClientAutojoinPolicy {
	static let delayedWarningInterval: TimeInterval = 90
	static let maximumDelayedWarningCount: UInt = 3

	static func shouldWaitForIdentification(
		isIdentifiedWithSASL: Bool,
		waitsForNickServ: Bool,
		serverHasNickServ: Bool,
		isIdentifiedWithNickServ: Bool
	) -> Bool {
		!isIdentifiedWithSASL && waitsForNickServ && serverHasNickServ && !isIdentifiedWithNickServ
	}

	/** Whether the autojoin is still owed this connection's connect commands.

	 It is a wait of its own, not an alternative to the identification wait: a
	 configuration that asks for both joins only once both have been answered. */
	static func shouldWaitForConnectCommands(
		waitsForConnectCommands: Bool,
		connectCommandsHaveSettled: Bool
	) -> Bool {
		waitsForConnectCommands && !connectCommandsHaveSettled
	}

	/** How long to pause after the connect commands were sent before joining.

	 The commands are written to the socket, not answered: a server's reply to
	 one arrives later and out of band, so the wait the option offers is a
	 delay long enough for that reply to land. Zero means nothing to wait
	 for — the option is off, or the connection has no commands to send. */
	static func delayAfterConnectCommands(
		waitsForConnectCommands: Bool,
		hasConnectCommands: Bool,
		configuredDelay: TimeInterval
	) -> TimeInterval {
		guard waitsForConnectCommands, hasConnectCommands else { return 0 }
		return max(0, min(configuredDelay, ClientConfigDefaults.maximumAutojoinConnectCommandDelay))
	}
}

@MainActor
public extension IRCClient {
	func startAutojoinTimer() {
		guard !autojoinTimer.isActive else { return }
		let interval = environment.preferences.autojoinDelayAfterIdentification
		guard interval > 0 else {
			onAutojoinTimer()
			return
		}
		autojoinTimer.start(interval, repeats: false)
	}

	func stopAutojoinTimer() {
		guard autojoinTimer.isActive else { return }
		autojoinTimer.stop()
	}

	/** Joins every pending channel at once.

	 One JOIN per line that fits the server's budget, and the connection host's
	 flood control paces the lines; the two-channels-every-few-seconds throttle
	 this used to run on top of that only made a long channel list take tens of
	 seconds to arrive. */
	func onAutojoinTimer() {
		guard isAutojoining, let channels = channelsToAutojoin else { return }
		channelsToAutojoin = nil
		joinChannels(channels)
		isAutojoining = false
		isAutojoined = true
	}

	/** Records that this connection's configured connect commands have been
	 sent, and starts the pause the user asked for before the autojoin follows.

	 With no pause to serve — no commands to send, or the option switched off —
	 the wait is over at once. */
	func markConnectCommandsPerformed() {
		guard !didPerformConnectCommands else { return }
		didPerformConnectCommands = true

		let delay = IRCClientAutojoinPolicy.delayAfterConnectCommands(
			waitsForConnectCommands: config.autojoinWaitsForConnectCommands,
			hasConnectCommands: !config.loginCommands.isEmpty,
			configuredDelay: config.autojoinDelayAfterConnectCommands
		)
		guard delay > 0 else {
			settleConnectCommands()
			return
		}

		connectCommandsSettlingTask?.cancel()
		connectCommandsSettlingTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(delay))

			guard Task.isCancelled == false, let self else { return }

			settleConnectCommands()
		}
	}

	/** Ends that wait and releases an autojoin held back by it. Every other
	 wait still applies: `performAutoJoin()` re-checks them. */
	func settleConnectCommands() {
		guard !connectCommandsHaveSettled else { return }
		connectCommandsSettlingTask = nil
		connectCommandsHaveSettled = true
		guard config.autojoinWaitsForConnectCommands else { return }
		performAutoJoin()
	}

	/// Forgets the wait, so the next connection serves its own.
	func cancelConnectCommandSettling() {
		connectCommandsSettlingTask?.cancel()
		connectCommandsSettlingTask = nil
		didPerformConnectCommands = false
		connectCommandsHaveSettled = false
	}

	/// Forgets a join list that has not been sent yet.
	func cancelPendingAutojoin() {
		channelsToAutojoin = nil
		isAutojoining = false
	}

	func startAutojoinDelayedWarningTimer() {
		guard !autojoinDelayedWarningTimer.isActive else { return }
		autojoinDelayedWarningTimer.start(IRCClientAutojoinPolicy.delayedWarningInterval, repeats: true)
	}

	func stopAutojoinDelayedWarningTimer() {
		guard autojoinDelayedWarningTimer.isActive else { return }
		autojoinDelayedWarningTimer.stop()
	}

	func onAutojoinDelayedWarningTimer() {
		guard isLoggedIn, !config.hideAutojoinDelayedWarnings,
		      autojoinDelayedWarningCount < IRCClientAutojoinPolicy.maximumDelayedWarningCount
		else {
			stopAutojoinDelayedWarningTimer()
			return
		}

		autojoinDelayedWarningCount += 1
		let text = IRCConnectionStrings.autojoinDelayedForIdentification
		printDebugInformation(toConsole: text)
		if let channel = output?.selectedChannel(on: self) {
			printDebugInformation(text, in: channel)
		}
	}

	func performAutoJoin() {
		performAutoJoin(initiatedByUser: false)
	}

	func performAutoJoin(initiatedByUser: Bool) {
		guard !isAutojoining else { return }
		stopAutojoinDelayedWarningTimer()

		if !initiatedByUser {
			guard !isAutojoined else { return }
			if isConnectedToZNC, config.zncIgnoreConfiguredAutojoin {
				isAutojoined = true
				return
			}
			guard !IRCClientAutojoinPolicy.shouldWaitForIdentification(
				isIdentifiedWithSASL: isCapabilityEnabled(.isIdentifiedWithSASL),
				waitsForNickServ: config.autojoinWaitsForNickServ,
				serverHasNickServ: serverHasNickServ,
				isIdentifiedWithNickServ: userIsIdentifiedWithNickServ
			) else { return }
			guard !IRCClientAutojoinPolicy.shouldWaitForConnectCommands(
				waitsForConnectCommands: config.autojoinWaitsForConnectCommands,
				connectCommandsHaveSettled: connectCommandsHaveSettled
			) else { return }
		}

		let channels = channelList.filter { $0.isChannel && !$0.isActive && $0.config.autoJoin }
		guard !channels.isEmpty else {
			isAutojoining = false
			isAutojoined = true
			return
		}

		isAutojoining = true
		channelsToAutojoin = channels
		startAutojoinTimer()
	}
}
