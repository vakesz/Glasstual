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

/** Whether a line belongs to the burst a server or bouncer replays right after
 a JOIN.

 A bouncer replays the tail of a conversation the moment it puts the user back
 in a channel, and a server answering `CHATHISTORY` on activation does the same.
 None of it is news: the user has either read it already or is about to scroll
 through it. Marking the channel unread, raising a highlight badge or posting a
 notification for any of it is noise, so the burst is suppressed and the read
 marker the server reports is left to decide what is genuinely unread.

 Textual drew the same window off `channelJoinTime` until 2013 and dropped it
 when `server-time` arrived. `server-time` turned out not to be enough on its
 own: it says when a line was said, not whether the user has seen it, and the
 servers that need the window most are the ones that supply the least. */
enum ChannelJoinBurstPolicy {
	/** How long after a join the burst is still expected.

	 Long enough for a bouncer to finish replaying a channel over a slow link,
	 short enough that the first live line of a real conversation falls outside
	 it. */
	static let gracePeriod: TimeInterval = 10

	/** Whether `receivedAt` describes a replayed line rather than something
	 said to the user just now.

	 `joinedAt` is the local user's join, `now` the moment the line arrived.
	 Outside the grace period nothing is a burst line: a channel joined a minute
	 ago is a channel the user is sitting in.

	 Inside it, three separate shapes of replay count, and each needs its own
	 clause:

	 - `isHistoric`, which is what a `chathistory` or `znc.in/playback` batch
	   sets, and what a stamp far behind arrival sets on a bouncer that replays
	   plain lines outside a batch.
	 - `hasServerTime == false`, because a server without `server-time` replays
	   with no stamp at all: nothing distinguishes its replay from live traffic
	   except that it arrived in the seconds after the join.
	 - `receivedAt <= joinedAt`, for a stamped line that was said before the
	   user was in the channel. Nobody can have addressed the user with it, so
	   it is scrollback however it was delivered.

	 `joinedAt` may be on the server's clock while `now` is on this Mac's, so
	 skew between them shifts the window; the grace period is wide enough to
	 absorb the second or two that is worth absorbing. */
	static func isJoinBurstLine(
		joinedAt: Date?,
		now: Date,
		isHistoric: Bool,
		hasServerTime: Bool,
		receivedAt: Date
	) -> Bool {
		guard let joinedAt, now.timeIntervalSince(joinedAt) <= gracePeriod else {
			return false
		}

		return isHistoric || hasServerTime == false || receivedAt <= joinedAt
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

	 Decided when the line arrives rather than when it finishes printing: the
	 grace period is measured against arrival, and printing is asynchronous. */
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
			receivedAt: message.receivedAt
		)
	}
}
