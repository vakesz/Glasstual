import CoreData
import Foundation
@testable import Glasstual
import Testing

/// The database name for one harness. `HistoricLogStore` only writes the slot
/// when it finds it empty and has to name the file itself, so filling it in up
/// front makes the store's reads answerable from a `let` instead of a box the
/// store's isolation domain and the test would have to share. Each harness gets
/// its own temporary directory, so a name per store is all the tests need.
private nonisolated struct ScratchFilenameStore: HistoricLogFilenameStoring { // nonisolated: value
	let filename = "logControllerHistoricLog_\(UUID().uuidString).sqlite"

	var databaseFilename: String? {
		get { filename }
		nonmutating set {
			Issue.record("The store renamed its database to \(newValue ?? "nothing").")
		}
	}
}

private actor DeletionRecorder {
	private(set) var identifiers: [String] = []

	func record(_ newIdentifiers: [String]) {
		identifiers.append(contentsOf: newIdentifiers)
	}
}

/// Drives the real in-process store while keeping temporary-file cleanup and
/// observation behind one actor.
private actor HistoricLogStoreHarness {
	private let store: HistoricLogStore
	private let recorder: DeletionRecorder
	private let filenameStore: ScratchFilenameStore

	let directory: URL

	init() throws {
		directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("historic-log-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		let recorder = DeletionRecorder()
		self.recorder = recorder
		let filenameStore = ScratchFilenameStore()
		self.filenameStore = filenameStore
		store = HistoricLogStore(filenameStore: filenameStore, deletionHandler: { identifiers, _ in
			await recorder.record(identifiers)
		})
	}

	func shutdown() async {
		await store.close()
		try? FileManager.default.removeItem(at: directory)
	}

	var deletedIdentifiers: [String] {
		get async { await recorder.identifiers }
	}

	func openDatabase() async -> Bool {
		await store.setMaximumLineCount(10000)
		return await store.openDatabase(inDirectory: directory.path).isOpen
	}

	func close() async {
		await store.close()
	}

	func seed(_ rows: [(identifier: UInt, entry: HistoricLogEntry)]) async throws {
		let context = try HistoricLogDatabase.makeStack(at: directory.appendingPathComponent(filenameStore.filename))
		try await context.perform {
			for row in rows {
				HistoricLogDatabase.insert(row.entry, in: context, entryIdentifier: row.identifier)
			}
			try context.save()
		}
	}

	func persistedRows(inView view: String) async throws -> [(identifier: UInt, entry: HistoricLogEntry)] {
		let context = try HistoricLogDatabase.makeStack(at: directory.appendingPathComponent(filenameStore.filename))
		return try await context.perform {
			let request = NSFetchRequest<NSManagedObject>(entityName: HistoricLogDatabase.entityName)
			request.predicate = NSPredicate(
				format: "%K == %@", HistoricLogAttribute.logLineViewIdentifier.rawValue, view
			)
			request.sortDescriptors = [
				NSSortDescriptor(key: HistoricLogAttribute.entryIdentifier.rawValue, ascending: true),
				NSSortDescriptor(key: HistoricLogAttribute.logLineUniqueIdentifier.rawValue, ascending: true),
			]
			return try context.fetch(request).map { object in
				let identifier = try #require(object
					.value(forKey: HistoricLogAttribute.entryIdentifier.rawValue) as? NSNumber)
				let entry = try #require(HistoricLogEntry(managedObject: object))
				return (identifier.uintValue, entry)
			}
		}
	}

	func write(_ entry: HistoricLogEntry) async {
		await store.writeLogLine(entry)
	}

	func fetch(
		inView view: String,
		ascending: Bool = true,
		before: String? = nil,
		limit: UInt = 100,
		limitToDate: Date? = nil
	) async -> [HistoricLogEntry] {
		if let before {
			return await store.fetchEntries(forView: view, before: before, fetchLimit: limit, limitToDate: limitToDate)
		}
		return await store.fetchEntries(
			forView: view,
			ascending: ascending,
			fetchLimit: limit,
			limitToDate: limitToDate
		)
	}

	func fetchOutcome(_ request: HistoricLogFetchRequest) async -> HistoricLogFetchOutcome {
		await store.fetchOutcome(request)
	}

	func write(_ index: Int, inView view: String) async {
		await store.writeLogLine(HistoricLogEntry(
			logLineData: Data("line \(index)".utf8),
			uniqueIdentifier: "line-\(index)",
			viewIdentifier: view,
			sessionIdentifier: 1,
			creationDate: Date().timeIntervalSince1970
		))
	}

	func save() async {
		await store.saveData()
	}

	func forgetView(_ view: String) async {
		await store.forgetView(view)
	}

	func lineCount(inView view: String, limit: UInt = 100) async -> Int {
		await store.fetchEntries(
			forView: view,
			ascending: true,
			fetchLimit: limit,
			limitToDate: nil
		).count
	}
}

