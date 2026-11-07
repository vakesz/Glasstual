// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
import Foundation

nonisolated extension ScrollbackQueries {
	/** The rows around one row, oldest first, with the row itself between the
	 older and the newer ones.

	 The row is found by its cursor and checked against it, so a window never
	 centres on a different row than the one a search showed, and a row that has
	 since been pruned is reported as `missingCursor` and not replaced by its
	 neighbour. */
	static func fetchWindow(
		in context: NSManagedObjectContext,
		viewIdentifier: String,
		around cursor: ScrollbackRowCursor,
		olderLimit: UInt,
		newerLimit: UInt
	) -> ScrollbackFetchOutcome {
		let older: [ScrollbackEntry]
		if olderLimit > 0 {
			switch fetchRowPage(
				in: context, viewIdentifier: viewIdentifier, before: cursor, fetchLimit: olderLimit, limitToDate: nil
			) {
			case let .page(entries): older = Array(entries.reversed())
			case let .failed(failure): return .failed(failure)
			case .cancelled: return .cancelled
			}
		} else {
			older = []
		}
		let anchor: ScrollbackEntry
		switch fetchRow(in: context, viewIdentifier: viewIdentifier, matching: cursor) {
		case let .success(entry): anchor = entry
		case let .failure(failure): return .failed(failure)
		}
		let newer: [ScrollbackEntry]
		if newerLimit > 0 {
			switch fetchRows(in: context, viewIdentifier: viewIdentifier, after: cursor, fetchLimit: newerLimit) {
			case let .page(entries): newer = entries
			case let .failed(failure): return .failed(failure)
			case .cancelled: return .cancelled
			}
		} else {
			newer = []
		}
		return .page(older + [anchor] + newer)
	}

	/// The one row a cursor names, or why there is none.
	private static func fetchRow(
		in context: NSManagedObjectContext,
		viewIdentifier: String,
		matching cursor: ScrollbackRowCursor
	) -> Result<ScrollbackEntry, ScrollbackFetchFailure> {
		do {
			guard let uri = URL(string: cursor.rowURI),
			      let coordinator = context.persistentStoreCoordinator ?? context.parent?.persistentStoreCoordinator,
			      let objectID = coordinator.managedObjectID(forURIRepresentation: uri)
			else { return .failure(.missingCursor) }
			let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
			request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
				NSPredicate(format: "%K == %@", ScrollbackAttribute.viewID.rawValue, viewIdentifier),
				NSPredicate(format: "SELF == %@", objectID),
			])
			request.fetchLimit = 1
			request.returnsObjectsAsFaults = false
			guard let object = try context.fetch(request).first,
			      ScrollbackRowCursor(object: object) == cursor
			else { return .failure(.missingCursor) }
			guard let entry = ScrollbackEntry(managedObject: object) else { return .failure(.invalidEntry) }
			return .success(entry)
		} catch {
			return .failure(.read(error.localizedDescription))
		}
	}

	/** The rows after `cursor`, oldest first: first the rows that share its
	 position but sort after it, then the rows that are newer.

	 The mirror of ``fetchRowPage(in:viewIdentifier:before:fetchLimit:limitToDate:)``.
	 Rows that tie on time, insertion and line identifier are ordered by their
	 permanent URI, which Core Data cannot compare in a predicate, so the
	 boundary bucket is read whole and ordered here. That is what lets the next
	 page resume after the last row returned without skipping a tied row. */
	static func fetchRows(
		in context: NSManagedObjectContext,
		viewIdentifier: String,
		after cursor: ScrollbackRowCursor,
		fetchLimit: UInt
	) -> ScrollbackFetchOutcome {
		guard fetchLimit > 0 else { return .failed(.invalidRequest) }
		let limit = Int(clamping: fetchLimit)
		let dateKey = ScrollbackAttribute.createdAt.rawValue
		let entryKey = ScrollbackAttribute.entryID.rawValue
		let lineKey = ScrollbackAttribute.lineID.rawValue
		let view = NSPredicate(format: "%K == %@", ScrollbackAttribute.viewID.rawValue, viewIdentifier)
		func bucket(_ position: ScrollbackRowCursor) -> NSPredicate {
			NSCompoundPredicate(andPredicateWithSubpredicates: [view, rowBucket(position)])
		}
		do {
			try context.obtainPermanentIDs(for: Array(context.insertedObjects))
			let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
			request.sortDescriptors = [
				NSSortDescriptor(key: dateKey, ascending: true),
				NSSortDescriptor(key: entryKey, ascending: true),
				NSSortDescriptor(key: lineKey, ascending: true),
			]
			var rows: [(object: NSManagedObject, cursor: ScrollbackRowCursor)] = []
			var included = Set<NSManagedObjectID>()
			func add(_ object: NSManagedObject, _ position: ScrollbackRowCursor) {
				if included.insert(object.objectID).inserted {
					rows.append((object, position))
				}
			}

			request.predicate = bucket(cursor)
			for object in try context.fetch(request) {
				guard let position = ScrollbackRowCursor(object: object) else { return .failed(.invalidEntry) }
				if position > cursor {
					add(object, position)
				}
			}
			if rows.count < limit {
				request.fetchLimit = limit - rows.count
				let newer = NSPredicate(
					format: "%K > %@ OR (%K == %@ AND %K > %@) OR (%K == %@ AND %K == %@ AND %K > %@)",
					dateKey, NSNumber(value: cursor.timestamp), dateKey, NSNumber(value: cursor.timestamp),
					entryKey, NSNumber(value: cursor.insertionIdentifier), dateKey, NSNumber(value: cursor.timestamp),
					entryKey, NSNumber(value: cursor.insertionIdentifier), lineKey, cursor.lineIdentifier
				)
				request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [view, newer])
				let candidates = try context.fetch(request)
				for object in candidates {
					guard let position = ScrollbackRowCursor(object: object) else { return .failed(.invalidEntry) }
					add(object, position)
				}
				if let last = candidates.last {
					guard let boundary = ScrollbackRowCursor(object: last) else { return .failed(.invalidEntry) }
					request.fetchLimit = 0
					request.predicate = bucket(boundary)
					for object in try context.fetch(request) {
						guard let position = ScrollbackRowCursor(object: object) else { return .failed(.invalidEntry) }
						add(object, position)
					}
				}
			}
			rows.sort { $0.cursor < $1.cursor }
			let selected = rows.prefix(limit)
			let entries = selected.compactMap { ScrollbackEntry(managedObject: $0.object) }
			guard entries.count == selected.count else { return .failed(.invalidEntry) }
			return .page(entries)
		} catch {
			return .failed(.read(error.localizedDescription))
		}
	}
}
