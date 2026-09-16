/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

nonisolated struct ScrollbackFetchRequest: Sendable { // nonisolated: value
	enum Kind: Sendable {
		case newest(ascending: Bool, fetchLimit: UInt, limitToDate: Date?)
		case before(uniqueIdentifier: String, fetchLimit: UInt, limitToDate: Date?)
		case rowPage(before: ScrollbackRowCursor?, fetchLimit: UInt, limitToDate: Date?)
	}

	let viewIdentifier: String
	let kind: Kind
}

nonisolated enum ScrollbackFetchFailure: Equatable, Sendable { // nonisolated: value
	case unavailable, invalidRequest, missingCursor, ambiguousCursor, invalidEntry
	case read(String)
}

nonisolated enum ScrollbackFetchOutcome: Sendable { // nonisolated: value
	/// Only a successful empty page proves exhaustion at the requested cursor.
	case page([ScrollbackEntry])
	case failed(ScrollbackFetchFailure)
	case cancelled
}

nonisolated enum ScrollbackStoreOperation: Sendable { // nonisolated: value
	case write, reset, forget, close, save, resize
}

nonisolated enum ScrollbackSaveOutcome: Equatable, Sendable { // nonisolated: value
	case saved
	case failed(String)
}

nonisolated enum ScrollbackWriteOutcome: Equatable, Sendable { // nonisolated: value
	case accepted
	case unavailable
	case failed(String)
}

nonisolated enum ScrollbackDeletionOutcome: Sendable { // nonisolated: value
	case deleted(ScrollbackDatabase.DeletionResult)
	case unavailable
	case failed(String)
}

/// A database position, never an archive key or a transcript display identifier.
nonisolated struct ScrollbackRowCursor: Codable, Equatable, Sendable { // nonisolated: value
	let timestamp: TimeInterval
	let insertionIdentifier: Int64
	let lineIdentifier: String
	let rowURI: String
}