@Suite("Historic log store", .serialized)
struct HistoricLogStoreConcurrencyTests {
	@Test("The real store distinguishes an unavailable database, missing cursor and exhausted page")
	func typedStoreFetchDistinguishesOutcomes() async throws {
		let harness = try HistoricLogStoreHarness()
		let newest = HistoricLogFetchRequest(viewIdentifier: "history",
		                                     kind: .newest(ascending: true, fetchLimit: 10, limitToDate: nil))
		switch await harness.fetchOutcome(newest) {
		case .failed(.unavailable): break
		default: Issue.record("Unopened history was reported as exhaustion")
		}
		#expect(await harness.openDatabase())
		switch await harness.fetchOutcome(newest) {
		case let .page(entries): #expect(entries.isEmpty)
		default: Issue.record("An empty store did not return a successful page")
		}
		let anchor = entry("anchor", date: 100)
		await harness.write(anchor)
		let older = HistoricLogFetchRequest(
			viewIdentifier: "history",
			kind: .before(uniqueIdentifier: anchor.uniqueIdentifier, fetchLimit: 10, limitToDate: nil)
		)
		switch await harness.fetchOutcome(older) {
		case let .page(entries): #expect(entries.isEmpty)
		default: Issue.record("A valid oldest cursor did not prove exhaustion")
		}
		await harness.forgetView("history")
		switch await harness.fetchOutcome(older) {
		case .failed(.missingCursor): break
		default: Issue.record("A forgotten cursor was reported as exhaustion")
		}
		await harness.close()
		switch await harness.fetchOutcome(newest) {
		case .failed(.unavailable): break
		default: Issue.record("Closed history was reported as exhaustion")
		}
		await harness.shutdown()
	}

	private func entry(_ label: String, date: TimeInterval, view: String = "history") -> HistoricLogEntry {
		var line = LogLine()
		line.receivedAt = Date(timeIntervalSince1970: date)
		line.messageBody = label
		return line.historicEntry(forView: view)
	}

	@Test("Reopening allocates above the greatest insertion ID, not the newest timestamp")
	func reopeningAppendsAboveMaximumIdentifier() async throws {
		let harness = try HistoricLogStoreHarness()
		#expect(await harness.openDatabase())
		let newest = entry("newest", date: 300)
		let oldest = entry("oldest", date: 100)
		await harness.write(newest)
		await harness.write(oldest)
		await harness.close()

		#expect(await harness.openDatabase())
		let appended = entry("middle", date: 200)
		await harness.write(appended)
		await harness.close()

		let rows = try await harness.persistedRows(inView: "history")
		#expect(rows.map(\.identifier) == [1, 2, 3])
		#expect(rows.map(\.entry.uniqueIdentifier) == [newest, oldest, appended].map(\.uniqueIdentifier))
		#expect(rows.map(\.entry.data) == [newest, oldest, appended].map(\.data))
		#expect(rows.map(\.entry.creationDate) == [300, 100, 200])
		await harness.shutdown()
	}

