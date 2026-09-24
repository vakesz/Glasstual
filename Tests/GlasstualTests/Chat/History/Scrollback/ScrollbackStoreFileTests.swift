// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
@testable import Glasstual
import Synchronization
import Testing

private nonisolated struct SavedScrollbackRow: Hashable, Sendable {
	let entryID: Int64
	let createdAt: Double
	let data: Data
	let lineID: String
	let sessionID: Int64
	let viewID: String

	init(entryID: Int64, createdAt: Double, data: Data, lineID: String, sessionID: Int64, viewID: String) {
		self.entryID = entryID
		self.createdAt = createdAt
		self.data = data
		self.lineID = lineID
		self.sessionID = sessionID
		self.viewID = viewID
	}

	init(_ object: NSManagedObject) throws {
		entryID = try #require((object.value(forKey: ScrollbackAttribute.entryID.rawValue) as? NSNumber)?.int64Value)
		createdAt = try #require((object.value(forKey: ScrollbackAttribute.createdAt.rawValue) as? NSNumber)?.doubleValue)
		data = try #require(object.value(forKey: ScrollbackAttribute.lineData.rawValue) as? Data)
		lineID = try #require(object.value(forKey: ScrollbackAttribute.lineID.rawValue) as? String)
		sessionID = try #require((object.value(forKey: ScrollbackAttribute.sessionID.rawValue) as? NSNumber)?.int64Value)
		viewID = try #require(object.value(forKey: ScrollbackAttribute.viewID.rawValue) as? String)
	}

	func insert(in context: NSManagedObjectContext, entity: NSEntityDescription) {
		let object = NSManagedObject(entity: entity, insertInto: context)
		object.setValue(NSNumber(value: entryID), forKey: ScrollbackAttribute.entryID.rawValue)
		object.setValue(NSNumber(value: createdAt), forKey: ScrollbackAttribute.createdAt.rawValue)
		object.setValue(data, forKey: ScrollbackAttribute.lineData.rawValue)
		object.setValue(lineID, forKey: ScrollbackAttribute.lineID.rawValue)
		object.setValue(NSNumber(value: sessionID), forKey: ScrollbackAttribute.sessionID.rawValue)
		object.setValue(viewID, forKey: ScrollbackAttribute.viewID.rawValue)
	}
}

/// What the store does when it is asked to open a database and the setting
/// that remembers one names nothing, or names something it cannot read.
///
/// 2.0 writes a schema no 1.x release wrote, so a 1.x
/// `logControllerHistoricLog_*.sqlite` is never named by the setting again.
/// Existing 2.x stores do receive the index-only model upgrade. These tests
/// cover both paths and keep unrelated files in the directory intact.
@MainActor
@Suite("Scrollback database file", .serialized)
struct ScrollbackStoreFileTests {
	private func makeDirectory() throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("scrollback-file-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		return directory
	}

	private func sqliteNames(in directory: URL) throws -> [String] {
		try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
			.filter { $0.pathExtension == "sqlite" }
			.map(\.lastPathComponent)
			.sorted()
	}

	@Test("A compatible unindexed 2.x database upgrades without losing or merging rows")
	func compatibleUnindexedDatabasePreservesEveryRow() async throws {
		let directory = try makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let filename = "\(ScrollbackStore.databaseFilenamePrefix)\(UUID().uuidString).sqlite"
		let url = directory.appendingPathComponent(filename)
		let expected = [
			SavedScrollbackRow(entryID: 1, createdAt: 1000, data: Data("first archive".utf8),
			                   lineID: "one", sessionID: 11, viewID: "main"),
			SavedScrollbackRow(entryID: 7, createdAt: 2000, data: Data("second archive".utf8),
			                   lineID: "shared", sessionID: 11, viewID: "main"),
			SavedScrollbackRow(entryID: 7, createdAt: 2000, data: Data("third archive".utf8),
			                   lineID: "shared", sessionID: 11, viewID: "main"),
			SavedScrollbackRow(entryID: 2, createdAt: 1500, data: Data("other view".utf8),
			                   lineID: "other", sessionID: 22, viewID: "side"),
		]

		// Mint the actual shipping 2.x schema before its fetch indexes were added.
		let seedingContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		try await seedingContext.perform {
			let model = try ScrollbackModelMigration.loadUnindexedModel()
			let entity = try #require(model.entitiesByName[ScrollbackQueries.entityName])
			#expect(entity.indexes.isEmpty)
			let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
			let persistentStore = try coordinator.addPersistentStore(type: .sqlite, at: url)
			seedingContext.persistentStoreCoordinator = coordinator
			for row in expected {
				row.insert(in: seedingContext, entity: entity)
			}
			try seedingContext.save()
			let request = NSFetchRequest<NSManagedObject>(entityName: ScrollbackQueries.entityName)
			#expect(try seedingContext.count(for: request) == expected.count)
			seedingContext.reset()
			try coordinator.remove(persistentStore)
		}
		let unindexedModel = try ScrollbackModelMigration.loadUnindexedModel()
		let indexedModel = try ScrollbackModelMigration.indexedModel(from: unindexedModel)
		let originalMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
			type: .sqlite, at: url, options: nil
		)
		#expect(unindexedModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: originalMetadata))
		#expect(!indexedModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: originalMetadata))
		let workingURL = directory.appendingPathComponent(".\(filename).indexing.sqlite")
		try Data("interrupted migration".utf8).write(to: workingURL)

