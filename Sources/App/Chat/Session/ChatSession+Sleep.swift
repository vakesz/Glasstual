// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension ChatSession {
	// MARK: - Sleep

	/// Called when a session's registration state changes, which is the only
	/// thing the setting reads besides itself.
	func noteLoginStateChanged() {
		refreshSleepPrevention()
	}

	func refreshSleepPrevention() {
		sleepPrevention.refresh(
			shouldHold: SettingsKeys.Connection.preventSleepWhileConnected.value
				&& sessions.contains(where: \.isLoggedIn)
		)
	}
}
