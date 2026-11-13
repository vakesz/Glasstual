// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
import Foundation

/// The columns of the `ScrollbackEntry` entity. The raw values are the attribute
/// names in `ScrollbackStorageModel`, so a store written with other spellings —
/// any 1.x database — refuses to open rather than being migrated.
nonisolated enum ScrollbackAttribute: String {
	case createdAt
	case entryID
	case lineData
	case lineID
	case sessionID
	case viewID
	/// The searchable columns the second schema added beside `lineData`.
	case plainText
	case sender
	case searchText
	/// The IRCv3 message identifier the fourth schema copies out of `lineData`,
	/// so a redaction finds its row through an index.
	case messageID
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
	/// The plain text written beside the archive so the row can be searched.
	let search: ScrollbackSearchFields
	/// The line's IRCv3 message identifier, written beside the archive so a
	/// redaction can find the row without reading the view. Never empty.
	let messageIdentifier: String?

	init(
		lineData data: Data,
		uniqueIdentifier: String,
		viewIdentifier: String,
		sessionIdentifier: UInt,
		creationDate: TimeInterval,
		cursor: ScrollbackRowCursor? = nil,
		search: ScrollbackSearchFields = .empty,
		messageIdentifier: String? = nil
	) {
		self.data = data
		self.uniqueIdentifier = uniqueIdentifier
		self.viewIdentifier = viewIdentifier
		self.sessionIdentifier = sessionIdentifier
		self.creationDate = creationDate
		self.cursor = cursor
		self.search = search
		self.messageIdentifier = messageIdentifier?.isEmpty == false ? messageIdentifier : nil
	}

	/// One malformed stored row is discarded without affecting the store.
	init?(managedObject: NSManagedObject) {
		guard
			let data = managedObject.value(forKey: ScrollbackAttribute.lineData.rawValue) as? Data,
			let uniqueIdentifier = managedObject.value(
				forKey: ScrollbackAttribute.lineID.rawValue
			) as? String,
			let viewIdentifier = managedObject.value(
				forKey: ScrollbackAttribute.viewID.rawValue
			) as? String,
			let sessionNumber = managedObject.value(
				forKey: ScrollbackAttribute.sessionID.rawValue
			) as? NSNumber,
			let sessionIdentifier = UInt(exactly: sessionNumber.int64Value),
			let creationNumber = managedObject.value(
				forKey: ScrollbackAttribute.createdAt.rawValue
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
		search = ScrollbackSearchFields(managedObject: managedObject)
		messageIdentifier = managedObject.entity.propertiesByName[ScrollbackAttribute.messageID.rawValue] == nil
			? nil
			: managedObject.value(forKey: ScrollbackAttribute.messageID.rawValue) as? String
	}

	/// Writes the columns derived from the line beside its archive: the search
	/// text and the message identifier.
	func writeDerivedColumns(to object: NSManagedObject) {
		search.write(to: object)
		object.setValue(messageIdentifier, forKey: ScrollbackAttribute.messageID.rawValue)
	}
}

/// A database position, never an archive key or a transcript display identifier.
nonisolated struct ScrollbackRowCursor: Codable, Equatable, Sendable {
	let timestamp: TimeInterval
	let insertionIdentifier: Int64
	let lineIdentifier: String
	let rowURI: String
}
