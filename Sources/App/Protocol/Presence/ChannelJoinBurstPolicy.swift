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

/// Explicit playback stays historical for its entire delivery. Only known legacy
/// bouncers use the short timestamp heuristic; an untagged live message is never replay.
enum ChannelJoinBurstPolicy {
	static let gracePeriod: TimeInterval = 10

	static func isJoinBurstLine(
		joinedAt: Date?,
		now: Date,
		isHistoric: Bool,
		hasServerTime: Bool,
		receivedAt: Date,
		isKnownBouncer: Bool = false
	) -> Bool {
		if isHistoric {
			return true
		}
		guard isKnownBouncer, hasServerTime, let joinedAt,
		      (0 ... gracePeriod).contains(now.timeIntervalSince(joinedAt)) else { return false }
		return receivedAt <= joinedAt
	}
}

/// Whether a line is behind the read marker the server last reported.
enum ChannelReadMarkerPolicy {
	/** Whether the user has already read `receivedAt`.

	 `marker` is the newest point this client has told the server it read, or
	 the newest point the server told it about in a `MARKREAD`. A line at or
	 before it was read somewhere else — another client, another session — so
	 it is not this channel's news either. Without a marker nothing is known
	 to have been read. */
	static func lineIsRead(receivedAt: Date, marker: Date?) -> Bool {
		guard let marker else { return false }

		return receivedAt <= marker
	}
}

@MainActor
extension IRCClient {
	/** Whether an inbound line arrived already seen, so it prints without
	 touching the unread count, the highlight badge or a notification.

	 Decided at arrival because printing is asynchronous. */
	func lineArrivedAlreadySeen(_ message: Message, in channel: IRCChannel?) -> Bool {
		guard let channel else { return false }

		return lineIsJoinBurst(message, in: channel)
			|| ChannelReadMarkerPolicy.lineIsRead(
				receivedAt: message.receivedAt,
				marker: readMarkerSentDates[channel.uniqueIdentifier]
			)
	}

	/** Whether the line came in with the post-join replay burst.

	 Separate from `lineArrivedAlreadySeen` because the read marker must not
	 gate itself: a line behind the marker cannot move the marker forward
	 anyway, while a replayed line ahead of it could, and must not. */
	func lineIsJoinBurst(_ message: Message?, in channel: IRCChannel?) -> Bool {
		guard let message, let channel else { return false }

		return ChannelJoinBurstPolicy.isJoinBurstLine(
			joinedAt: channel.joinedAt,
			now: Date(),
			isHistoric: message.isHistoric,
			hasServerTime: message.hasServerTime,
			receivedAt: message.receivedAt,
			isKnownBouncer: isConnectedToZNC
		)
	}
}
