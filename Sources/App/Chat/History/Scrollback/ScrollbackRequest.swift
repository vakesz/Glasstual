// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// What one view asks the scrollback for: a page of its stored rows, named
/// either by the row it should end before or by the line it should end before.
nonisolated struct ScrollbackFetchRequest: Sendable {
	enum Kind: Sendable {
		case before(uniqueIdentifier: String, fetchLimit: UInt, limitToDate: Date?)
		case rowPage(before: ScrollbackRowCursor?, fetchLimit: UInt, limitToDate: Date?)
	}

	let viewIdentifier: String
	let kind: Kind
}

nonisolated enum ScrollbackFetchFailure: Equatable, Sendable {
	case unavailable, invalidRequest, missingCursor, ambiguousCursor, invalidEntry
	case read(String)
}
