// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/* How the store answers each thing it can be asked to do. One file so the five
 answers stay comparable: each of them distinguishes a database that is not
 there from a database that refused the work. */

/// Whether the database this process writes to could be opened.
nonisolated enum ScrollbackOpenOutcome: Sendable {
	case opened
	case failed(reason: String?)
	var isOpen: Bool {
		if case .opened = self {
			true
		} else {
			false
		}
	}
}

nonisolated enum ScrollbackFetchOutcome: Sendable {
	/// Only a successful empty page proves exhaustion at the requested cursor.
	case page([ScrollbackEntry])
	case failed(ScrollbackFetchFailure)
	case cancelled
}

nonisolated enum ScrollbackSaveOutcome: Equatable, Sendable {
	case saved
	case failed(String)
}

nonisolated enum ScrollbackWriteOutcome: Equatable, Sendable {
	case accepted
	case unavailable
	case failed(String)
}

nonisolated enum ScrollbackDeletionOutcome: Sendable {
	case deleted(ScrollbackQueries.DeletionResult)
	case unavailable
	case failed(String)
}
