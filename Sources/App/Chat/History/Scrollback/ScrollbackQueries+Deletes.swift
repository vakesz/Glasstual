// Copyright (c) 2016 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
import Foundation

nonisolated extension ScrollbackQueries {
	/** Deletes at most `chunkLimit` of the oldest rows `deletion` covers, and
	 saves.

	 A large removal is a run of these, so no one save holds an unbounded set
	 of deleted objects and the store can let queued work in between them.
	 `hasMore` says whether another chunk is due. Each chunk reports the line
	 identifiers no row left in the store still carries, so an identifier
	 shared with a row a later chunk deletes is reported by that chunk. */
	static func deleteOutcome(
		_ deletion: Deletion,
		in context: NSManagedObjectContext,
		viewIdentifier: String,
		chunkLimit: Int
	) -> ScrollbackDeletionOutcome {
		// Rollback below may discard only this deletion, never an earlier accepted write.
		if case let .failed(reason) = quickSave(context) {
			return .failed(reason)
		}
		if let parent = context.parent {
			let outcome = parent.performAndWait { quickSave(parent) }
			if case let .failed(reason) = outcome {
				return .failed(reason)
			}
			let deletion = parent.performAndWait {
				deleteOutcome(deletion, in: parent, viewIdentifier: viewIdentifier, chunkLimit: chunkLimit)
			}
			if case .deleted = deletion {
				context.reset()
			}
			return deletion
		}
		do {
			let view = NSPredicate(
				format: "%K == %@",
				ScrollbackAttribute.viewID.rawValue,
				viewIdentifier
			)
			let chunk = max(1, chunkLimit)
			let covered: NSPredicate
			let doomedLimit: Int
			var hasMore: Bool
			switch deletion {
			case let .everything(ceiling):
				covered = NSCompoundPredicate(andPredicateWithSubpredicates: [
					view,
					NSPredicate(
						format: "%K <= %@", ScrollbackAttribute.entryID.rawValue,
						NSNumber(value: Int64(clamping: ceiling))
					),
				])
				// One past the chunk is how a full chunk tells whether any are left.
				doomedLimit = chunk + 1
				hasMore = false
			case let .retainingNewest(count):
				covered = view
				let counting = NSFetchRequest<NSManagedObject>(entityName: entityName)
				counting.predicate = view
				let excess = try context.count(for: counting) - Int(clamping: count)
				guard excess > 0 else { return .deleted(DeletionResult(deletedCount: 0, uniqueIdentifiers: [])) }
				doomedLimit = min(excess, chunk)
				hasMore = excess > chunk
			}
			var doomed = try rowIdentities(in: context, matching: covered, oldestFirst: true, fetchLimit: doomedLimit)
			if doomed.count > chunk {
				doomed.removeLast(doomed.count - chunk)
				hasMore = true
			}
			let doomedObjects = Set(doomed.map(\.objectID))
			let removed = Set(doomed.compactMap(\.uniqueIdentifier))
			/* A line identifier names a line, not a row, so the store can hold
			 it twice; only the identifiers no surviving row still carries are
			 gone. Asked of the rows that share them rather than of every row the
			 view keeps. */
			var retained = Set<String>()
			let removedIdentifiers = Array(removed)
			for start in stride(from: 0, to: removedIdentifiers.count, by: deletionLookupBatchSize) {
				let batch = removedIdentifiers[start ..< min(start + deletionLookupBatchSize, removedIdentifiers.count)]
				let sharing = NSCompoundPredicate(andPredicateWithSubpredicates: [
					view,
					NSPredicate(format: "%K IN %@", ScrollbackAttribute.lineID.rawValue, Array(batch)),
				])
				for row in try rowIdentities(in: context, matching: sharing, oldestFirst: true, fetchLimit: 0)
					where doomedObjects.contains(row.objectID) == false
				{
					if let identifier = row.uniqueIdentifier {
						retained.insert(identifier)
					}
				}
			}
			for objectID in doomedObjects {
				context.delete(context.object(with: objectID))
			}
			try context.save()
			return .deleted(DeletionResult(
				deletedCount: UInt(doomed.count),
				uniqueIdentifiers: removed.subtracting(retained).sorted(),
				hasMore: hasMore
			))
		} catch {
			context.rollback()
			return .failed(error.localizedDescription)
		}
	}

	/// How many line identifiers one lookup names, so a pass that prunes a large
	/// backlog never builds a single unbounded `IN` list.
	private static let deletionLookupBatchSize = 500

	/** The object and line identifier of the rows `predicate` matches, and
	 nothing else of them.

	 Ordered the way reads page: by the line's own time, then by insertion, then
	 by line identifier. Insertion order alone is not age — a server-history page
	 is inserted after lines hours newer than it — so pruning by it deleted
	 recent lines and kept old ones. Rows that tie on all three keys are the same
	 moment of the same line, and which of them goes is immaterial. */
	private static func rowIdentities(
		in context: NSManagedObjectContext,
		matching predicate: NSPredicate,
		oldestFirst: Bool,
		fetchLimit: Int
	) throws -> [(objectID: NSManagedObjectID, uniqueIdentifier: String?)] {
		let objectIDKey = "objectID"
		let objectID = NSExpressionDescription()
		objectID.name = objectIDKey
		objectID.expression = NSExpression.expressionForEvaluatedObject()
		objectID.expressionResultType = .objectIDAttributeType
		let request = NSFetchRequest<NSDictionary>(entityName: entityName)
		request.resultType = .dictionaryResultType
		request.predicate = predicate
		request.propertiesToFetch = [objectID, ScrollbackAttribute.lineID.rawValue]
		request.sortDescriptors = [
			NSSortDescriptor(key: ScrollbackAttribute.createdAt.rawValue, ascending: oldestFirst),
			NSSortDescriptor(key: ScrollbackAttribute.entryID.rawValue, ascending: oldestFirst),
			NSSortDescriptor(key: ScrollbackAttribute.lineID.rawValue, ascending: oldestFirst),
		]
		request.fetchLimit = fetchLimit
		return try context.fetch(request).compactMap { row in
			guard let identifier = row[objectIDKey] as? NSManagedObjectID else { return nil }
			return (identifier, row[ScrollbackAttribute.lineID.rawValue] as? String)
		}
	}
}
