// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The channels waiting to be joined, and the pacing they are joined at.

 Autojoin is a queue with two timers over it: one that sends the next batch of
 `JOIN`s, and one that tells the user why nothing has been joined yet when the
 queue is waiting on services. */
struct AutojoinSchedule {
	/// The channels still to join, or `nil` when no autojoin is in flight.
	var pendingChannels: [Conversation]?
	let timer: SessionTimer
	let delayedWarningTimer: SessionTimer
	/// How many times the user has been told the join is still waiting.
	var delayedWarningCount: UInt = 0
}

enum AutojoinPolicy {
	static let delayedWarningInterval: TimeInterval = 90
	static let maximumDelayedWarningCount: UInt = 3

	/** How long the session waits for an identification nothing in the session
	 is actually sending.

	 `noteNickServIdentificationWritten()` starts a thirty second deadline when
	 the session itself wrote the IDENTIFY line. Turning on "wait for NickServ"
	 without any login command that identifies — a bouncer that authenticates
	 for you, a server that recognises the certificate — armed nothing, so the
	 join list sat unsent for the rest of the session. This deadline covers that
	 wait, and is measured in warning intervals so that the user has been told
	 what is being waited for before the session gives up and joins anyway. */
	static let unattendedAuthenticationDeadline: TimeInterval =
		delayedWarningInterval * TimeInterval(maximumDelayedWarningCount)

	/** How long to pause after the connect commands were sent before joining.

	 This delay applies to join lists without NickServ identification.
	 Zero disables it; identification uses its own confirmation deadline. */
	static func delayAfterConnectCommands(
		waitsForConnectCommands: Bool,
		hasConnectCommands: Bool,
		configuredDelay: TimeInterval
	) -> TimeInterval {
		guard waitsForConnectCommands, hasConnectCommands else { return 0 }
		return max(0, min(configuredDelay, ServerConfigDefaults.maximumAutojoinConnectCommandDelay))
	}
}

extension ServerSession {
	func startAutojoinTimer() {
		guard !autojoin.timer.isActive else { return }
		let interval = startup.requiresAuthentication ? 0 : environment.settings.autojoinDelayAfterIdentification
		guard interval > 0 else {
			onAutojoinTimer()
			return
		}
		autojoin.timer.start(interval, repeats: false)
	}

	func stopAutojoinTimer() {
		guard autojoin.timer.isActive else { return }
		autojoin.timer.stop()
	}

	/** Joins every pending channel at once.

	 One JOIN per line that fits the server's budget, and the connection host's
	 flood control paces the lines; the two-channels-every-few-seconds throttle
	 this used to run on top of that only made a long channel list take tens of
	 seconds to arrive. */
	func onAutojoinTimer() {
		guard isLoggedIn, !isTerminating, !isQuitting, !isDisconnecting,
		      isAutojoining, let channels = autojoin.pendingChannels else { return }
		autojoin.pendingChannels = nil
		joinChannels(channels)
		isAutojoining = false
		isAutojoined = true
	}

	/// Forgets a join list that has not been sent yet.
	func cancelPendingAutojoin() {
		autojoin.pendingChannels = nil
		isAutojoining = false
	}

	func startAutojoinDelayedWarningTimer() {
		guard !autojoin.delayedWarningTimer.isActive else { return }
		autojoin.delayedWarningTimer.start(AutojoinPolicy.delayedWarningInterval, repeats: true)
	}

	func stopAutojoinDelayedWarningTimer() {
		guard autojoin.delayedWarningTimer.isActive else { return }
		autojoin.delayedWarningTimer.stop()
	}

	func onAutojoinDelayedWarningTimer() {
		guard isLoggedIn, !config.hideAutojoinDelayedWarnings,
		      autojoin.delayedWarningCount < AutojoinPolicy.maximumDelayedWarningCount
		else {
			stopAutojoinDelayedWarningTimer()
			return
		}

		autojoin.delayedWarningCount += 1
		let text = String(localized: .IRC.joiningChannelsHasBeenDelayedBecause)
		printDebugInformation(toConsole: text)
		if let conversation = output?.selectedConversation(on: self) {
			printDebugInformation(text, in: conversation)
		}
	}

	func performAutoJoin() {
		performAutoJoin(initiatedByUser: false)
	}

	func performAutoJoin(initiatedByUser: Bool) {
		guard isLoggedIn, !isTerminating, !isQuitting, !isDisconnecting, !isAutojoining else { return }
		stopAutojoinDelayedWarningTimer()

		if !initiatedByUser {
			guard !isAutojoined else { return }
			if znc.isConnected, config.zncIgnoreConfiguredAutojoin {
				isAutojoined = true
				return
			}
			guard startup.canJoin else {
				beginUnattendedAuthenticationWait()
				return
			}
		}

		let channels = conversationList.filter { $0.isChannel && !$0.isActive && $0.config.autoJoin }
		guard !channels.isEmpty else {
			isAutojoining = false
			isAutojoined = true
			return
		}

		isAutojoining = true
		autojoin.pendingChannels = channels
		startAutojoinTimer()
	}
}
