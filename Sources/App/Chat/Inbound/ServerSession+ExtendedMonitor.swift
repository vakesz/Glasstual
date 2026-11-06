// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension ServerSession {
	/** Records what `extended-monitor` says about a monitored nickname.

	 With the capability the server sends `AWAY`, `ACCOUNT` and `CHGHOST` for the
	 people on the monitor list even when they share no channel with the
	 session. Such a line proves the person is online, and an `AWAY` also says
	 which way they are leaning, so the address-book tracker follows both. It is
	 the tracker's own state and nothing more: the notification a sign-on raises
	 is the monitor reply's to send, so none is sent from here.

	 Only a nickname the address book is tracking is recorded. The channel-wide
	 handlers have already updated a user the session knows; this is for the
	 monitored person they cannot reach.

	 - Parameter away: `true` or `false` for an `AWAY` line, `nil` for a line
	   that says nothing about presence of that kind. */
	func recordMonitoredActivity(of nickname: String, away: Bool?) {
		guard isCapabilityEnabled(.extendedMonitor), isCapabilityEnabled(.monitorCommand),
		      nicknameIsMyself(nickname) == false,
		      trackedUsers.status(ofUser: nickname) != .unknown
		else {
			return
		}

		if trackedUsers.status(ofUser: nickname) != .available {
			setTrackedNickname(nickname, status: .available, notify: false)
		}

		if let away {
			setTrackedNickname(nickname, status: away ? .away : .notAway, notify: false)
		}
	}
}
