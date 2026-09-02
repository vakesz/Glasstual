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

	/// The identifier a lookup returns when the view has no such entry.
	static let missingEntryIdentifier = UInt.max

	/// Which rows a deletion covers. `Sendable` so the request can be rebuilt
	/// on the parent context's queue instead of being carried across.
	enum Deletion: Sendable {
		case everything
		case entriesBelow(entryIdentifier: UInt)
	}

	/// Rows a deletion removed, together with the unique identifiers the client
	/// has to be told about. Returned rather than reported from here: the
	/// remote object proxy belongs to the actor, not to the context's queue.
	struct DeletionResult: Sendable {
		let deletedCount: UInt
		let uniqueIdentifiers: [String]

		static let none = DeletionResult(deletedCount: 0, uniqueIdentifiers: [])
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
		let options: [AnyHashable: Any] = [
			NSMigratePersistentStoresAutomaticallyOption: true,
			NSInferMappingModelAutomaticallyOption: true,
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
		context.retainsRegisteredObjects = true
		context.undoManager = nil

		return context
	}

	/// The bundle the compiled model ships in. It travels with this framework,
	/// so it is found through a type of this framework's rather than through
	/// `Bundle.main`, which is the host application under test.
	private static var modelBundle: Bundle {
		Bundle(for: HistoricLogStoreBundleToken.self)
	}

	static func makeViewContext(parent: NSManagedObjectContext) -> NSManagedObjectContext {
		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		context.parent = parent
		context.retainsRegisteredObjects = true
		context.undoManager = nil

		return context
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
			request.fetchLimit = Int(fetchLimit)
		}

		request.includesPendingChanges = true
		request.includesPropertyValues = true
		request.returnsObjectsAsFaults = false
		request.resultType = resultType
		request.sortDescriptors = [
			NSSortDescriptor(key: HistoricLogAttribute.entryCreationDate.rawValue, ascending: ascending),
		]

		return request
	}

	private static func deletionRequest(
		_ deletion: Deletion,
		in context: NSManagedObjectContext,
		viewIdentifier: String
	) -> NSFetchRequest<NSManagedObject>? {
		switch deletion {
		case .everything:
			return conditionalRequest(
				in: context,
				viewIdentifier: viewIdentifier,
				resultType: .managedObjectResultType
			)
		case let .entriesBelow(entryIdentifier):
			guard let request = model(in: context)?.fetchRequestFromTemplate(
				withName: "Truncate",
				substitutionVariables: [
					"view_id": viewIdentifier,
					"entry_id_lowest": NSNumber(value: entryIdentifier),
				]
			) as? NSFetchRequest<NSManagedObject> else {
				return nil
			}

			request.includesPendingChanges = true
			request.includesPropertyValues = true
			request.returnsObjectsAsFaults = false

			return request
		}
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
		guard let request = conditionalRequest(
			in: context,
			viewIdentifier: viewIdentifier,
			ascending: ascending,
			fetchLimit: fetchLimit,
			lowestEntryIdentifier: lowestEntryIdentifier,
			highestEntryIdentifier: highestEntryIdentifier,
			limitToDate: limitToDate,
			resultType: .managedObjectResultType
		) else { return [] }

		do {
			let objects = try context.fetch(request)

			return objects.compactMap { HistoricLogEntry(managedObject: $0) }
		} catch {
			logger.error("Error occurred fetching objects: \(error.localizedDescription, privacy: .public)")

			return []
		}
	}

	static func lineCount(in context: NSManagedObjectContext, viewIdentifier: String) -> UInt {
		guard let request = conditionalRequest(
			in: context,
			viewIdentifier: viewIdentifier,
			resultType: .countResultType
		) else { return 0 }

		do {
			return try UInt(context.count(for: request))
		} catch {
			logger.error("Failed to count log lines: \(error.localizedDescription, privacy: .public)")

			return 0
		}
	}

	static func newestIdentifier(in context: NSManagedObjectContext, viewIdentifier: String) -> UInt {
		guard let request = conditionalRequest(
			in: context,
			viewIdentifier: viewIdentifier,
			ascending: false,
			fetchLimit: 1,
			resultType: .managedObjectResultType
		) else { return 0 }

		do {
			return try (context.fetch(request).first?.value(
				forKey: HistoricLogAttribute.entryIdentifier.rawValue
			) as? NSNumber)?.uintValue ?? 0
		} catch {
			logger.error("Failed to fetch newest identifier: \(error.localizedDescription, privacy: .public)")

			return 0
		}
	}

	static func entryIdentifier(
		in context: NSManagedObjectContext,
		viewIdentifier: String,
		uniqueIdentifier: String
	) -> UInt {
		guard let request = model(in: context)?.fetchRequestFromTemplate(
			withName: "UniqueIdToEntryId",
			substitutionVariables: [
				"view_id": viewIdentifier,
				"unique_id": uniqueIdentifier,
			]
		) as? NSFetchRequest<NSManagedObject> else { return missingEntryIdentifier }

		request.includesPendingChanges = true
		request.includesPropertyValues = true
		request.returnsObjectsAsFaults = false

		do {
			return try (context.fetch(request).first?.value(
				forKey: HistoricLogAttribute.entryIdentifier.rawValue
			) as? NSNumber)?
				.uintValue ?? missingEntryIdentifier
		} catch {
			logger.error("Failed to resolve unique identifier: \(error.localizedDescription, privacy: .public)")

			return missingEntryIdentifier
		}
	}

	// MARK: - Writes

	static func insert(_ logLine: HistoricLogEntry, in context: NSManagedObjectContext, entryIdentifier: UInt) {
		guard let entity = NSEntityDescription.entity(forEntityName: entityName, in: context) else {
			logger.error("The LogLine2 entity is missing")

			return
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
	static func restampEntryCreationDates(in context: NSManagedObjectContext) {
		guard needsEntryCreationDateRestamp(in: context) else { return }

		do {
			let restamped = try restampRows(in: context)

			try recordRestampCompletion(in: context)

			logger.info("Re-stamped \(restamped) historic rows with the line's own time")
		} catch {
			context.reset()

			logger.error("Failed to re-stamp historic rows: \(error.localizedDescription, privacy: .public)")
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
		      let line = LogLine(data: entry.data)
		else { return false }

		let receivedAt = line.receivedAt.timeIntervalSince1970

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

	static func quickSave(_ context: NSManagedObjectContext) {
		guard context.hasChanges else { return }

		do {
			try context.save()
		} catch {
			logger.error("Failed to perform save: \(error.localizedDescription, privacy: .public)")
		}

		context.reset()
	}

	// MARK: - Deletes

	static func delete(
		_ deletion: Deletion,
		in context: NSManagedObjectContext,
		viewIdentifier: String
	) -> DeletionResult {
		guard
			let parentContext = context.parent,
			let request = deletionRequest(deletion, in: context, viewIdentifier: viewIdentifier)
		else { return .none }

		quickSave(context)
		parentContext.performAndWait { quickSave(parentContext) }

		let uniqueIdentifiers = doomedUniqueIdentifiers(request, in: context)

		guard uniqueIdentifiers.isEmpty == false else { return .none }

		/* The batch delete runs on the parent, which owns the coordinator. Its
		 request is rebuilt there from the same `Sendable` inputs rather than
		 carried across the hop. */
		let objectIDs = parentContext.performAndWait {
			executeBatchDelete(deletion, in: parentContext, viewIdentifier: viewIdentifier)
		}

		guard let objectIDs, objectIDs.isEmpty == false else { return .none }

		NSManagedObjectContext.mergeChanges(
			fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
			into: [parentContext, context]
		)

		logger.debug("Deleted \(objectIDs.count) rows in \(viewIdentifier, privacy: .public)")

		return DeletionResult(deletedCount: UInt(objectIDs.count), uniqueIdentifiers: uniqueIdentifiers)
	}

	private static func doomedUniqueIdentifiers(
		_ fetchRequest: NSFetchRequest<NSManagedObject>,
		in context: NSManagedObjectContext
	) -> [String] {
		guard let identifierRequest = fetchRequest.copy() as? NSFetchRequest<NSDictionary> else {
			assertionFailure("Unable to copy the historic-log identifier fetch request")

			return []
		}

		identifierRequest.resultType = .dictionaryResultType
		identifierRequest.propertiesToFetch = [HistoricLogAttribute.logLineUniqueIdentifier.rawValue]
		/* A dictionary result with a batch size has to fetch the object ID too,
		 and Core Data logs a complaint and drops the batching when it does not.
		 Nothing here wants batching: the identifiers are read once. */
		identifierRequest.fetchBatchSize = 0
		identifierRequest.includesPendingChanges = false
		identifierRequest.returnsObjectsAsFaults = false
		identifierRequest.sortDescriptors = nil

		do {
			return try context.fetch(identifierRequest).compactMap {
				$0[HistoricLogAttribute.logLineUniqueIdentifier.rawValue] as? String
			}
		} catch {
			logger.error("Error occurred fetching identifiers: \(error.localizedDescription, privacy: .public)")

			return []
		}
	}

	private static func executeBatchDelete(
		_ deletion: Deletion,
		in parentContext: NSManagedObjectContext,
		viewIdentifier: String
	) -> [NSManagedObjectID]? {
		guard
			let request = deletionRequest(deletion, in: parentContext, viewIdentifier: viewIdentifier),
			let deleteFetchRequest = request.copy() as? NSFetchRequest<NSFetchRequestResult>
		else {
			assertionFailure("Unable to copy the historic-log deletion fetch request")

			return nil
		}

		deleteFetchRequest.resultType = .managedObjectResultType
		deleteFetchRequest.includesPendingChanges = false
		deleteFetchRequest.sortDescriptors = nil

		let batchRequest = NSBatchDeleteRequest(fetchRequest: deleteFetchRequest)
		batchRequest.resultType = .resultTypeObjectIDs

		do {
			guard let result = try parentContext.execute(batchRequest) as? NSBatchDeleteResult else {
				throw CocoaError(.coderInvalidValue)
			}

			return result.result as? [NSManagedObjectID]
		} catch {
			logger.error("Failed to perform batch delete: \(error.localizedDescription, privacy: .public)")

			return nil
		}
	}
}
