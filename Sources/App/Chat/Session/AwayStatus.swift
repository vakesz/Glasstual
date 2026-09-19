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
	/** Whether it was the screen going to sleep that set this.

	 Waking up only clears an away the sleep handler set, so an away the user
	 asked for survives the display turning itself off. */
	var forScreenSleep = false
}

extension ServerSession {
	func toggleAwayStatus(_ setAway: Bool, withComment comment: String?) {
		away.forScreenSleep = false
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

	func setAwayForScreenSleep() {
		guard isLoggedIn, !away.isAway, away.message == nil, !away.forScreenSleep else { return }
		toggleAwayStatus(true, withComment: String(localized: .IRC.beBackLater))
		away.forScreenSleep = true
	}

	func clearAwayAfterScreenSleep() {
		guard away.forScreenSleep else { return }
		away.forScreenSleep = false
		if isLoggedIn {
			toggleAwayStatus(false, withComment: nil)
		} else {
			away.message = nil
			away.previousNickname = nil
		}
	}
}
