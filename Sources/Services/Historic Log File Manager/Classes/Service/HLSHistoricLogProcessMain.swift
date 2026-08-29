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

@preconcurrency import CoreData
import Foundation
import os

@objc(HLSHistoricLogProcessMain)
final class HistoricLogProcessMain: NSObject, HistoricLogServerProtocol, @unchecked Sendable {
	private final class CallbackBox<Callback>: @unchecked Sendable {
		let callback: Callback

		init(_ callback: Callback) {
			self.callback = callback
		}
	}

	private enum UniqueIdentifierFetchType {
		case before
		case after
	}

	private enum Database {
		static let filenameKey = "TVCLogControllerHistoricLogFileSavePath_v3"
		static let modelName = "HistoricLogFileStorageModel"
		static let entityName = "LogLine2"
	}

	private static let logger = Logger(
		subsystem: "com.vakesz.glasstual.ScrollbackHistoryManager",
		category: "Storage"
	)

	private var serviceConnection: NSXPCConnection?
	private var managedObjectContext: NSManagedObjectContext?
	private var managedObjectModel: NSManagedObjectModel?
	private var persistentStoreCoordinator: NSPersistentStoreCoordinator?
	private var databaseURL: URL?
	private var databaseDirectoryURL: URL?
	private var contextObjects: [String: HistoricLogViewContext] = [:]
	private let contextLock = NSRecursiveLock()
	private var maximumLineCountStorage: UInt = 100

	/** Written from the XPC delivery thread and read from Core Data queues. */
	private var maximumLineCount: UInt {
		get { contextLock.withLock { maximumLineCountStorage } }
		set { contextLock.withLock { maximumLineCountStorage = newValue } }
	}

	private let saveQueue = DispatchQueue(label: "HLSHistoricLogProcessMain.saveQueue")
	private var saveTimer: DispatchSourceTimer?
	private var connectionIsInvalidated = false

	@objc(initWithConnection:)
	init(connection: NSXPCConnection) {
		serviceConnection = connection
		super.init()
	}

	private func resetDatabaseFilename() -> String {
		let filename = "logControllerHistoricLog_\(UUID().uuidString).sqlite"
		TextualUserDefaults.shared().set(filename, forKey: Database.filenameKey)
		return filename
	}

	private func databaseSaveFilename() -> String {
		TextualUserDefaults.shared().string(forKey: Database.filenameKey) ?? resetDatabaseFilename()
	}

	private func setDatabasePath(in directory: String) {
		databaseDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
		setDatabasePath()
	}

	private func setDatabasePath() {
		databaseURL = databaseDirectoryURL?.appendingPathComponent(databaseSaveFilename(), isDirectory: false)
	}

	private func resetDatabasePath() {
		_ = resetDatabaseFilename()
		setDatabasePath()
	}

	func openDatabase(
		inDirectory databaseDirectory: String,
		withCompletionBlock completionBlock: (@Sendable (Bool) -> Void)?
	) {
		setDatabasePath(in: databaseDirectory)
		guard let databaseURL else {
			completionBlock?(false)
			return
		}

		Self.logger.info("Opening database at path: \(databaseURL.path, privacy: .public)")
		contextLock.lock()
		let success = createBaseModel()
		contextLock.unlock()
		completionBlock?(success)

		guard success else { return }
		saveQueue.async { [weak self] in
			guard let self, !connectionIsInvalidated else { return }
			rescheduleSave()
		}
	}

	func setMaximumLineCount(_ maximumLineCount: UInt) {
		/* This service process is shared by every view; a bad value must not abort it. */
		guard maximumLineCount > 0 else {
			Self.logger.error("Ignoring a request to set the maximum line count to zero")
			return
		}

		self.maximumLineCount = maximumLineCount
	}

