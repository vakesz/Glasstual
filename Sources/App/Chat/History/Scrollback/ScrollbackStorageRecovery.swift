// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

/** What the scrollback database has to tell the reader, for the process rather
 than for one conversation: a store that will not open, a save that failed, or
 history a view could not be rid of.

 One object, owned by ``Scrollback``. Every transcript's banner reads it, which
 is why the deletion failures are keyed by view: the message names the
 conversations that still hold lines the reader asked to remove. */
@MainActor
@Observable
final class ScrollbackStorageRecovery {
	var storageFailure: String?
	var deletionFailures: [String: String] = [:]
	var isRetrying = false
	/** How far the one-time upgrade of an existing history store has got, from
	 0 to 1, while it runs; `nil` when none is running. History is unavailable
	 until it finishes, so the window says why. */
	private(set) var migrationFraction: Double?

	/// Records the upgrade's progress. Progress arrives from the store's own
	/// task as a series of hops to the main actor, which can land out of order,
	/// so an earlier fraction never replaces a later one.
	func noteMigrationProgress(_ fraction: Double) {
		if fraction >= 1 {
			migrationFraction = nil
		} else if fraction > (migrationFraction ?? -1) {
			migrationFraction = fraction
		}
	}

	/// What the storage failures read as, or nothing while the database is
	/// healthy.
	var localMessage: String? {
		if deletionFailures.isEmpty == false {
			let details = Set(deletionFailures.values).sorted()
			return ([String(localized: .ChatHistory.deletionNotRepeated)] + details +
				[storageFailure].compactMap(\.self)).joined(separator: "\n")
		}
		return storageFailure
	}
}
