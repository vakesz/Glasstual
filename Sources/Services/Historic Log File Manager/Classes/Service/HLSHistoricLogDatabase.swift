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

/// The Core Data half of the historic log service.
///
/// Every function here runs inside a `perform` block on the context it is
/// handed, so none of them may touch `HistoricLogStore` state: the actor
/// passes in the values a query needs and gets a `Sendable` result back.
/// `NSManagedObjectContext` is itself `Sendable`; fetch requests and the
/// model are not, so both are built from the context inside the block.
enum HistoricLogDatabase {
	static let filenameKey = "TVCLogControllerHistoricLogFileSavePath_v3"
	static let modelName = "HistoricLogFileStorageModel"
	static let entityName = "LogLine2"

	static let logger = Logger(
		subsystem: "com.vakesz.glasstual.ScrollbackHistoryManager",
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

	static func makeStack(at url: URL) -> NSManagedObjectContext? {
		guard
			let modelURL = modelBundle.url(forResource: modelName, withExtension: "momd"),
			let model = NSManagedObjectModel(contentsOf: modelURL)
		else {
			logger.error("Historic log model is missing")

			return nil
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

			return nil
		}

		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		context.persistentStoreCoordinator = coordinator
		context.retainsRegisteredObjects = true
		context.undoManager = nil

		return context
	}

	/// The bundle the compiled model ships in: the service bundle in the
	/// service, the test bundle under test. `Bundle.main` is neither.
	private static var modelBundle: Bundle {
		Bundle(for: HistoricLogProcessMain.self)
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
		request.sortDescriptors = [NSSortDescriptor(key: "entryCreationDate", ascending: ascending)]

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
	) -> [LogLineXPC] {
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

			logger.debug("\(objects.count) results fetched for view \(viewIdentifier, privacy: .public)")

			return objects.compactMap { LogLineXPC(managedObject: $0) }
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
			return try (context.fetch(request).first?.value(forKey: "entryIdentifier") as? NSNumber)?.uintValue ?? 0
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
			return try (context.fetch(request).first?.value(forKey: "entryIdentifier") as? NSNumber)?
				.uintValue ?? missingEntryIdentifier
		} catch {
			logger.error("Failed to resolve unique identifier: \(error.localizedDescription, privacy: .public)")

			return missingEntryIdentifier
		}
	}

	// MARK: - Writes

	static func insert(_ logLine: LogLineXPC, in context: NSManagedObjectContext, entryIdentifier: UInt) {
		guard let entity = NSEntityDescription.entity(forEntityName: entityName, in: context) else {
			logger.error("The LogLine2 entity is missing")

			return
		}

		let entry = NSManagedObject(entity: entity, insertInto: context)

		entry.setValue(NSNumber(value: entryIdentifier), forKey: "entryIdentifier")
		entry.setValue(NSNumber(value: Date().timeIntervalSince1970), forKey: "entryCreationDate")
		entry.setValue(logLine.viewIdentifier, forKey: "logLineViewIdentifier")
		entry.setValue(logLine.data, forKey: "logLineData")
		entry.setValue(logLine.uniqueIdentifier, forKey: "logLineUniqueIdentifier")
		entry.setValue(NSNumber(value: logLine.sessionIdentifier), forKey: "sessionIdentifier")
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
		identifierRequest.propertiesToFetch = ["logLineUniqueIdentifier"]
		identifierRequest.includesPendingChanges = false
		identifierRequest.returnsObjectsAsFaults = false
		identifierRequest.sortDescriptors = nil

		do {
			return try context.fetch(identifierRequest).compactMap { $0["logLineUniqueIdentifier"] as? String }
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