	@Test("Tied timestamps paginate chronologically in pending and gapped persisted rows", arguments: [false, true])
	func chronologicalKeysetPagesVisitEachRowOnce(persisted: Bool) async throws {
		let harness = try HistoricLogStoreHarness()
		let dates: [TimeInterval] = [300, 100, 200, 200, 100, 300, 200]
		let entries = dates.enumerated().map { entry("line \($0.offset)", date: $0.element) }
		if persisted {
			try await harness.seed(entries.enumerated().map { (UInt($0.offset * 10 + 1), $0.element) })
		}
		#expect(await harness.openDatabase())
		if persisted == false {
			for entry in entries {
				await harness.write(entry)
			}
		}

		let expected = [1, 4, 2, 3, 6, 0, 5].map { entries[$0].uniqueIdentifier }
		let ascending = await harness.fetch(inView: "history", limit: 100)
		#expect(ascending.map(\.uniqueIdentifier) == expected)
		let descending = await harness.fetch(inView: "history", ascending: false, limit: 100)
		#expect(descending.map(\.uniqueIdentifier) == Array(expected.reversed()))
		var page = await Array(harness.fetch(inView: "history", ascending: false, limit: 2).reversed())
		var visited = page.map(\.uniqueIdentifier)
		for _ in 0 ..< entries.count {
			guard let anchor = page.first?.uniqueIdentifier else { break }
			page = await harness.fetch(inView: "history", before: anchor, limit: 2)
			visited.insert(contentsOf: page.map(\.uniqueIdentifier), at: 0)
		}
		#expect(page.isEmpty)
		#expect(visited == expected)
		#expect(Set(visited).count == entries.count)

		let limited = await harness.fetch(
			inView: "history", before: entries[5].uniqueIdentifier, limit: 2,
			limitToDate: Date(timeIntervalSince1970: 200)
		)
		#expect(limited.map(\.uniqueIdentifier) == [entries[1], entries[4]].map(\.uniqueIdentifier))
		#expect(await harness.fetch(inView: "history", before: entries[1].uniqueIdentifier).isEmpty)
		#expect(await harness.fetch(inView: "history", before: "missing").isEmpty)
		#expect(await harness.fetch(inView: "history", before: entries[5].uniqueIdentifier, limit: 0).isEmpty)
		await harness.shutdown()
	}

	@Test("Persisted duplicate insertion IDs stay intact and use line identity to break ties")
	func duplicateInsertionIdentifiersRemainUnchangedAcrossReopens() async throws {
		let harness = try HistoricLogStoreHarness()
		let entries = (0 ..< 4).map { entry("duplicate \($0)", date: 200) }
		try await harness.seed(entries.map { (7, $0) })
		let original = try await harness.persistedRows(inView: "history")
		let expected = original.map(\.entry.uniqueIdentifier)

		for _ in 0 ..< 2 {
			#expect(await harness.openDatabase())
			var page = await harness.fetch(inView: "history", ascending: false, limit: 1)
			var visited = page.map(\.uniqueIdentifier)
			for _ in 0 ..< entries.count {
				guard let anchor = page.first?.uniqueIdentifier else { break }
				page = await harness.fetch(inView: "history", before: anchor, limit: 1)
				visited.insert(contentsOf: page.map(\.uniqueIdentifier), at: 0)
			}
			#expect(page.isEmpty)
			#expect(visited == expected)
			await harness.close()
			let stored = try await harness.persistedRows(inView: "history")
			#expect(stored.map(\.identifier) == original.map(\.identifier))
			#expect(stored.map(\.entry.uniqueIdentifier) == expected)
			#expect(stored.map(\.entry.data) == original.map(\.entry.data))
			#expect(stored.map(\.entry.creationDate) == original.map(\.entry.creationDate))
			#expect(stored.map(\.entry.sessionIdentifier) == original.map(\.entry.sessionIdentifier))
		}

		#expect(await harness.openDatabase())
		await harness.write(entry("appended", date: 100))
		await harness.close()
		#expect(try await harness.persistedRows(inView: "history").map(\.identifier) == [7, 7, 7, 7, 8])
		await harness.shutdown()
	}

