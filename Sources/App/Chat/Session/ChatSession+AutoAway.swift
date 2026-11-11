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
		focusFilterGeneration += 1
		applyAutoAway()
	}

	/** Installs a filter that was read from the system, unless the system has
	 installed or removed one since `generation` was noted. That read is older
	 than the delivery and would put back a filter the Focus has since ended.
	 Returns whether the filter was installed. */
	@discardableResult
	func restoreFocusFilter(_ filter: FocusFilterState, readAtGeneration generation: Int) -> Bool {
		guard generation == focusFilterGeneration else { return false }
		setFocusFilter(filter)
		return true
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
