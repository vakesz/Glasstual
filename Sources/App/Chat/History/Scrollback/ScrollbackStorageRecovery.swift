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

	/// Records the upgrade's progress. Reports arrive in the order the store
	/// made them, so the last one is the truth: a restarted upgrade starts over
	/// from a low fraction, and `1` ends it.
	func noteMigrationProgress(_ fraction: Double) {
		migrationFraction = fraction >= 1 ? nil : fraction
	}

	/// Applies each report from `progress`, in order, until it finishes.
	func consume(_ progress: AsyncStream<Double>) async {
		for await fraction in progress {
			noteMigrationProgress(fraction)
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
