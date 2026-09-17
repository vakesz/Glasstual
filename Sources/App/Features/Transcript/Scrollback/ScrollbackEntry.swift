// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
import Foundation

nonisolated enum ScrollbackAttribute: String {
	case entryCreationDate
	case entryIdentifier
	case logLineData
	case logLineUniqueIdentifier
	case logLineViewIdentifier
	case sessionIdentifier
}

/// The value stored in Core Data between the archive and application models.
/// It is a native `Sendable` value because history no longer crosses XPC.
nonisolated struct ScrollbackEntry: Sendable {
	let data: Data
	let uniqueIdentifier: String
	let viewIdentifier: String
	let sessionIdentifier: UInt
	let creationDate: TimeInterval
	let cursor: ScrollbackRowCursor?

	init(
		logLineData data: Data,
		uniqueIdentifier: String,
		viewIdentifier: String,
		sessionIdentifier: UInt,
		creationDate: TimeInterval,
		cursor: ScrollbackRowCursor? = nil
	) {
		self.data = data
		self.uniqueIdentifier = uniqueIdentifier
		self.viewIdentifier = viewIdentifier
		self.sessionIdentifier = sessionIdentifier
		self.creationDate = creationDate
		self.cursor = cursor
	}

	/// One malformed historic row is discarded without affecting the store.
	init?(managedObject: NSManagedObject) {
		guard
			let data = managedObject.value(forKey: ScrollbackAttribute.logLineData.rawValue) as? Data,
			let uniqueIdentifier = managedObject.value(
				forKey: ScrollbackAttribute.logLineUniqueIdentifier.rawValue
			) as? String,
			let viewIdentifier = managedObject.value(
				forKey: ScrollbackAttribute.logLineViewIdentifier.rawValue
			) as? String,
			let sessionNumber = managedObject.value(
				forKey: ScrollbackAttribute.sessionIdentifier.rawValue
			) as? NSNumber,
			let sessionIdentifier = UInt(exactly: sessionNumber.int64Value),
			let creationNumber = managedObject.value(
				forKey: ScrollbackAttribute.entryCreationDate.rawValue
			) as? NSNumber,
			case let creationDate = creationNumber.doubleValue,
			creationDate.isFinite,
			creationDate >= 0
		else {
			return nil
		}

		self.data = data
		self.uniqueIdentifier = uniqueIdentifier
		self.viewIdentifier = viewIdentifier
		self.sessionIdentifier = sessionIdentifier
		self.creationDate = creationDate
		cursor = ScrollbackRowCursor(object: managedObject)
	}
}

nonisolated struct ScrollbackFetchRequest: Sendable {
	enum Kind: Sendable {
		case newest(ascending: Bool, fetchLimit: UInt, limitToDate: Date?)
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

nonisolated enum ScrollbackFetchOutcome: Sendable {
	/// Only a successful empty page proves exhaustion at the requested cursor.
	case page([ScrollbackEntry])
	case failed(ScrollbackFetchFailure)
	case cancelled
}

nonisolated enum ScrollbackStoreOperation: Sendable {
	case write, reset, forget, close, save, resize
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
	case deleted(ScrollbackDatabase.DeletionResult)
	case unavailable
	case failed(String)
}

/// A database position, never an archive key or a transcript display identifier.
nonisolated struct ScrollbackRowCursor: Codable, Equatable, Sendable {
	let timestamp: TimeInterval
	let insertionIdentifier: Int64
	let lineIdentifier: String
	let rowURI: String
}
