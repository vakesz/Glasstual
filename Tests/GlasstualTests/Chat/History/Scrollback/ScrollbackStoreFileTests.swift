// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
@testable import Glasstual
import Synchronization
import Testing

/// What the store does when it is asked to open a database and the setting
/// that remembers one names nothing, or names something it cannot read.
///
/// 2.0 writes a schema no earlier release wrote and migrates nothing, so a 1.x
/// `logControllerHistoricLog_*.sqlite` is never named by the setting again.
/// These cover both halves of that: a fresh database is minted under the current
/// name, and anything already in the directory is left exactly as it was.
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
