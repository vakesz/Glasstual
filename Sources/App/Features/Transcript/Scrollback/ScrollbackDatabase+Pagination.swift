/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CoreData
import Foundation

nonisolated extension ScrollbackDatabase { // nonisolated: value
	/// Descending rows. Only the boundary bucket is expanded; Core Data cannot
	/// compare object IDs in an ordered predicate, so its permanent URIs break ties here.
	static func fetchRowPage(
		in context: NSManagedObjectContext, viewIdentifier: String, before cursor: ScrollbackRowCursor?,
		fetchLimit: UInt, limitToDate: Date?
	) -> ScrollbackFetchOutcome {
		guard fetchLimit > 0,
		      limitToDate?.timeIntervalSince1970.isFinite != false else { return .failed(.invalidRequest) }
		let limit = Int(clamping: fetchLimit)
		let dateKey = ScrollbackAttribute.entryCreationDate.rawValue
		let idKey = ScrollbackAttribute.entryIdentifier.rawValue
		let lineKey = ScrollbackAttribute.logLineUniqueIdentifier.rawValue
		let view = NSPredicate(format: "%K == %@", ScrollbackAttribute.logLineViewIdentifier.rawValue, viewIdentifier)
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

	private static func rowBucket(_ cursor: ScrollbackRowCursor) -> NSPredicate {
		NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@",
		            ScrollbackAttribute.entryCreationDate.rawValue, NSNumber(value: cursor.timestamp),
		            ScrollbackAttribute.entryIdentifier.rawValue, NSNumber(value: cursor.insertionIdentifier),
		            ScrollbackAttribute.logLineUniqueIdentifier.rawValue, cursor.lineIdentifier)
	}
}

nonisolated extension ScrollbackRowCursor: Comparable { // nonisolated: value
	static func < (left: Self, right: Self) -> Bool {
		(left.timestamp, left.insertionIdentifier, left.lineIdentifier, left.rowURI)
			< (right.timestamp, right.insertionIdentifier, right.lineIdentifier, right.rowURI)
	}

	init?(object: NSManagedObject) {
		guard !object.objectID.isTemporaryID,
		      let date = object.value(forKey: ScrollbackAttribute.entryCreationDate.rawValue) as? NSNumber,
		      let identifier = object.value(forKey: ScrollbackAttribute.entryIdentifier.rawValue) as? NSNumber,
		      let line = object.value(forKey: ScrollbackAttribute.logLineUniqueIdentifier.rawValue) as? String,
		      date.doubleValue.isFinite else { return nil }
		self.init(timestamp: date.doubleValue, insertionIdentifier: identifier.int64Value,
		          lineIdentifier: line, rowURI: object.objectID.uriRepresentation().absoluteString)
	}
}
