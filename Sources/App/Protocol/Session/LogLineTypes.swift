// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The raw values are persisted — they are written into the renderer
 attribute dictionary and archived with every log line — so a number may never
 be reused and a new case may only ever be appended. `offTheRecordEncryptionStatus`
 stays at 15 for the sake of already-archived lines even though OTR is gone. */
enum LogLineType: UInt, Codable, Sendable {
	case undefined = 0
	case action = 1
	case actionNoHighlight = 2
	case ctcp = 3
	case ctcpQuery = 4
	case ctcpReply = 5
	case dccFileTransfer = 6
	case debug = 7
	case invite = 8
	case join = 9
	case kick = 10
	case kill = 11
	case mode = 12
	case nick = 13
	case notice = 14
	case offTheRecordEncryptionStatus = 15
	case part = 16
	case privateMessage = 17
	case privateMessageNoHighlight = 18
	case quit = 19
	case topic = 20
	case website = 21

	/// Something a person said, as opposed to an event the client narrates —
	/// a join, a mode, a topic. The unread marker is placed before the first
	/// of these, not before the first line of any kind.
	nonisolated var isConversation: Bool { // nonisolated: pure
		switch self {
		case .action, .actionNoHighlight, .notice, .privateMessage, .privateMessageNoHighlight:
			true
		default:
			false
		}
	}

	/// A message whose body the renderer scans for the channel's members and
	/// the reader's highlight keywords.
	nonisolated var mentionsMembers: Bool { // nonisolated: pure
		self == .privateMessage || self == .action
	}
}

/** Persisted alongside the log line; see `LogLineType`. */
enum LogLineMemberType: UInt, Codable, Sendable {
	case normal = 0
	case localUser = 1
}

/** Persisted alongside the log line; see `LogLineType`. */
enum LogLineDeliveryState: UInt, Codable, Sendable {
	case none = 0
	case pending = 1
	case delivered = 2
	case failed = 3
}
