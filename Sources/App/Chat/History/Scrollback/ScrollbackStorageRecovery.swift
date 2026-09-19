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

	/// What the storage failures read as, or nothing while the database is
	/// healthy.
	var localMessage: String? {
		if deletionFailures.isEmpty == false {
			let details = Set(deletionFailures.values).sorted()
			return ([String(localized: .Transcript.deletionNotRepeated)] + details +
				[storageFailure].compactMap(\.self)).joined(separator: "\n")
		}
		return storageFailure
	}
}
