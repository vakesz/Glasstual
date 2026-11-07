// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
import Foundation
import os

nonisolated extension ScrollbackQueries {
	/// Matches of one view, newest first, up to the query's limit; or why the
	/// read failed.
	enum SearchResult {
		case success([ScrollbackSearchHit])
		case failure(String)
	}

	/** The rows of one view whose text, or whose sender, contains the query.

	 `normalized` has already folded the text, so it is compared against the
	 folded column with a plain `CONTAINS`; the sender is short and compared
	 with `[cd]`. Rows without text — events, redacted lines and rows whose
	 archive could not be read — are excluded however the query reads. */
	static func search(
		in context: NSManagedObjectContext,
		viewIdentifier: String,
		query: ScrollbackSearchQuery
	) -> SearchResult {
		let dateKey = ScrollbackAttribute.createdAt.rawValue
		let entryKey = ScrollbackAttribute.entryID.rawValue
		let lineKey = ScrollbackAttribute.lineID.rawValue
		var clauses = [
			NSPredicate(format: "%K == %@", ScrollbackAttribute.viewID.rawValue, viewIdentifier),
			NSPredicate(format: "%K != %@", ScrollbackAttribute.searchText.rawValue, ""),
		]
		if let from = query.from {
			clauses.append(NSPredicate(format: "%K >= %@", dateKey, NSNumber(value: from.timeIntervalSince1970)))
		}
		if let through = query.through {
			clauses.append(NSPredicate(format: "%K < %@", dateKey, NSNumber(value: through.timeIntervalSince1970)))
		}
		if query.text.isEmpty == false {
			clauses.append(NSCompoundPredicate(orPredicateWithSubpredicates: [
				NSPredicate(format: "%K CONTAINS %@", ScrollbackAttribute.searchText.rawValue, query.text),
				NSPredicate(format: "%K CONTAINS[cd] %@", ScrollbackAttribute.sender.rawValue, query.text),
			]))
		}
		if query.sender.isEmpty == false {
			clauses.append(NSPredicate(format: "%K CONTAINS[cd] %@", ScrollbackAttribute.sender.rawValue, query.sender))
		}

		let objectIDKey = "objectID"
		let objectID = NSExpressionDescription()
		objectID.name = objectIDKey
		objectID.expression = NSExpression.expressionForEvaluatedObject()
		objectID.expressionResultType = .objectIDAttributeType
		let request = NSFetchRequest<NSDictionary>(entityName: entityName)
		request.resultType = .dictionaryResultType
		request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
		request.propertiesToFetch = [
			objectID, dateKey, entryKey, lineKey,
			ScrollbackAttribute.sender.rawValue, ScrollbackAttribute.plainText.rawValue,
		]
		request.sortDescriptors = [
			NSSortDescriptor(key: dateKey, ascending: false),
			NSSortDescriptor(key: entryKey, ascending: false),
			NSSortDescriptor(key: lineKey, ascending: false),
		]
		// One more than the cap, so the caller can tell a full answer from a cut one.
		request.fetchLimit = query.limit + 1
		do {
			let rows = try context.fetch(request)
			let hits = rows.compactMap { row -> ScrollbackSearchHit? in
				guard let identifier = row[objectIDKey] as? NSManagedObjectID,
				      let timestamp = (row[dateKey] as? NSNumber)?.doubleValue, timestamp.isFinite,
				      let insertion = (row[entryKey] as? NSNumber)?.int64Value,
				      let line = row[lineKey] as? String
				else { return nil }
				return ScrollbackSearchHit(
					viewIdentifier: viewIdentifier,
					lineIdentifier: line,
					sender: row[ScrollbackAttribute.sender.rawValue] as? String ?? "",
					text: row[ScrollbackAttribute.plainText.rawValue] as? String ?? "",
					timestamp: timestamp,
					cursor: ScrollbackRowCursor(
						timestamp: timestamp, insertionIdentifier: insertion, lineIdentifier: line,
						rowURI: identifier.uriRepresentation().absoluteString
					)
				)
			}
			return .success(hits)
		} catch {
			logger.error("Failed to search history: \(error.localizedDescription, privacy: .public)")
			return .failure(error.localizedDescription)
		}
	}
}