	private func fetchRequest(
		forView viewIdentifier: String,
		ascending: Bool = true,
		fetchLimit: UInt = 0,
		lowestEntryIdentifier: UInt = 0,
		highestEntryIdentifier: UInt = UInt(Int.max),
		limitToDate: Date? = nil,
		resultType: NSFetchRequestResultType
	) -> NSFetchRequest<NSManagedObject>? {
		guard let managedObjectModel else { return nil }

		let variables: [String: Any] = [
			"view_id": viewIdentifier,
			"entry_id_lowest": NSNumber(value: lowestEntryIdentifier),
			"entry_id_highest": NSNumber(value: highestEntryIdentifier),
			"creation_date": NSNumber(value: (limitToDate ?? .distantFuture).timeIntervalSince1970),
		]
		guard let request = managedObjectModel.fetchRequestFromTemplate(
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

	func forgetView(_ viewIdentifier: String) {
		Self.logger.debug("Forgetting view: \(viewIdentifier, privacy: .public)")
		guard let viewContext = context(forView: viewIdentifier) else { return }

		viewContext.performAndWait {
			cancelResize(in: viewContext)
			if let request = fetchRequest(forView: viewIdentifier, resultType: .managedObjectResultType) {
				_ = deleteData(in: viewContext, fetchRequest: request, performOnQueue: false)
			}
			viewContext.reset()
		}

		contextLock.withLock {
			_ = contextObjects.removeValue(forKey: viewIdentifier)
		}
	}

	func resetData(forView viewIdentifier: String) {
		Self.logger.debug("Resetting the contents of view: \(viewIdentifier, privacy: .public)")
		guard let viewContext = context(forView: viewIdentifier) else { return }

		viewContext.performAndWait {
			cancelResize(in: viewContext)
			if let request = fetchRequest(forView: viewIdentifier, resultType: .managedObjectResultType) {
				_ = deleteData(in: viewContext, fetchRequest: request, performOnQueue: false)
			}
			viewContext.reset()
		}
	}

	func fetchEntries(
		forView viewIdentifier: String,
		beforeUniqueIdentifier uniqueIdentifier: String,
		fetchLimit: UInt,
		limitTo limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	) {
		fetchEntries(
			forView: viewIdentifier,
			uniqueIdentifier: uniqueIdentifier,
			fetchType: .before,
			fetchLimit: fetchLimit,
			limitToDate: limitToDate,
			completionBlock: completionBlock
		)
	}

	func fetchEntries(
		forView viewIdentifier: String,
		afterUniqueIdentifier uniqueIdentifier: String,
		fetchLimit: UInt,
		limitTo limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	) {
		fetchEntries(
			forView: viewIdentifier,
			uniqueIdentifier: uniqueIdentifier,
			fetchType: .after,
			fetchLimit: fetchLimit,
			limitToDate: limitToDate,
			completionBlock: completionBlock
		)
	}

	func fetchEntries(
		forView viewIdentifier: String,
		withUniqueIdentifier uniqueIdentifier: String,
		beforeFetchLimit fetchLimitBefore: UInt,
		afterFetchLimit fetchLimitAfter: UInt,
		limitTo limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	) {
		guard let viewContext = context(forView: viewIdentifier) else {
			completionBlock([])
			return
		}

		let entries: [LogLineXPC] = viewContext.performAndWait {
			let entryIdentifier = identifier(
				in: viewContext,
				forUniqueIdentifier: uniqueIdentifier,
				performOnQueue: false
			)
			guard entryIdentifier != UInt.max else {
				return []
			}

			let lowest = entryIdentifier > fetchLimitBefore ? entryIdentifier - fetchLimitBefore : 0
			let highest = saturatedAdd(entryIdentifier, fetchLimitAfter)
			return fetchEntries(
				in: viewContext,
				ascending: true,
				/* Unbounded here would put an entire view into one XPC reply. */
				fetchLimit: maximumLineCount,
				lowestEntryIdentifier: lowest,
				highestEntryIdentifier: highest,
				limitToDate: limitToDate
			)
		}
		completionBlock(entries)
	}

	func fetchEntries(
		forView viewIdentifier: String,
		afterUniqueIdentifier uniqueIdentifierAfter: String,
		beforeUniqueIdentifier uniqueIdentifierBefore: String,
		fetchLimit: UInt,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	) {
		guard let viewContext = context(forView: viewIdentifier) else {
			completionBlock([])
			return
		}

		let entries: [LogLineXPC] = viewContext.performAndWait {
			let first = identifier(in: viewContext, forUniqueIdentifier: uniqueIdentifierAfter, performOnQueue: false)
			let second = identifier(in: viewContext, forUniqueIdentifier: uniqueIdentifierBefore, performOnQueue: false)
			guard first != UInt.max, second != UInt.max else {
				return []
			}

			return fetchEntries(
				in: viewContext,
				ascending: true,
				fetchLimit: fetchLimit,
				lowestEntryIdentifier: saturatedAdd(first, 1),
				highestEntryIdentifier: second > 0 ? second - 1 : 0,
				limitToDate: nil
			)
		}
		completionBlock(entries)
	}

	private func fetchEntries(
		forView viewIdentifier: String,
		uniqueIdentifier: String,
		fetchType: UniqueIdentifierFetchType,
		fetchLimit: UInt,
		limitToDate: Date?,
		completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	) {
		guard fetchLimit > 0 else {
			Self.logger.error("Ignoring a fetch request with a zero fetch limit")
			completionBlock([])
			return
		}

		guard let viewContext = context(forView: viewIdentifier) else {
			completionBlock([])
			return
		}

		let entries: [LogLineXPC] = viewContext.performAndWait {
			let entryIdentifier = identifier(
				in: viewContext,
				forUniqueIdentifier: uniqueIdentifier,
				performOnQueue: false
			)
			guard entryIdentifier != UInt.max else {
				return []
			}

			let bounds: (lowest: UInt, highest: UInt) = switch fetchType {
			case .before:
				(
					entryIdentifier > fetchLimit ? entryIdentifier - fetchLimit : 0,
					entryIdentifier > 0 ? entryIdentifier - 1 : 0
				)
			case .after:
				(saturatedAdd(entryIdentifier, 1), saturatedAdd(entryIdentifier, fetchLimit))
			}

			return fetchEntries(
				in: viewContext,
				ascending: true,
				fetchLimit: fetchLimit,
				lowestEntryIdentifier: bounds.lowest,
				highestEntryIdentifier: bounds.highest,
				limitToDate: limitToDate
			)
		}
		completionBlock(entries)
	}

	func fetchEntries(
		forView viewIdentifier: String,
		ascending: Bool,
		fetchLimit: UInt,
		limitTo limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	) {
		guard let viewContext = context(forView: viewIdentifier) else {
			completionBlock([])
			return
		}
		let entries: [LogLineXPC] = viewContext.performAndWait {
			fetchEntries(
				in: viewContext,
				ascending: ascending,
				fetchLimit: fetchLimit,
				limitToDate: limitToDate
			)
		}
		completionBlock(entries)
	}

	private func fetchEntries(
		in viewContext: HistoricLogViewContext,
		ascending: Bool,
		fetchLimit: UInt,
		lowestEntryIdentifier: UInt = 0,
		highestEntryIdentifier: UInt = UInt(Int.max),
		limitToDate: Date?
	) -> [LogLineXPC] {
		guard let request = fetchRequest(
			forView: viewContext.viewIdentifier,
			ascending: ascending,
			fetchLimit: fetchLimit,
			lowestEntryIdentifier: lowestEntryIdentifier,
			highestEntryIdentifier: highestEntryIdentifier,
			limitToDate: limitToDate,
			resultType: .managedObjectResultType
		) else { return [] }

		do {
			let objects = try viewContext.fetch(request)
			Self.logger
				.debug("\(objects.count) results fetched for view \(viewContext.viewIdentifier, privacy: .public)")
			return objects.compactMap { LogLineXPC(managedObject: $0) }
		} catch {
			Self.logger.error("Error occurred fetching objects: \(error.localizedDescription, privacy: .public)")
			return []
		}
	}

	func writeLogLine(_ logLine: LogLineXPC) {
		let viewIdentifier = logLine.viewIdentifier
		let data = logLine.data
		let uniqueIdentifier = logLine.uniqueIdentifier
		let sessionIdentifier = logLine.sessionIdentifier
		guard let viewContext = context(forView: viewIdentifier) else { return }
		viewContext.performAndWait {
			guard let entity = NSEntityDescription.entity(forEntityName: Database.entityName, in: viewContext) else {
				Self.logger.error("The LogLine2 entity is missing")
				return
			}

			let entry = NSManagedObject(entity: entity, insertInto: viewContext)
			entry.setValue(NSNumber(value: incrementNewestIdentifier(in: viewContext)), forKey: "entryIdentifier")
			entry.setValue(NSNumber(value: Date().timeIntervalSince1970), forKey: "entryCreationDate")
			entry.setValue(viewIdentifier, forKey: "logLineViewIdentifier")
			entry.setValue(data, forKey: "logLineData")
			entry.setValue(uniqueIdentifier, forKey: "logLineUniqueIdentifier")
			entry.setValue(NSNumber(value: sessionIdentifier), forKey: "sessionIdentifier")
			scheduleResize(in: viewContext)
		}
	}

	private func createBaseModel(recursionDepth: Int = 0) -> Bool {
		guard
			let modelURL = Bundle.main.url(forResource: Database.modelName, withExtension: "momd"),
			let model = NSManagedObjectModel(contentsOf: modelURL),
			let databaseURL
		else {
			Self.logger.error("Historic log model or database URL is missing")
			return false
		}

		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
		let options: [AnyHashable: Any] = [
			NSMigratePersistentStoresAutomaticallyOption: true,
			NSInferMappingModelAutomaticallyOption: true,
			NSSQLitePragmasOption: ["synchronous": "NORMAL", "journal_mode": "WAL"],
		]

		do {
			_ = try coordinator.addPersistentStore(type: .sqlite, at: databaseURL, options: options)
		} catch {
			Self.logger.error("Error creating persistent store: \(error.localizedDescription, privacy: .public)")
			guard recursionDepth == 0 else { return false }
			Self.logger.info("Attempting to create a new persistent store")
			resetDatabasePath()
			return createBaseModel(recursionDepth: 1)
		}

		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		context.persistentStoreCoordinator = coordinator
		context.retainsRegisteredObjects = true
		context.undoManager = nil
		managedObjectContext = context
		managedObjectModel = model
		persistentStoreCoordinator = coordinator
		return true
	}

	private func cancelScheduledSave() {
		saveTimer?.cancel()
		saveTimer = nil
	}

	private func rescheduleSave() {
		cancelScheduledSave()
		let timer = DispatchSource.makeTimerSource(queue: .main)
		timer.schedule(deadline: .now() + 120, repeating: 120)
		timer.setEventHandler { [weak self] in self?.saveData(completionBlock: nil) }
		timer.resume()
		saveTimer = timer
	}

	private func quickSave(_ context: NSManagedObjectContext) {
		guard context.hasChanges else { return }
		do {
			try context.save()
		} catch {
			Self.logger.error("Failed to perform save: \(error.localizedDescription, privacy: .public)")
		}
		context.reset()
	}

	private func saveAllContexts(cancellingResize: Bool) {
		guard let context = managedObjectContext else { return }
		Self.logger.debug("Performing save")
		let viewContexts = contextLock.withLock { Array(contextObjects.values) }

		for viewContext in viewContexts {
			viewContext.performAndWait {
				if cancellingResize {
					cancelResize(in: viewContext)
				}
				quickSave(viewContext)
			}
		}
		context.performAndWait { quickSave(context) }
	}

	func saveData(completionBlock: (@Sendable () -> Void)?) {
		let completion = CallbackBox(completionBlock)
		saveQueue.async { [weak self] in
			/* The reply block is an XPC reply; it has to be invoked on every path. */
			defer { completion.callback?() }
			guard let self else { return }
			if !connectionIsInvalidated {
				rescheduleSave()
			}
			saveAllContexts(cancellingResize: false)
		}
	}

	@objc func connectionInvalidated() {
		Self.logger.debug("Connection invalidated")
		saveQueue.sync {
			connectionIsInvalidated = true
			cancelScheduledSave()
			saveAllContexts(cancellingResize: true)
		}
		serviceConnection = nil
	}
}

extension HistoricLogProcessMain {
	private func cancelResize(in viewContext: HistoricLogViewContext) {
		(viewContext.resizeTimer as? DispatchSourceTimer)?.cancel()
		viewContext.resizeTimer = nil
	}

	private func scheduleResize(in viewContext: HistoricLogViewContext) {
		guard viewContext.resizeTimer == nil, viewContext.totalLineCount >= maximumLineCount else { return }
		let viewIdentifier = viewContext.viewIdentifier
		let interval = TimeInterval(UInt32.random(in: 0 ..< 1800))
		let timer = DispatchSource.makeTimerSource(queue: .main)
		timer.schedule(deadline: .now() + interval)
		timer.setEventHandler { [weak self] in self?.resizeView(viewIdentifier) }
		timer.resume()
		viewContext.resizeTimer = timer as AnyObject
		Self.logger.debug("Scheduled to resize \(viewIdentifier, privacy: .public) in \(interval) seconds")
	}

	private func resizeView(_ viewIdentifier: String) {
		guard let viewContext = context(forView: viewIdentifier) else { return }
		viewContext.perform { [weak self] in self?.resize(viewContext) }
	}

	private func resize(_ viewContext: HistoricLogViewContext) {
		Self.logger.debug("Resizing view \(viewContext.viewIdentifier, privacy: .public)")
		viewContext.resizeTimer = nil
		let lowest = viewContext.newestIdentifier > maximumLineCount
			? viewContext.newestIdentifier - maximumLineCount
			: 0
		guard
			let request = managedObjectModel?.fetchRequestFromTemplate(
				withName: "Truncate",
				substitutionVariables: [
					"view_id": viewContext.viewIdentifier,
					"entry_id_lowest": NSNumber(value: lowest),
				]
			) as? NSFetchRequest<NSManagedObject>
		else { return }

		request.includesPendingChanges = true
		request.includesPropertyValues = true
		request.returnsObjectsAsFaults = false
		let deleted = deleteData(in: viewContext, fetchRequest: request, performOnQueue: false)
		viewContext.totalLineCount = deleted > viewContext.totalLineCount ? 0 : viewContext.totalLineCount - deleted
	}

	private func deleteData(
		in viewContext: HistoricLogViewContext,
		fetchRequest: NSFetchRequest<NSManagedObject>,
		performOnQueue: Bool
	) -> UInt {
		let deleted = performOnQueue
			? viewContext.performAndWait { deleteDataUsingBatch(fetchRequest, in: viewContext) }
			: deleteDataUsingBatch(fetchRequest, in: viewContext)
		Self.logger.debug("Deleted \(deleted) rows in \(viewContext.viewIdentifier, privacy: .public)")
		return deleted
	}

	private func deleteDataUsingBatch(
		_ fetchRequest: NSFetchRequest<NSManagedObject>,
		in viewContext: HistoricLogViewContext
	) -> UInt {
		guard let parentContext = viewContext.parent else { return 0 }
		quickSave(viewContext)
		parentContext.performAndWait { quickSave(parentContext) }

		guard let identifierRequest = fetchRequest.copy() as? NSFetchRequest<NSDictionary> else {
			assertionFailure("Unable to copy the historic-log identifier fetch request")
			return 0
		}

		identifierRequest.resultType = .dictionaryResultType
		identifierRequest.propertiesToFetch = ["logLineUniqueIdentifier"]
		identifierRequest.includesPendingChanges = false
		identifierRequest.returnsObjectsAsFaults = false
		identifierRequest.sortDescriptors = nil

		let identifierRows: [NSDictionary]
		do {
			identifierRows = try viewContext.fetch(identifierRequest)
		} catch {
			Self.logger.error("Error occurred fetching identifiers: \(error.localizedDescription, privacy: .public)")
			return 0
		}
		let uniqueIdentifiers = identifierRows.compactMap { $0["logLineUniqueIdentifier"] as? String }
		guard !uniqueIdentifiers.isEmpty else { return 0 }

		guard let deleteFetchRequest = fetchRequest.copy() as? NSFetchRequest<NSFetchRequestResult> else {
			assertionFailure("Unable to copy the historic-log deletion fetch request")
			return 0
		}

		deleteFetchRequest.resultType = .managedObjectResultType
		deleteFetchRequest.includesPendingChanges = false
		deleteFetchRequest.sortDescriptors = nil
		let batchRequest = NSBatchDeleteRequest(fetchRequest: deleteFetchRequest)
		batchRequest.resultType = .resultTypeObjectIDs

		let execution: Result<NSBatchDeleteResult, Error> = parentContext.performAndWait {
			Result {
				guard let result = try parentContext.execute(batchRequest) as? NSBatchDeleteResult else {
					throw CocoaError(.coderInvalidValue)
				}
				return result
			}
		}
		guard case let .success(result) = execution else {
			if case let .failure(error) = execution {
				Self.logger.error("Failed to perform batch delete: \(error.localizedDescription, privacy: .public)")
			}
			return 0
		}
		guard let objectIDs = result.result as? [NSManagedObjectID], !objectIDs.isEmpty else { return 0 }

		NSManagedObjectContext.mergeChanges(
			fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
			into: [parentContext, viewContext]
		)
		remoteObjectProxy()?.willDeleteUniqueIdentifiers(uniqueIdentifiers, inView: viewContext.viewIdentifier)
		return UInt(objectIDs.count)
	}

	private func context(forView viewIdentifier: String) -> HistoricLogViewContext? {
		contextLock.lock()
		defer { contextLock.unlock() }
		if let cached = contextObjects[viewIdentifier] {
			return cached
		}
		guard let parentContext = managedObjectContext else {
			Self.logger
				.error("Requested context for \(viewIdentifier, privacy: .public) before the database was opened")
			return nil
		}

		let context = HistoricLogViewContext(concurrencyType: .privateQueueConcurrencyType)
		context.parent = parentContext
		context.retainsRegisteredObjects = true
		context.undoManager = nil
		context.viewIdentifier = viewIdentifier
		context.totalLineCount = lineCount(in: context, performOnQueue: true)
		context.newestIdentifier = newestIdentifier(in: context, performOnQueue: true)
		Self.logger.debug(
			"Context created for \(viewIdentifier, privacy: .public), line count: \(context.totalLineCount), newest identifier: \(context.newestIdentifier)"
		)
		contextObjects[viewIdentifier] = context
		return context
	}

	private func incrementNewestIdentifier(in viewContext: HistoricLogViewContext) -> UInt {
		viewContext.totalLineCount = saturatedAdd(viewContext.totalLineCount, 1)
		viewContext.newestIdentifier = saturatedAdd(viewContext.newestIdentifier, 1)
		return viewContext.newestIdentifier
	}

	private func newestIdentifier(in viewContext: HistoricLogViewContext, performOnQueue: Bool) -> UInt {
		let work: @Sendable () -> UInt = {
			guard let request = self.fetchRequest(
				forView: viewContext.viewIdentifier,
				ascending: false,
				fetchLimit: 1,
				resultType: .managedObjectResultType
			) else { return 0 }
			do {
				return try (viewContext.fetch(request).first?.value(forKey: "entryIdentifier") as? NSNumber)?
					.uintValue ?? 0
			} catch {
				Self.logger.error("Failed to fetch newest identifier: \(error.localizedDescription, privacy: .public)")
				return 0
			}
		}
		return performOnQueue ? viewContext.performAndWait(work) : work()
	}

	private func lineCount(in viewContext: HistoricLogViewContext, performOnQueue: Bool) -> UInt {
		let work: @Sendable () -> UInt = {
			guard let request = self.fetchRequest(
				forView: viewContext.viewIdentifier,
				resultType: .countResultType
			) else { return 0 }
			do {
				return try UInt(viewContext.count(for: request))
			} catch {
				Self.logger.error("Failed to count log lines: \(error.localizedDescription, privacy: .public)")
				return 0
			}
		}
		return performOnQueue ? viewContext.performAndWait(work) : work()
	}

	private func identifier(
		in viewContext: HistoricLogViewContext,
		forUniqueIdentifier uniqueIdentifier: String,
		performOnQueue: Bool
	) -> UInt {
		let work: @Sendable () -> UInt = {
			guard
				let request = self.managedObjectModel?.fetchRequestFromTemplate(
					withName: "UniqueIdToEntryId",
					substitutionVariables: [
						"view_id": viewContext.viewIdentifier,
						"unique_id": uniqueIdentifier,
					]
				) as? NSFetchRequest<NSManagedObject>
			else { return UInt.max }
			request.includesPendingChanges = true
			request.includesPropertyValues = true
			request.returnsObjectsAsFaults = false
			do {
				return try (viewContext.fetch(request).first?.value(forKey: "entryIdentifier") as? NSNumber)?
					.uintValue ?? UInt.max
			} catch {
				Self.logger
					.error("Failed to resolve unique identifier: \(error.localizedDescription, privacy: .public)")
				return UInt.max
			}
		}
		return performOnQueue ? viewContext.performAndWait(work) : work()
	}

	private func remoteObjectProxy() -> HistoricLogClientProtocol? {
		serviceConnection?.remoteObjectProxy as? HistoricLogClientProtocol
	}

	private func saturatedAdd(_ lhs: UInt, _ rhs: UInt) -> UInt {
		let (result, overflow) = lhs.addingReportingOverflow(rhs)
		return overflow ? UInt.max : result
	}
}
