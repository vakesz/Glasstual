// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// What one view asks the scrollback for: a page of its stored rows, named
/// either by the row it should end before or by the line it should end before.
nonisolated struct ScrollbackFetchRequest: Sendable {
	enum Kind: Sendable {
		case before(uniqueIdentifier: String, fetchLimit: UInt, limitToDate: Date?)
		case rowPage(before: ScrollbackRowCursor?, fetchLimit: UInt, limitToDate: Date?)
		/** The rows around one stored row, oldest first: up to `olderLimit` rows
		 before it, the row itself, and up to `newerLimit` rows after it.

		 Named by the row's cursor rather than its line identifier, because a
		 line identifier can be held by two rows and a cursor names exactly one. */
		case window(around: ScrollbackRowCursor, olderLimit: UInt, newerLimit: UInt)
	}

	let viewIdentifier: String
	let kind: Kind
}

nonisolated enum ScrollbackFetchFailure: Error, Equatable, Sendable {
	case unavailable, invalidRequest, missingCursor, ambiguousCursor, invalidEntry
	case read(String)
}