	@Test("Concurrent first writes share initialized counts on empty and persisted views")
	func concurrentFirstWritesAllocateUniqueIdentifiers() async throws {
		let harness = try HistoricLogStoreHarness()
		let seed = entry("seed", date: 300, view: "persisted")
		try await harness.seed([(50, seed)])
		#expect(await harness.openDatabase())
		let entries = ["empty", "persisted"].flatMap { view in
			(0 ..< 40).map { entry("\(view)-\($0)", date: 200, view: view) }
		}
		await withTaskGroup(of: Void.self) { group in
			for entry in entries {
				group.addTask { await harness.write(entry) }
			}
		}
		await harness.close()

		let empty = try await harness.persistedRows(inView: "empty")
		let persisted = try await harness.persistedRows(inView: "persisted")
		#expect(empty.map(\.identifier) == Array(UInt(1) ... 40))
		#expect(persisted.map(\.identifier) == Array(UInt(50) ... 90))
		#expect(Set(empty.map(\.entry.uniqueIdentifier) + persisted.map(\.entry.uniqueIdentifier))
			== Set(entries.map(\.uniqueIdentifier) + [seed.uniqueIdentifier]))
		await harness.shutdown()
	}

	@Test("Maximum allocation includes rows beyond the display cutoff and stops at Int64 max")
	func allocationIncludesHiddenRowsAndRejectsExhaustion() async throws {
		let harness = try HistoricLogStoreHarness()
		let future = entry("future", date: Date.distantFuture.timeIntervalSince1970 + 1)
		let exhausted = entry("exhausted", date: 100, view: "exhausted")
		try await harness.seed([(90, future), (UInt(Int64.max), exhausted)])
		#expect(await harness.openDatabase())
		await harness.write(entry("append", date: 100))
		await harness.write(entry("cannot allocate", date: 200, view: "exhausted"))
		await harness.close()
		#expect(try await harness.persistedRows(inView: "history").map(\.identifier) == [90, 91])
		let rows = try await harness.persistedRows(inView: "exhausted")
		#expect(rows.map(\.identifier) == [UInt(Int64.max)])
		#expect(rows.map(\.entry.data) == [exhausted.data])
		await harness.shutdown()
	}

	@Test("An ambiguous persisted line cursor leaves both rows intact")
	func duplicateLineIdentifiersDoNotChooseAnArbitraryAnchor() async throws {
		let harness = try HistoricLogStoreHarness()
		let line = entry("same line", date: 200)
		try await harness.seed([(1, line), (2, line)])
		#expect(await harness.openDatabase())
		#expect(await harness.fetch(inView: "history").count == 2)
		#expect(await harness.fetch(inView: "history", before: line.uniqueIdentifier).isEmpty)
		await harness.close()
		let rows = try await harness.persistedRows(inView: "history")
		#expect(rows.map(\.identifier) == [1, 2])
		#expect(rows.map(\.entry.data) == [line.data, line.data])
		#expect(rows.map(\.entry.uniqueIdentifier) == [line.uniqueIdentifier, line.uniqueIdentifier])
		await harness.shutdown()
	}

	@Test(
		"Incompatible SQLite stores are preserved even when a destructive mapping is inferable",
		arguments: [false, true]
	)
	func failedOpenPreservesTheSelectedDatabase(inferable: Bool) async throws {
		let harness = try HistoricLogStoreHarness()
		let filenameStore = ScratchFilenameStore()
		let directory = harness.directory
		let url = directory.appendingPathComponent(filenameStore.filename)
		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		let payload = Data("irreplaceable historic archive".utf8)
		let entityName = inferable ? "UnrecognizedHistoryVersion" : HistoricLogDatabase.entityName
		let original = try await context.perform {
			let attribute = NSAttributeDescription()
			attribute.name = HistoricLogAttribute.entryIdentifier.rawValue
			attribute.attributeType = .binaryDataAttributeType
			let entity = NSEntityDescription()
			entity.name = entityName
			entity.managedObjectClassName = "NSManagedObject"
			entity.properties = [attribute]
			let model = NSManagedObjectModel()
			model.entities = [entity]
			let modelURL = try #require(Bundle(for: LogLineArchive.self).url(
				forResource: HistoricLogDatabase.modelName, withExtension: "momd"
			))
			let destination = try #require(NSManagedObjectModel(contentsOf: modelURL))
			if inferable {
				// Removing an unrelated entity is a valid, but data-losing, lightweight migration.
				_ = try NSMappingModel.inferredMappingModel(forSourceModel: model, destinationModel: destination)
			} else {
				// The same entity's binary identifier cannot migrate to the app's integer identifier.
				#expect(throws: (any Error).self) {
					_ = try NSMappingModel.inferredMappingModel(forSourceModel: model, destinationModel: destination)
				}
			}
			let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
			let persistentStore = try coordinator.addPersistentStore(type: .sqlite, at: url)
			context.persistentStoreCoordinator = coordinator
			let object = NSManagedObject(entity: entity, insertInto: context)
			object.setValue(payload, forKey: HistoricLogAttribute.entryIdentifier.rawValue)
			try context.save()
			let metadata = coordinator.metadata(for: persistentStore)
			let hashes = try #require(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
			let identifier = try #require(metadata[NSStoreUUIDKey] as? String)
			context.reset()
			try coordinator.remove(persistentStore)
			return (hashes: hashes, identifier: identifier)
		}

		let store = HistoricLogStore(filenameStore: filenameStore)
		for _ in 0 ..< 2 {
			let outcome = await store.openDatabase(inDirectory: directory.path)
			#expect(outcome.isOpen == false)
			if case let .failed(reason) = outcome {
				#expect(reason != nil)
			}
		}
		await store.close()
		let archives = try await context.perform {
			let coordinator = try #require(context.persistentStoreCoordinator)
			let persistentStore = try coordinator.addPersistentStore(type: .sqlite, at: url)
			defer { try? coordinator.remove(persistentStore) }
			let metadata = coordinator.metadata(for: persistentStore)
			#expect(metadata[NSStoreModelVersionHashesKey] as? [String: Data] == original.hashes)
			#expect(metadata[NSStoreUUIDKey] as? String == original.identifier)
			let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
			let archives = try context.fetch(request).compactMap {
				$0.value(forKey: HistoricLogAttribute.entryIdentifier.rawValue) as? Data
			}
			context.reset()
			return archives
		}
		#expect(archives == [payload])
		let databases = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
			.filter { $0.pathExtension == "sqlite" }
		#expect(databases.map(\.lastPathComponent) == [filenameStore.filename])
		await harness.shutdown()
	}

	@Test("A failed save retains pending rows so a later save can recover them")
	func failedSaveDoesNotResetPendingRows() async throws {
		let harness = try HistoricLogStoreHarness()
		let directory = harness.directory
		let context = try HistoricLogDatabase.makeStack(at: directory.appendingPathComponent("save-failure.sqlite"))
		let line = entry("pending archive", date: 200)
		try await context.perform {
			HistoricLogDatabase.insert(line, in: context, entryIdentifier: 1)
			let inserted = try #require(context.insertedObjects.first)
			inserted.setValue(nil, forKey: HistoricLogAttribute.sessionIdentifier.rawValue)
			HistoricLogDatabase.quickSave(context)
			#expect(context.hasChanges)
			#expect(context.insertedObjects.count == 1)
			#expect(inserted.value(forKey: HistoricLogAttribute.logLineData.rawValue) as? Data == line.data)
			inserted.setValue(
				NSNumber(value: line.sessionIdentifier),
				forKey: HistoricLogAttribute.sessionIdentifier.rawValue
			)
			try context.save()
			context.reset()
			let saved = HistoricLogDatabase.fetchEntries(
				in: context, viewIdentifier: "history", ascending: true, fetchLimit: 0, limitToDate: nil
			)
			#expect(saved.map(\.data) == [line.data])
		}
		await harness.shutdown()
	}

	@Test("Ten concurrent fetches all see the lines that were written")
	func concurrentFetchesAllSeeTheWrites() async throws {
		let harness = try HistoricLogStoreHarness()
		#expect(await harness.openDatabase())

		let view = "view-\(UUID().uuidString)"
		let lineCount = 40
		for index in 0 ..< lineCount {
			await harness.write(index, inView: view)
		}
		await harness.save()

		let results = await withTaskGroup(of: Int.self) { group in
			for _ in 0 ..< 10 {
				group.addTask { await harness.lineCount(inView: view, limit: UInt(lineCount)) }
			}
			var values: [Int] = []
			for await value in group {
				values.append(value)
			}
			return values
		}

		#expect(results.count == 10)
		#expect(Set(results) == [lineCount])
		await harness.shutdown()
	}

	@Test("Forgetting a view reports its lines and empties it")
	func forgettingAViewReportsAndEmptiesIt() async throws {
		let harness = try HistoricLogStoreHarness()
		#expect(await harness.openDatabase())

		let view = "view-\(UUID().uuidString)"
		for index in 0 ..< 5 {
			await harness.write(index, inView: view)
		}
		await harness.save()
		#expect(await harness.lineCount(inView: view) == 5)

		await harness.forgetView(view)

		#expect(await harness.lineCount(inView: view) == 0)
		#expect(await Set(harness.deletedIdentifiers) == Set((0 ..< 5).map { "line-\($0)" }))
		await harness.shutdown()
	}

	@Test("Two views written at once do not see each other's lines")
	func viewsAreIsolatedFromEachOther() async throws {
		let harness = try HistoricLogStoreHarness()
		#expect(await harness.openDatabase())

		let first = "view-\(UUID().uuidString)"
		let second = "view-\(UUID().uuidString)"
		for index in 0 ..< 12 {
			await harness.write(index, inView: index.isMultiple(of: 2) ? first : second)
		}
		await harness.save()

		async let firstCount = harness.lineCount(inView: first)
		async let secondCount = harness.lineCount(inView: second)
		#expect(await firstCount == 6)
		#expect(await secondCount == 6)
		await harness.shutdown()
	}
}
