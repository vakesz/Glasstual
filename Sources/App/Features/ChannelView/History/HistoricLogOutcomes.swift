/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

nonisolated struct HistoricLogFetchRequest: Sendable { // nonisolated: value
	enum Kind: Sendable {
		case newest(ascending: Bool, fetchLimit: UInt, limitToDate: Date?)
		case before(uniqueIdentifier: String, fetchLimit: UInt, limitToDate: Date?)
		case rowPage(before: HistoricLogRowCursor?, fetchLimit: UInt, limitToDate: Date?)
	}

	let viewIdentifier: String
	let kind: Kind
}

nonisolated enum HistoricLogFetchFailure: Equatable, Sendable { // nonisolated: value
	case unavailable, invalidRequest, missingCursor, ambiguousCursor, invalidEntry
	case read(String)
}

nonisolated enum HistoricLogFetchOutcome: Sendable { // nonisolated: value
	/// Only a successful empty page proves exhaustion at the requested cursor.
	case page([HistoricLogEntry])
	case failed(HistoricLogFetchFailure)
	case cancelled
	/// The original array API deliberately collapses errors; production reads the case.
	var entries: [HistoricLogEntry] {
		if case let .page(entries) = self {
			entries
		} else {
			[]
		}
	}
}

nonisolated enum HistoricLogStoreOperation: Sendable { // nonisolated: value
	case write, reset, forget, close, save, resize
}

nonisolated enum HistoricLogSaveOutcome: Equatable, Sendable { // nonisolated: value
	case saved
	case failed(String)
}

nonisolated enum HistoricLogWriteOutcome: Equatable, Sendable { // nonisolated: value
	case accepted
	case unavailable
	case failed(String)
}

nonisolated enum HistoricLogDeletionOutcome: Sendable { // nonisolated: value
	case deleted(HistoricLogDatabase.DeletionResult)
	case unavailable
	case failed(String)
}

/// A database position, never an archive key or a transcript display identifier.
nonisolated struct HistoricLogRowCursor: Codable, Equatable, Sendable { // nonisolated: value
	let timestamp: TimeInterval
	let insertionIdentifier: Int64
	let lineIdentifier: String
	let rowURI: String
}
