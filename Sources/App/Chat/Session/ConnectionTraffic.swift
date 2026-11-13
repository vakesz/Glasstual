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
