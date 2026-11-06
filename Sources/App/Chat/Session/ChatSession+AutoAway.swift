// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension ChatSession {
	// MARK: - Automatic away

	/// Records that `reason` started or stopped holding and brings every
	/// network in line.
	func setAutoAwayReason(_ reason: AutoAwayReason, holds: Bool) {
		if holds {
			autoAwayReasons.insert(reason)
		} else {
			autoAwayReasons.remove(reason)
		}
		applyAutoAway()
	}

	/// Installs or removes the Focus filter, then brings every network in line.
	func setFocusFilter(_ filter: FocusFilterState?) {
		focusFilter = filter
		applyAutoAway()
	}

	/// Whether the idle reason currently holds.
	var isIdleAway: Bool {
		autoAwayReasons.contains(.idle)
	}

	/** Sets or clears the automatic away on every network from the reasons that
	 hold for it. A manual away is left alone by `ServerSession.applyAutoAway`. */
	func applyAutoAway() {
		for session in sessions {
			var reasons = autoAwayReasons
			if focusFilter?.setsAway(onNetwork: session.config.uniqueIdentifier) == true {
				reasons.insert(.focus)
			}

			guard let owner = AutoAwayReason.owner(of: reasons) else {
				session.applyAutoAway(owner: nil, message: nil)
				continue
			}

			let message = AutoAwayReason.message(
				for: owner,
				idleMessage: environment.settings.idleAwayMessage,
				focusMessage: focusFilter?.awayMessage,
				fallback: String(localized: .IRC.beBackLater)
			)
			session.applyAutoAway(owner: owner, message: message)
		}
	}
}
