/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2016 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CoreData
import Foundation
import os

/// Core Data operations for the historic log store.
///
/// Every function here runs inside a `perform` block on the context it is
/// handed, so none of them may touch `HistoricLogStore` state: the actor
/// passes in the values a query needs and gets a `Sendable` result back.
/// `NSManagedObjectContext` is itself `Sendable`; fetch requests and the
/// model are not, so both are built from the context inside the block.
/// Locates this framework's bundle. `Bundle(for:)` needs a class to point at;
/// this one exists for no other reason.
private final nonisolated class HistoricLogStoreBundleToken {} // nonisolated: immutable

/// Read only the historic timestamp; opening storage must not construct UI log
/// lines, populate new identifiers or read current rendering preferences.
@objc(GLTHistoricTimestampArchive)
private final nonisolated class HistoricTimestampArchive: NSObject, NSSecureCoding { // nonisolated: immutable
	static var supportsSecureCoding: Bool {
		true
	}

	let date: Date
	required init?(coder: NSCoder) {
		guard let date = coder.decodeObject(of: NSDate.self, forKey: "receivedAt") as Date? else { return nil }
		self.date = date
	}

	func encode(with coder: NSCoder) {
		coder.encode(date, forKey: "receivedAt")
	}

	static func read(_ data: Data) -> Date? {
		guard let decoder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
		decoder.requiresSecureCoding = true
		decoder.decodingFailurePolicy = .setErrorAndReturn
		decoder.setClass(Self.self, forClassName: "TVCLogLine")
		defer { decoder.finishDecoding() }
		return decoder.decodeObject(of: Self.self, forKey: NSKeyedArchiveRootObjectKey)?.date
	}
}

/// Where the name of the database file is kept between launches.
nonisolated protocol HistoricLogFilenameStoring: Sendable { // nonisolated: value
	var databaseFilename: String? { get nonmutating set }
}

