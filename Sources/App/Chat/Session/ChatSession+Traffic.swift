// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension ChatSession {
	// MARK: - Traffic counters

	var messagesSent: UInt {
		traffic.messagesSent
	}

	var messagesReceived: UInt {
		traffic.messagesReceived
	}

	var bandwidthIn: UInt64 {
		traffic.bandwidthIn
	}

	var bandwidthOut: UInt64 {
		traffic.bandwidthOut
	}

	func noteMessageSent(length: UInt) {
		traffic.noteSent(length: length)
	}

	func noteMessageReceived(length: UInt) {
		traffic.noteReceived(length: length)
	}
}
