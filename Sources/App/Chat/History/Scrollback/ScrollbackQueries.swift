// Copyright (c) 2016 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import CoreData
import Foundation
import os

/// The Core Data requests and readers the scrollback store runs.
///
/// Every function here runs inside a `perform` block on the context it is
/// handed, so none of them may touch `ScrollbackStore` state: the actor
/// passes in the values a query needs and gets a `Sendable` result back.
/// `NSManagedObjectContext` is itself `Sendable`; fetch requests and the
/// model are not, so both are built from the context inside the block.
nonisolated enum ScrollbackQueries {
	static let modelName = "ScrollbackStorageModel"
	static let entityName = "ScrollbackEntry"

	static let logger = Logger(
		subsystem: LogSubsystem.current,
		category: "ScrollbackQueries"
	)

	/// Which rows a deletion covers. `Sendable` so the request can be rebuilt
	/// on the parent context's queue instead of being carried across.
	enum Deletion: Sendable {
		/// Every row of the view whose entry identifier is at most the ceiling:
		/// the rows written before the removal was asked for. A line written
		/// while it runs is newer, and stays.
		case everything(throughEntryIdentifier: UInt)
		case retainingNewest(count: UInt)
	}

	/// Rows a deletion removed, together with the unique identifiers the store's
	/// owner has to be told about. Returned rather than reported from here:
	/// telling anyone belongs to the actor, not to the context's queue.
	struct DeletionResult: Sendable {
		let deletedCount: UInt
		let uniqueIdentifiers: [String]
		/// Whether rows the deletion covers were left for another chunk.
		var hasMore = false
	}

	// MARK: - Stack

	/// Builds the stack, or throws what stopped it. The reason travels: it is
	/// the only thing the failure alert has to tell the reader.
	///
	/// - Parameter migrationProgress: Told how far an upgrade of an existing
	///   store has got, from 0 to 1. Not called for a store that needs none.
	static func makeStack(
		at url: URL,
		migrationProgress: (@Sendable (Double) -> Void)? = nil
	) throws -> NSManagedObjectContext {
		let versions: ScrollbackModelVersions
		do {
			versions = try ScrollbackModelMigration.versions()
		} catch {
			logger.error("Scrollback model is missing")
			throw error
		}

		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: versions.current)
		// The explicit upgrade handles only the known earlier schemas. Never
		// infer a migration for any other store at ordinary open.
		let options: [AnyHashable: Any] = [
			NSMigratePersistentStoresAutomaticallyOption: false,
			NSInferMappingModelAutomaticallyOption: false,
			NSSQLitePragmasOption: ["synchronous": "NORMAL", "journal_mode": "WAL"],
		]

		do {
			try ScrollbackModelMigration.upgradeIfNeeded(
				at: url, versions: versions, using: coordinator, options: options, progress: migrationProgress
			)
			_ = try coordinator.addPersistentStore(type: .sqlite, at: url, options: options)
		} catch {
			logger.error("Error opening persistent store: \(error.localizedDescription, privacy: .public)")

			throw error
		}

		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		context.persistentStoreCoordinator = coordinator
		context.undoManager = nil

		return context
	}

	// MARK: - Reads

	/// Allocation must include every row, even one excluded by the display date
	/// filter or carrying an unreadable archive. A failed read must not restart IDs.
	static func initialCounts(
		in context: NSManagedObjectContext,
		viewIdentifier: String
	) throws -> (lineCount: UInt, maximumIdentifier: UInt) {
		let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
		request.predicate = NSPredicate(
			format: "%K == %@", ScrollbackAttribute.viewID.rawValue, viewIdentifier
		)
		request.includesPendingChanges = true
		let lineCount = try UInt(context.count(for: request))
		request.sortDescriptors = [
			NSSortDescriptor(key: ScrollbackAttribute.entryID.rawValue, ascending: false),
		]
		request.fetchLimit = 1
		let maximum = try (context.fetch(request).first?.value(
			forKey: ScrollbackAttribute.entryID.rawValue
		) as? NSNumber)?.int64Value ?? 0

		return (lineCount, UInt(max(0, maximum)))
	}

	static func fetchOutcome(
		in context: NSManagedObjectContext,
		viewIdentifier: String,
		before uniqueIdentifier: String,
		fetchLimit: UInt,
		limitToDate: Date?
	) -> ScrollbackFetchOutcome {
		guard fetchLimit > 0 else { return .failed(.invalidRequest) }
		if let limitToDate, !limitToDate.timeIntervalSince1970.isFinite {
			return .failed(.invalidRequest)
		}
		let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
		request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
			NSPredicate(format: "%K == %@", ScrollbackAttribute.viewID.rawValue, viewIdentifier),
			NSPredicate(format: "%K == %@", ScrollbackAttribute.lineID.rawValue, uniqueIdentifier),
		])

		// The public cursor names a line, not a Core Data row. Do not guess if
		// the store contains multiple rows with that same line identity.
		request.fetchLimit = 2
		request.includesPendingChanges = true
		request.includesPropertyValues = true
		request.returnsObjectsAsFaults = false

		do {
			try context.obtainPermanentIDs(for: Array(context.insertedObjects))
			let anchors = try context.fetch(request)
			if anchors.count > 1 {
				logger.error("Cannot paginate history from a duplicate line identifier")
				return .failed(.ambiguousCursor)
			}
			guard let anchor = anchors.first else { return .failed(.missingCursor) }
			guard let cursor = ScrollbackRowCursor(object: anchor) else { return .failed(.invalidEntry) }
			let outcome = fetchRowPage(in: context, viewIdentifier: viewIdentifier, before: cursor,
			                           fetchLimit: fetchLimit, limitToDate: limitToDate)
			if case let .page(entries) = outcome {
				return .page(Array(entries.reversed()))
			}
			return outcome
		} catch {
			logger.error("Failed to fetch older entries: \(error.localizedDescription, privacy: .public)")

			return .failed(.read(error.localizedDescription))
		}
	}

	// MARK: - Writes

	@discardableResult
	static func insert(_ chatLine: ScrollbackEntry, in context: NSManagedObjectContext, entryIdentifier: UInt) -> Bool {
		guard let entity = NSEntityDescription.entity(forEntityName: entityName, in: context) else {
			logger.error("The \(entityName, privacy: .public) entity is missing")

			return false
		}

		let entry = NSManagedObject(entity: entity, insertInto: context)

		entry.setValue(
			NSNumber(value: entryIdentifier),
			forKey: ScrollbackAttribute.entryID.rawValue
		)
		/* The line's own timestamp, not the moment it reached the database: reads
		 both sort and filter on this column, and a chat-history replay inserts
		 lines that are hours old. */
		entry.setValue(
			NSNumber(value: chatLine.creationDate),
			forKey: ScrollbackAttribute.createdAt.rawValue
		)
		entry.setValue(chatLine.viewIdentifier, forKey: ScrollbackAttribute.viewID.rawValue)
		entry.setValue(chatLine.data, forKey: ScrollbackAttribute.lineData.rawValue)
		chatLine.writeDerivedColumns(to: entry)
		entry.setValue(chatLine.uniqueIdentifier, forKey: ScrollbackAttribute.lineID.rawValue)
		entry.setValue(
			NSNumber(value: chatLine.sessionIdentifier),
			forKey: ScrollbackAttribute.sessionID.rawValue
		)
		return true
	}

	static func replace(_ entry: ScrollbackEntry, in context: NSManagedObjectContext) -> ScrollbackReplacementOutcome {
		let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
		request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
			NSPredicate(format: "%K == %@", ScrollbackAttribute.viewID.rawValue, entry.viewIdentifier),
			NSPredicate(format: "%K == %@", ScrollbackAttribute.lineID.rawValue, entry.uniqueIdentifier),
		])
		do {
			let rows = try context.fetch(request)
			guard !rows.isEmpty else { return .missing }
			for row in rows {
				// Preserve physical cursors and insertion order already handed to views.
				row.setValue(entry.data, forKey: ScrollbackAttribute.lineData.rawValue)
				// A labelled echo learns its server message identifier here.
				entry.writeDerivedColumns(to: row)
			}
			return .replaced
		} catch { return .failed(error.localizedDescription) }
	}

	/** Overwrites the stored payload of the line `messageIdentifier` names in one
	 view with the line redacted, so the deleted text does not stay in the
	 database.

	 The identifier is a column beside the payload, indexed with the view, so
	 only the rows that carry it are read. The column compares bytes, as
	 ``MessageIdentifierKey`` does, and each match is still checked against its
	 archive before it is overwritten. The row keeps its cursor, order, line
	 identity and message identifier: only `lineData` and the search columns
	 change. */
	static func redact(
		messageIdentifier: String,
		viewIdentifier: String,
		in context: NSManagedObjectContext
	) -> ScrollbackRedactionOutcome {
		guard messageIdentifier.isEmpty == false else { return .missing }
		let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
		request.predicate = NSPredicate(
			format: "%K == %@ AND %K == %@",
			ScrollbackAttribute.viewID.rawValue, viewIdentifier,
			ScrollbackAttribute.messageID.rawValue, messageIdentifier
		)
		request.includesPendingChanges = true
		do {
			var redactedLine: ChatLine?
			for row in try context.fetch(request) {
				guard let data = row.value(forKey: ScrollbackAttribute.lineData.rawValue) as? Data,
				      var line = ChatLine(data: data),
				      MessageIdentifierKey.equal(line.messageIdentifier, messageIdentifier)
				else { continue }
				line.redact()
				let payload = ChatLineStoredPayload(line: line)
				guard let encoded = try? PropertyListEncoder().encode(payload) else {
					return .failed(CocoaError(.coderInvalidValue).localizedDescription)
				}
				row.setValue(encoded, forKey: ScrollbackAttribute.lineData.rawValue)
				// The words are withdrawn from every column, not only from the archive.
				ScrollbackSearchFields(line: line).write(to: row)
				redactedLine = redactedLine ?? line
			}
			return redactedLine.map { .redacted($0) } ?? .missing
		} catch { return .failed(error.localizedDescription) }
	}

	@discardableResult
	static func quickSave(_ context: NSManagedObjectContext) -> ScrollbackSaveOutcome {
		guard context.hasChanges else { return .saved }

		do {
			try context.save()
		} catch {
			logger.error("Failed to perform save: \(error.localizedDescription, privacy: .public)")
			return .failed(error.localizedDescription)
		}
		return .saved
	}
}