		let setting = ScrollbackFilenameFixture(filename).store
		let store = ScrollbackStore(filenameSetting: setting)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		#expect(!FileManager.default.fileExists(atPath: workingURL.path))
		let mainRows = await store.fetchOutcome(.newestEntries(forView: "main", fetchLimit: 10)).entries
		let sideRows = await store.fetchOutcome(.newestEntries(forView: "side", fetchLimit: 10)).entries
		#expect(mainRows.count == 3)
		#expect(sideRows.count == 1)
		#expect(Set(mainRows.map(\.data)) == Set(expected.filter { $0.viewID == "main" }.map(\.data)))
		#expect(sideRows.map(\.data) == [expected[3].data])
		#expect(await store.close() == .saved)
		let upgradedMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
			type: .sqlite, at: url, options: nil
		)
		#expect(indexedModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: upgradedMetadata))
		let upgradedUUID = try #require(upgradedMetadata[NSStoreUUIDKey] as? String)

		// Read all columns from the upgraded file, including the tied physical rows.
		let upgradedContext = try ScrollbackQueries.makeStack(at: url)
		let actual = try await upgradedContext.perform {
			let request = NSFetchRequest<NSManagedObject>(entityName: ScrollbackQueries.entityName)
			return try upgradedContext.fetch(request).map(SavedScrollbackRow.init)
		}
		#expect(actual.count == expected.count)
		#expect(Set(actual) == Set(expected))

		try Data("interrupted cleanup".utf8).write(to: workingURL)
		let relaunched = ScrollbackStore(filenameSetting: setting)
		#expect(await relaunched.openDatabase(inDirectory: directory.path).isOpen)
		#expect(!FileManager.default.fileExists(atPath: workingURL.path))
		let reopenedMainRows = await relaunched.fetchOutcome(.newestEntries(forView: "main", fetchLimit: 10)).entries
		let reopenedSideRows = await relaunched.fetchOutcome(.newestEntries(forView: "side", fetchLimit: 10)).entries
		#expect(reopenedMainRows.count == 3)
		#expect(Set(reopenedMainRows.map(\.data)) == Set(expected.filter { $0.viewID == "main" }.map(\.data)))
		#expect(reopenedSideRows.map(\.data) == [expected[3].data])
		#expect(await relaunched.close() == .saved)
		let reopenedMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
			type: .sqlite, at: url, options: nil
		)
		#expect(reopenedMetadata[NSStoreUUIDKey] as? String == upgradedUUID)
		#expect(try sqliteNames(in: directory) == [filename])
	}

	@Test("An empty preference mints a database under the current name and keeps it across reopen")
	func freshInstallMintsAndRemembersOneDatabase() async throws {
		let directory = try makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		/* The shape a first launch after installation has: the setting that
		 remembers the file name has none yet, and keeps whatever is written. */
		let remembered = Mutex<String?>(nil)
		let filenameSetting = ScrollbackFilenameSetting(
			load: { remembered.withLock { $0 } },
			save: { name in remembered.withLock { $0 = name } }
		)

		let store = ScrollbackStore(filenameSetting: filenameSetting)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)

		let minted = try #require(remembered.withLock { $0 })
		#expect(minted.hasPrefix(ScrollbackStore.databaseFilenamePrefix))
		#expect(minted.hasSuffix(".sqlite"))

		var line = ChatLine()
		line.messageBody = "written before relaunch"
		#expect(await store.writeChatLine(line.scrollbackEntry(forView: "view")) == .accepted)
		#expect(await store.close() == .saved)

		// The relaunch: a new store, the same setting, the same file and rows.
		let relaunched = ScrollbackStore(filenameSetting: filenameSetting)
		#expect(await relaunched.openDatabase(inDirectory: directory.path).isOpen)
		#expect(remembered.withLock { $0 } == minted)
		let rows = await relaunched.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 10)).entries
		#expect(rows.map(\.uniqueIdentifier) == [line.uniqueIdentifier])
		#expect(await relaunched.close() == .saved)

		#expect(try sqliteNames(in: directory) == [minted])
	}

	@Test("A database written by an earlier schema is ignored, not adopted or destroyed")
	func anEarlierSchemaIsLeftWhereItIs() async throws {
		let directory = try makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		/* A store in the shape 1.x wrote: the entity and attribute names the
		 model used before this phase, with one row in it. */
		let legacyName = "logControllerHistoricLog_\(UUID().uuidString).sqlite"
		let legacyURL = directory.appendingPathComponent(legacyName)
		let payload = Data("a row from an earlier release".utf8)
		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		try await context.perform {
			let data = NSAttributeDescription()
			data.name = "logLineData"
			data.attributeType = .binaryDataAttributeType
			let entity = NSEntityDescription()
			entity.name = "LogLine2"
			entity.managedObjectClassName = "NSManagedObject"
			entity.properties = [data]
			let model = NSManagedObjectModel()
			model.entities = [entity]
			let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
			let persistentStore = try coordinator.addPersistentStore(type: .sqlite, at: legacyURL)
			context.persistentStoreCoordinator = coordinator
			let object = NSManagedObject(entity: entity, insertInto: context)
			object.setValue(payload, forKey: "logLineData")
			try context.save()
			context.reset()
			try coordinator.remove(persistentStore)
		}

		// Nothing points at it, because the setting that would is empty.
		let remembered = Mutex<String?>(nil)
		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameSetting(
			load: { remembered.withLock { $0 } },
			save: { name in remembered.withLock { $0 = name } }
		))
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		let minted = try #require(remembered.withLock { $0 })
		#expect(minted != legacyName)
		#expect(await store.close() == .saved)

		#expect(try sqliteNames(in: directory) == [minted, legacyName].sorted())

		// Exactly what it held: no migration read it, no pass rewrote it.
		let surviving = try await context.perform {
			let coordinator = try #require(context.persistentStoreCoordinator)
			let persistentStore = try coordinator.addPersistentStore(type: .sqlite, at: legacyURL)
			defer { try? coordinator.remove(persistentStore) }
			let request = NSFetchRequest<NSManagedObject>(entityName: "LogLine2")
			let rows = try context.fetch(request).compactMap { $0.value(forKey: "logLineData") as? Data }
			context.reset()
			return rows
		}
		#expect(surviving == [payload])
	}

	@Test("A database the preference names but this build cannot open fails openly")
	func anUnreadableDatabaseFailsRatherThanEmptyingItself() async throws {
		let directory = try makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		/* Not a database at all, which is what a truncated file or a foreign
		 format looks like from here. The store must report why rather than
		 replace it, so the transcript's recovery banner can offer the retry. */
		let filename = "\(ScrollbackStore.databaseFilenamePrefix)\(UUID().uuidString).sqlite"
		let url = directory.appendingPathComponent(filename)
		let contents = Data("not a database".utf8)
		try contents.write(to: url)

		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture(filename).store)
		for _ in 0 ..< 2 {
			let outcome = await store.openDatabase(inDirectory: directory.path)
			#expect(outcome.isOpen == false)
			guard case let .failed(reason) = outcome else {
				Issue.record("An unreadable database was reported as open")
				return
			}
			#expect(reason != nil)
		}
		await store.close()

		#expect(try Data(contentsOf: url) == contents)
		#expect(try sqliteNames(in: directory) == [filename])
	}
}