nonisolated enum HistoricLogDatabase { // nonisolated: value
	static let modelName = "HistoricLogFileStorageModel"
	static let entityName = "LogLine2"

	static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "Storage"
	)

	/// Which rows a deletion covers. `Sendable` so the request can be rebuilt
	/// on the parent context's queue instead of being carried across.
	enum Deletion: Sendable {
		case everything
		case entriesBelow(entryIdentifier: UInt)
		case retainingNewest(count: UInt)
	}

	/// Rows a deletion removed, together with the unique identifiers the client
	/// has to be told about. Returned rather than reported from here: the
	/// remote object proxy belongs to the actor, not to the context's queue.
	struct DeletionResult: Sendable {
		let deletedCount: UInt
		let uniqueIdentifiers: [String]
	}

	// MARK: - Stack

	/// Builds the stack, or throws what stopped it. The reason travels: it is
	/// the only thing the failure alert has to tell the reader.
	static func makeStack(at url: URL) throws -> NSManagedObjectContext {
		guard
			let modelURL = modelBundle.url(forResource: modelName, withExtension: "momd"),
			let model = NSManagedObjectModel(contentsOf: modelURL)
		else {
			logger.error("Historic log model is missing")

			throw CocoaError(.fileNoSuchFile)
		}

		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
		// Inferred migration may legally drop entire entities and their archives.
		// Open only compatible stores until a data-preserving migration is defined.
		let options: [AnyHashable: Any] = [
			NSMigratePersistentStoresAutomaticallyOption: false,
			NSInferMappingModelAutomaticallyOption: false,
			NSSQLitePragmasOption: ["synchronous": "NORMAL", "journal_mode": "WAL"],
		]

		do {
			_ = try coordinator.addPersistentStore(type: .sqlite, at: url, options: options)
		} catch {
			logger.error("Error creating persistent store: \(error.localizedDescription, privacy: .public)")

			throw error
		}

		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		context.persistentStoreCoordinator = coordinator
		context.undoManager = nil

		return context
	}

	/// The bundle the compiled model ships in. It travels with this framework,
	/// so it is found through a type of this framework's rather than through
	/// `Bundle.main`, which is the host application under test.
	private static var modelBundle: Bundle {
		Bundle(for: HistoricLogStoreBundleToken.self)
	}

	/// A child context reaches the model through its parent's coordinator.
	private static func model(in context: NSManagedObjectContext) -> NSManagedObjectModel? {
		context.persistentStoreCoordinator?.managedObjectModel
			?? context.parent?.persistentStoreCoordinator?.managedObjectModel
	}

	// MARK: - Requests

	static func conditionalRequest(
		in context: NSManagedObjectContext,
		viewIdentifier: String,
		ascending: Bool = true,
		fetchLimit: UInt = 0,
		lowestEntryIdentifier: UInt = 0,
		highestEntryIdentifier: UInt = UInt(Int.max),
		limitToDate: Date? = nil,
		resultType: NSFetchRequestResultType
	) -> NSFetchRequest<NSManagedObject>? {
		let variables: [String: Any] = [
			"view_id": viewIdentifier,
			"entry_id_lowest": NSNumber(value: lowestEntryIdentifier),
			"entry_id_highest": NSNumber(value: highestEntryIdentifier),
			"creation_date": NSNumber(value: (limitToDate ?? .distantFuture).timeIntervalSince1970),
		]

		guard let request = model(in: context)?.fetchRequestFromTemplate(
			withName: "GenericConditional",
			substitutionVariables: variables
		) as? NSFetchRequest<NSManagedObject> else {
			return nil
		}

		if fetchLimit > 0 {
			request.fetchLimit = Int(clamping: fetchLimit)
		}

		request.includesPendingChanges = true
		request.includesPropertyValues = true
		request.returnsObjectsAsFaults = false
		request.resultType = resultType
		request.sortDescriptors = [
			NSSortDescriptor(key: HistoricLogAttribute.entryCreationDate.rawValue, ascending: ascending),
			NSSortDescriptor(key: HistoricLogAttribute.entryIdentifier.rawValue, ascending: ascending),
			NSSortDescriptor(key: HistoricLogAttribute.logLineUniqueIdentifier.rawValue, ascending: ascending),
		]

		return request
	}

	// MARK: - Reads

	static func fetchEntries(
		in context: NSManagedObjectContext,
		viewIdentifier: String,
		ascending: Bool,
		fetchLimit: UInt,
		lowestEntryIdentifier: UInt = 0,
		highestEntryIdentifier: UInt = UInt(Int.max),
		limitToDate: Date?
	) -> [HistoricLogEntry] {
		fetchOutcome(
			in: context, viewIdentifier: viewIdentifier, ascending: ascending, fetchLimit: fetchLimit,
			lowestEntryIdentifier: lowestEntryIdentifier, highestEntryIdentifier: highestEntryIdentifier,
			limitToDate: limitToDate
		).entries
	}

	static func fetchOutcome(
		in context: NSManagedObjectContext,
		viewIdentifier: String,
		ascending: Bool,
		fetchLimit: UInt,
		lowestEntryIdentifier: UInt = 0,
		highestEntryIdentifier: UInt = UInt(Int.max),
		limitToDate: Date?
	) -> HistoricLogFetchOutcome {
		if let limitToDate, !limitToDate.timeIntervalSince1970.isFinite {
			return .failed(.invalidRequest)
		}
		guard let request = conditionalRequest(
			in: context,
			viewIdentifier: viewIdentifier,
			ascending: ascending,
			fetchLimit: fetchLimit,
			lowestEntryIdentifier: lowestEntryIdentifier,
			highestEntryIdentifier: highestEntryIdentifier,
			limitToDate: limitToDate,
			resultType: .managedObjectResultType
		) else { return .failed(.invalidRequest) }

		do {
			let objects = try context.fetch(request)

			let entries = objects.compactMap { HistoricLogEntry(managedObject: $0) }
			guard entries.count == objects.count else { return .failed(.invalidEntry) }
			return .page(entries)
		} catch {
			logger.error("Error occurred fetching objects: \(error.localizedDescription, privacy: .public)")

			return .failed(.read(error.localizedDescription))
		}
	}

	/// Allocation must include every row, even one excluded by the display date
	/// filter or carrying an unreadable archive. A failed read must not restart IDs.
	static func initialCounts(
		in context: NSManagedObjectContext,
		viewIdentifier: String
	) throws -> (lineCount: UInt, maximumIdentifier: UInt) {
		let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
		request.predicate = NSPredicate(
			format: "%K == %@", HistoricLogAttribute.logLineViewIdentifier.rawValue, viewIdentifier
		)
		request.includesPendingChanges = true
		let lineCount = try UInt(context.count(for: request))
		request.sortDescriptors = [
			NSSortDescriptor(key: HistoricLogAttribute.entryIdentifier.rawValue, ascending: false),
		]
		request.fetchLimit = 1
		let maximum = try (context.fetch(request).first?.value(
			forKey: HistoricLogAttribute.entryIdentifier.rawValue
		) as? NSNumber)?.int64Value ?? 0

		return (lineCount, UInt(max(0, maximum)))
	}

	static func fetchEntries(
		in context: NSManagedObjectContext,
		viewIdentifier: String,
		before uniqueIdentifier: String,
		fetchLimit: UInt,
		limitToDate: Date?
	) -> [HistoricLogEntry] {
		fetchOutcome(in: context, viewIdentifier: viewIdentifier, before: uniqueIdentifier,
		             fetchLimit: fetchLimit, limitToDate: limitToDate).entries
	}

	static func fetchOutcome(
		in context: NSManagedObjectContext,
		viewIdentifier: String,
		before uniqueIdentifier: String,
		fetchLimit: UInt,
		limitToDate: Date?
	) -> HistoricLogFetchOutcome {
		guard fetchLimit > 0 else { return .failed(.invalidRequest) }
		if let limitToDate, !limitToDate.timeIntervalSince1970.isFinite {
			return .failed(.invalidRequest)
		}
		guard let request = model(in: context)?.fetchRequestFromTemplate(
			withName: "UniqueIdToEntryId",
			substitutionVariables: [
				"view_id": viewIdentifier,
				"unique_id": uniqueIdentifier,
			]
		) as? NSFetchRequest<NSManagedObject> else { return .failed(.invalidRequest) }

		// The public cursor names a line, not a Core Data row. Do not guess if
		// an old store contains multiple rows with that same line identity.
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
			guard let cursor = HistoricLogRowCursor(object: anchor) else { return .failed(.invalidEntry) }
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
	static func insert(_ logLine: HistoricLogEntry, in context: NSManagedObjectContext, entryIdentifier: UInt) -> Bool {
		guard let entity = NSEntityDescription.entity(forEntityName: entityName, in: context) else {
			logger.error("The LogLine2 entity is missing")

			return false
		}

		let entry = NSManagedObject(entity: entity, insertInto: context)

		entry.setValue(
			NSNumber(value: entryIdentifier),
			forKey: HistoricLogAttribute.entryIdentifier.rawValue
		)
		/* The line's own timestamp, not the moment it reached the database: the
		 fetch template both sorts and filters on this column, and a chat-history
		 replay inserts lines that are hours old. */
		entry.setValue(
			NSNumber(value: logLine.creationDate),
			forKey: HistoricLogAttribute.entryCreationDate.rawValue
		)
		entry.setValue(logLine.viewIdentifier, forKey: HistoricLogAttribute.logLineViewIdentifier.rawValue)
		entry.setValue(logLine.data, forKey: HistoricLogAttribute.logLineData.rawValue)
		entry.setValue(logLine.uniqueIdentifier, forKey: HistoricLogAttribute.logLineUniqueIdentifier.rawValue)
		entry.setValue(
			NSNumber(value: logLine.sessionIdentifier),
			forKey: HistoricLogAttribute.sessionIdentifier.rawValue
		)
		return true
	}

	// MARK: - Re-stamping

	/// Records that the stored rows carry the line's own time. Versioned so a
	/// later correction can run its own pass over a store this one finished.
	static let restampMetadataKey = "restampedEntryCreationDate"
	/// The re-stamp this build performs.
	static let restampVersion = 1

	/// Rows read and rewritten between saves. Large enough that a full store is
	/// a handful of transactions, small enough that none of them is long.
	private static let restampBatchSize = 500

	/// How far a stamp may sit from the line's own time and still be left alone.
	/// Earlier versions wrote the insert time, which is later than the line's
	/// time by anything from milliseconds to hours.
	private static let restampTolerance: TimeInterval = 1

	/// Whether this store still has to be re-stamped.
	static func needsEntryCreationDateRestamp(in context: NSManagedObjectContext) -> Bool {
		guard let coordinator = context.persistentStoreCoordinator,
		      let store = coordinator.persistentStores.first
		else { return false }

		let recorded = coordinator.metadata(for: store)[restampMetadataKey] as? NSNumber

		return (recorded?.intValue ?? 0) < restampVersion
	}

	/** Rewrites `entryCreationDate` from the line's own `receivedAt`.

	 Rows written before the insert started storing the line's time carry the
	 moment they reached the database, so they sort against newer rows by a
	 different clock until they age out. This runs once, the first time the store
	 opens after the change, and records itself in the store's metadata. A pass
	 that throws leaves the flag unwritten, so the next launch tries again.
	 */
	@discardableResult
	static func restampEntryCreationDates(in context: NSManagedObjectContext) -> HistoricLogSaveOutcome {
		guard needsEntryCreationDateRestamp(in: context) else { return .saved }

		do {
			let restamped = try restampRows(in: context)

			try recordRestampCompletion(in: context)

			logger.info("Re-stamped \(restamped) historic rows with the line's own time")
			return .saved
		} catch {
			logger.error("Failed to re-stamp historic rows: \(error.localizedDescription, privacy: .public)")
			return .failed(error.localizedDescription)
		}
	}

	/// The identifiers are read first and the rows fetched a batch at a time, so
	/// no single transaction holds the whole store.
	private static func restampRows(in context: NSManagedObjectContext) throws -> Int {
		let request = NSFetchRequest<NSManagedObjectID>(entityName: entityName)
		request.resultType = .managedObjectIDResultType
		request.includesPendingChanges = false

		let objectIDs = try context.fetch(request)
		var restamped = 0

		for batch in stride(from: 0, to: objectIDs.count, by: restampBatchSize) {
			let upperBound = min(batch + restampBatchSize, objectIDs.count)

			for objectID in objectIDs[batch ..< upperBound] where restamp(objectID, in: context) {
				restamped += 1
			}

			if context.hasChanges {
				try context.save()
			}

			context.reset()
		}

		return restamped
	}

	/// Whether the row was rewritten. A row whose archive cannot be decoded is
	/// left as it stands: there is nothing better to stamp it with.
	private static func restamp(_ objectID: NSManagedObjectID, in context: NSManagedObjectContext) -> Bool {
		guard let object = try? context.existingObject(with: objectID),
		      let entry = HistoricLogEntry(managedObject: object),
		      let date = HistoricTimestampArchive.read(entry.data)
		else { return false }

		let receivedAt = date.timeIntervalSince1970

		guard abs(receivedAt - entry.creationDate) > restampTolerance else { return false }

		object.setValue(NSNumber(value: receivedAt), forKey: HistoricLogAttribute.entryCreationDate.rawValue)

		return true
	}

	/// Core Data holds store metadata in memory until a save carries it down, so
	/// the flag is written through a save of its own rather than left to the
	/// next one.
	private static func recordRestampCompletion(in context: NSManagedObjectContext) throws {
		guard let coordinator = context.persistentStoreCoordinator,
		      let store = coordinator.persistentStores.first
		else { return }

		var metadata = coordinator.metadata(for: store)
		metadata[restampMetadataKey] = NSNumber(value: restampVersion)
		coordinator.setMetadata(metadata, for: store)

		try context.save()
	}

	@discardableResult
	static func quickSave(_ context: NSManagedObjectContext) -> HistoricLogSaveOutcome {
		guard context.hasChanges else { return .saved }

		do {
			try context.save()
		} catch {
			logger.error("Failed to perform save: \(error.localizedDescription, privacy: .public)")
			return .failed(error.localizedDescription)
		}
		return .saved
	}

	// MARK: - Deletes

	static func deleteOutcome(
		_ deletion: Deletion,
		in context: NSManagedObjectContext,
		viewIdentifier: String
	) -> HistoricLogDeletionOutcome {
		// Rollback below may discard only this deletion, never an earlier accepted write.
		if case let .failed(reason) = quickSave(context) {
			return .failed(reason)
		}
		if let parent = context.parent {
			let outcome = parent.performAndWait { quickSave(parent) }
			if case let .failed(reason) = outcome {
				return .failed(reason)
			}
			let deletion = parent.performAndWait { deleteOutcome(deletion, in: parent, viewIdentifier: viewIdentifier) }
			if case .deleted = deletion {
				context.reset()
			}
			return deletion
		}
		do {
			let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
			request.predicate = NSPredicate(
				format: "%K == %@",
				HistoricLogAttribute.logLineViewIdentifier.rawValue,
				viewIdentifier
			)
			let objects = try context.fetch(request).sorted { left, right in
				let leftID = (left.value(forKey: HistoricLogAttribute.entryIdentifier.rawValue) as? NSNumber)?
					.int64Value ?? 0
				let rightID = (right.value(forKey: HistoricLogAttribute.entryIdentifier.rawValue) as? NSNumber)?
					.int64Value ?? 0
				if leftID != rightID {
					return leftID < rightID
				}
				return left.objectID.uriRepresentation().absoluteString < right.objectID.uriRepresentation()
					.absoluteString
			}
			let doomed: [NSManagedObject] = switch deletion {
			case .everything: objects
			case let .retainingNewest(count): Array(objects.prefix(max(0, objects.count - Int(clamping: count))))
			case let .entriesBelow(identifier):
				objects
					.filter {
						(($0.value(forKey: HistoricLogAttribute.entryIdentifier.rawValue) as? NSNumber)?
							.int64Value ?? 0) <=
							Int64(clamping: identifier)
					}
			}
			let ids = Set(doomed.map(\.objectID))
			let removed = Set(doomed
				.compactMap { $0.value(forKey: HistoricLogAttribute.logLineUniqueIdentifier.rawValue) as? String })
			let retained = Set(objects.filter { !ids.contains($0.objectID) }.compactMap {
				$0.value(forKey: HistoricLogAttribute.logLineUniqueIdentifier.rawValue) as? String
			})
			for object in doomed {
				context.delete(object)
			}
			try context.save()
			return .deleted(DeletionResult(
				deletedCount: UInt(doomed.count),
				uniqueIdentifiers: removed.subtracting(retained).sorted()
			))
		} catch {
			context.rollback()
			return .failed(error.localizedDescription)
		}
	}
}