nonisolated extension ScrollbackQueries {
	/// Descending rows. Only the boundary bucket is expanded; Core Data cannot
	/// compare object IDs in an ordered predicate, so its permanent URIs break ties here.
	static func fetchRowPage(
		in context: NSManagedObjectContext, viewIdentifier: String, before cursor: ScrollbackRowCursor?,
		fetchLimit: UInt, limitToDate: Date?
	) -> ScrollbackFetchOutcome {
		guard fetchLimit > 0,
		      limitToDate?.timeIntervalSince1970.isFinite != false else { return .failed(.invalidRequest) }
		let limit = Int(clamping: fetchLimit)
		let dateKey = ScrollbackAttribute.createdAt.rawValue
		let idKey = ScrollbackAttribute.entryID.rawValue
		let lineKey = ScrollbackAttribute.lineID.rawValue
		let view = NSPredicate(format: "%K == %@", ScrollbackAttribute.viewID.rawValue, viewIdentifier)
		let base = NSCompoundPredicate(andPredicateWithSubpredicates: [view,
		                                                               NSPredicate(
		                                                               	format: "%K < %@",
		                                                               	dateKey,
		                                                               	NSNumber(value: (limitToDate ??
		                                                               			.distantFuture)
		                                                               		.timeIntervalSince1970)
		                                                               )])
		do {
			try context.obtainPermanentIDs(for: Array(context.insertedObjects))
			if let cursor {
				guard let uri = URL(string: cursor.rowURI),
				      let coordinator = context.persistentStoreCoordinator ?? context.parent?
				      	.persistentStoreCoordinator,
				      let objectID = coordinator.managedObjectID(forURIRepresentation: uri)
				else { return .failed(.missingCursor) }
				let anchor = NSFetchRequest<NSManagedObject>(entityName: entityName)
				anchor.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
					view,
					NSPredicate(format: "SELF == %@", objectID),
				])
				guard let object = try context.fetch(anchor).first,
				      ScrollbackRowCursor(object: object) == cursor else { return .failed(.missingCursor) }
			}
			let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
			request.sortDescriptors = [NSSortDescriptor(key: dateKey, ascending: false),
			                           NSSortDescriptor(key: idKey, ascending: false),
			                           NSSortDescriptor(key: lineKey, ascending: false)]
			var rows: [(object: NSManagedObject, cursor: ScrollbackRowCursor)] = []
			if let cursor {
				request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [base, rowBucket(cursor)])
				for object in try context.fetch(request) {
					guard let position = ScrollbackRowCursor(object: object) else { return .failed(.invalidEntry) }
					if position.rowURI < cursor.rowURI {
						rows.append((object, position))
					}
				}
			}
			if rows.count < limit {
				request.fetchLimit = limit - rows.count
				if let cursor {
					let older = NSPredicate(
						format: "%K < %@ OR (%K == %@ AND %K < %@) OR (%K == %@ AND %K == %@ AND %K < %@)",
						dateKey, NSNumber(value: cursor.timestamp), dateKey, NSNumber(value: cursor.timestamp),
						idKey, NSNumber(value: cursor.insertionIdentifier), dateKey, NSNumber(value: cursor.timestamp),
						idKey, NSNumber(value: cursor.insertionIdentifier), lineKey, cursor.lineIdentifier
					)
					request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [base, older])
				} else {
					request.predicate = base
				}
				let candidates = try context.fetch(request)
				if let last = candidates.last {
					guard let boundary = ScrollbackRowCursor(object: last) else { return .failed(.invalidEntry) }
					for object in candidates {
						guard let position = ScrollbackRowCursor(object: object) else { return .failed(.invalidEntry) }
						if position.timestamp != boundary.timestamp || position.insertionIdentifier != boundary
							.insertionIdentifier ||
							position.lineIdentifier != boundary.lineIdentifier
						{
							rows.append((object, position))
						}
					}
					request.fetchLimit = 0
					request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [base, rowBucket(boundary)])
					for object in try context.fetch(request) {
						guard let position = ScrollbackRowCursor(object: object) else { return .failed(.invalidEntry) }
						rows.append((object, position))
					}
				}
			}
			rows.sort { $0.cursor > $1.cursor }
			let selected = rows.prefix(limit)
			let entries = selected.compactMap { ScrollbackEntry(managedObject: $0.object) }
			guard entries.count == selected.count else { return .failed(.invalidEntry) }
			return .page(entries)
		} catch { return .failed(.read(error.localizedDescription)) }
	}

	static func rowBucket(_ cursor: ScrollbackRowCursor) -> NSPredicate {
		NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@",
		            ScrollbackAttribute.createdAt.rawValue, NSNumber(value: cursor.timestamp),
		            ScrollbackAttribute.entryID.rawValue, NSNumber(value: cursor.insertionIdentifier),
		            ScrollbackAttribute.lineID.rawValue, cursor.lineIdentifier)
	}
}

nonisolated extension ScrollbackRowCursor: Comparable {
	static func < (left: Self, right: Self) -> Bool {
		(left.timestamp, left.insertionIdentifier, left.lineIdentifier, left.rowURI)
			< (right.timestamp, right.insertionIdentifier, right.lineIdentifier, right.rowURI)
	}

	init?(object: NSManagedObject) {
		guard !object.objectID.isTemporaryID,
		      let date = object.value(forKey: ScrollbackAttribute.createdAt.rawValue) as? NSNumber,
		      let identifier = object.value(forKey: ScrollbackAttribute.entryID.rawValue) as? NSNumber,
		      let line = object.value(forKey: ScrollbackAttribute.lineID.rawValue) as? String,
		      date.doubleValue.isFinite else { return nil }
		self.init(timestamp: date.doubleValue, insertionIdentifier: identifier.int64Value,
		          lineIdentifier: line, rowURI: object.objectID.uriRepresentation().absoluteString)
	}
}
