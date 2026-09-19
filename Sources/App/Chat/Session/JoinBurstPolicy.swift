// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Explicit playback stays replayed for its entire delivery. Only known legacy
/// bouncers use the short timestamp heuristic; an untagged live message is never replay.
enum JoinBurstPolicy {
	static let gracePeriod: TimeInterval = 10

	static func isJoinBurstLine(
		joinedAt: Date?,
		now: Date,
		isReplayed: Bool,
		hasServerTime: Bool,
		receivedAt: Date,
		isKnownBouncer: Bool = false
	) -> Bool {
		if isReplayed {
			return true
		}
		guard isKnownBouncer, hasServerTime, let joinedAt,
		      (0 ... gracePeriod).contains(now.timeIntervalSince(joinedAt)) else { return false }
		return receivedAt <= joinedAt
	}
}

@MainActor
extension ServerSession {
	/** Whether an inbound line arrived already seen, so it prints without
	 touching the unread count, the highlight badge or a notification.

	 Decided at arrival because printing is asynchronous. */
	func lineArrivedAlreadySeen(_ message: Message, in conversation: Conversation?) -> Bool {
		guard let conversation else { return false }

		if lineIsJoinBurst(message, in: conversation) {
			return true
		}

		/* The read marker is the newest point this session has told the server it
		 read, or the newest the server reported in a `MARKREAD`. A line at or
		 before it was read somewhere else, so it is not this conversation's news
		 either. Without a marker nothing is known to have been read, and a line
		 with no server time is stamped by the local clock, which says nothing
		 about where it falls against a server timestamp. */
		guard message.hasServerTime, let marker = readMarkers.sentDates[conversation.uniqueIdentifier] else {
			return false
		}

		return message.receivedAt <= marker
	}

	/** Whether the line came in with the post-join replay burst.

	 Separate from `lineArrivedAlreadySeen` because the read marker must not
	 gate itself: a line behind the marker cannot move the marker forward
	 anyway, while a replayed line ahead of it could, and must not. */
	func lineIsJoinBurst(_ message: Message?, in conversation: Conversation?) -> Bool {
		guard let message, let conversation else { return false }

		return JoinBurstPolicy.isJoinBurstLine(
			joinedAt: conversation.joinedAt,
			now: Date(),
			isReplayed: message.isReplayed,
			hasServerTime: message.hasServerTime,
			receivedAt: message.receivedAt,
			isKnownBouncer: znc.isConnected
		)
	}
}
