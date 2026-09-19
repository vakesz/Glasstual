// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What every connection in the process has sent and received.

 A running total for the session, shown by the diagnostics command. The counts
 wrap rather than trap: a long-lived session on a busy network is allowed to
 outrun the counter, and nothing branches on the number. */
nonisolated struct ConnectionTraffic {
	private(set) var messagesSent: UInt = 0
	private(set) var messagesReceived: UInt = 0
	private(set) var bandwidthIn: UInt64 = 0
	private(set) var bandwidthOut: UInt64 = 0

	mutating func noteSent(length: UInt) {
		messagesSent &+= 1
		bandwidthOut &+= UInt64(length)
	}

	mutating func noteReceived(length: UInt) {
		messagesReceived &+= 1
		bandwidthIn &+= UInt64(length)
	}
}

/** Holds off idle system sleep while a session is logged in.

 Only idle system sleep: `.userInitiated` would also disable App Nap and sudden
 and automatic termination for as long as a server is connected, none of which
 keeping the Mac awake needs. */
@MainActor
final class SleepPrevention {
	private var activity: (any NSObjectProtocol)?

	/// Takes or drops the assertion, whichever `shouldHold` asks for. Holding
	/// one that is already held, or dropping one that is not, does nothing.
	func refresh(shouldHold: Bool) {
		if shouldHold, activity == nil {
			activity = ProcessInfo.processInfo.beginActivity(
				options: .idleSystemSleepDisabled,
				reason: "Keeping the Mac awake while connected to IRC"
			)
		} else if !shouldHold, let activity {
			ProcessInfo.processInfo.endActivity(activity)
			self.activity = nil
		}
	}
}
