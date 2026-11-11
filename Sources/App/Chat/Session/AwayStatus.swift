// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Whether the user is present, and the nickname and message that stand in for
 them while they are not.

 Away is user presence rather than connection state: it outlives a reconnect in
 the configuration the nickname comes from, and the screen-sleep handler sets it
 without anything happening to the socket. */
struct AwayStatus {
	/// Whether the server has the user marked away.
	var isAway = false
	/** The comment the last `AWAY` carried, or `nil` when the user is present.

	 A reconnect sends it again before registration finishes, so that a session
	 that came back does not silently come back present. */
	var message: String?
	/// The nickname to return to while an away nickname stands in for it.
	var previousNickname: String?
	/** The automatic reason that set this, or `nil` when the user did.

	 Only an away the application set is cleared when its reason ends, so an
	 away the user asked for survives the display sleeping, the Mac coming
	 back from idle and a Focus ending. */
	var autoReason: AutoAwayReason?

	/// Teardown: the connection that was away has ended. The comment is kept,
	/// for the next connection to send again.
	mutating func resetForTeardown() {
		isAway = false
		previousNickname = nil
	}
}

extension ServerSession {
	func toggleAwayStatus(_ setAway: Bool, withComment comment: String?) {
		away.autoReason = nil
		guard isLoggedIn, setAway == false || comment != nil else { return }
		/* `AWAYLEN` is measured here rather than at each caller: the menu, the
		 screen-sleep timer and `/away` all end up on this line, and only the
		 first of them used to bound the comment. */
		let comment = comment.map(truncatedAwayComment)
		if setAway, let comment {
			send(.away, arguments: [comment])
		} else {
			send(.away, arguments: [])
		}
		away.message = setAway ? comment : nil
		let newNickname: String?
		if setAway {
			newNickname = config.awayNickname
			away.previousNickname = userNickname
		} else {
			newNickname = away.previousNickname ?? (config.awayNickname?.isEmpty == false ? config.nickname : nil)
			away.previousNickname = nil
		}
		if let newNickname {
			changeNickname(newNickname)
		}
	}

	/** Marks the user away for `owner`, unless they already are.

	 With `owner` or `message` `nil` no reason holds any more and an automatic
	 away ends. An away already marked automatic only changes owner, so the
	 server sees one `AWAY` however the reasons overlap. */
	func applyAutoAway(owner: AutoAwayReason?, message: String?) {
		guard let owner, let message else {
			clearAutoAway()
			return
		}

		if away.autoReason != nil {
			away.autoReason = owner
			return
		}

		guard isLoggedIn, !away.isAway, away.message == nil else { return }
		toggleAwayStatus(true, withComment: message)
		away.autoReason = owner
	}

	func clearAutoAway() {
		guard away.autoReason != nil else { return }
		away.autoReason = nil
		if isLoggedIn {
			toggleAwayStatus(false, withComment: nil)
		} else {
			away.message = nil
			away.previousNickname = nil
		}
	}
}
