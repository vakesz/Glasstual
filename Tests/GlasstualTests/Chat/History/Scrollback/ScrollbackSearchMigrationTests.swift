// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
@testable import Glasstual
import Synchronization
import Testing

/// One stored row as a test reads it back: the six original columns and the
/// three the searchable schema added. `nil` marks a column the schema does not
/// have, which is how the old schema's rows read.
private nonisolated struct StoredRow: Hashable, Sendable {
	let entryID: Int64
	let createdAt: Double
	let data: Data
	let lineID: String
	let sessionID: Int64
	let viewID: String
	let plainText: String?
	let sender: String?
	let searchText: String?

	init(
		entryID: Int64, createdAt: Double, data: Data, lineID: String, sessionID: Int64, viewID: String
	) {
		self.entryID = entryID
		self.createdAt = createdAt
		self.data = data
		self.lineID = lineID
		self.sessionID = sessionID
		self.viewID = viewID
		plainText = nil
		sender = nil
		searchText = nil
	}

	init(_ object: NSManagedObject) throws {
		entryID = try #require((object.value(forKey: ScrollbackAttribute.entryID.rawValue) as? NSNumber)?.int64Value)
		createdAt = try #require((object.value(forKey: ScrollbackAttribute.createdAt.rawValue) as? NSNumber)?.doubleValue)
		data = try #require(object.value(forKey: ScrollbackAttribute.lineData.rawValue) as? Data)
		lineID = try #require(object.value(forKey: ScrollbackAttribute.lineID.rawValue) as? String)
		sessionID = try #require((object.value(forKey: ScrollbackAttribute.sessionID.rawValue) as? NSNumber)?.int64Value)
		viewID = try #require(object.value(forKey: ScrollbackAttribute.viewID.rawValue) as? String)
		let hasSearchColumns = object.entity.propertiesByName[ScrollbackAttribute.plainText.rawValue] != nil
		plainText = hasSearchColumns ? object.value(forKey: ScrollbackAttribute.plainText.rawValue) as? String : nil
		sender = hasSearchColumns ? object.value(forKey: ScrollbackAttribute.sender.rawValue) as? String : nil
		searchText = hasSearchColumns ? object.value(forKey: ScrollbackAttribute.searchText.rawValue) as? String : nil
	}

	/// The original columns only, which is what an upgrade has to leave alone.
	var original: StoredRow {
		StoredRow(entryID: entryID, createdAt: createdAt, data: data, lineID: lineID, sessionID: sessionID, viewID: viewID)
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

/** The upgrade from the schema with indexes to the one with searchable columns.

 Every store here is minted from the earlier model in the test itself, so the
 starting point is the schema a real installation holds rather than a copy of
 the current one. */
@MainActor
@Suite("Scrollback search migration", .serialized)
struct ScrollbackSearchMigrationTests {
	private func makeDirectory() throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("scrollback-search-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	private func archived(
		_ body: String,
		nickname: String? = "alice",
		type: ChatLineKind = .privateMessage,
		redacted: Bool = false
	) -> (data: Data, identifier: String) {
		var line = ChatLine()
		line.messageBody = body
		line.nickname = nickname
		line.lineType = type
		if redacted {
			line.redact()
		}
		let entry = line.scrollbackEntry(forView: "unused")
		return (entry.data, line.uniqueIdentifier)
	}

	/// Mints a store in the indexed schema, which is what every store written
	/// before searchable columns holds.
	private func seedIndexedStore(at url: URL, rows: [StoredRow]) async throws {
		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		try await context.perform {
			let model = try ScrollbackModelMigration.indexedModel(from: ScrollbackModelMigration.loadUnindexedModel())
			let entity = try #require(model.entitiesByName[ScrollbackQueries.entityName])
			let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
			let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
			context.persistentStoreCoordinator = coordinator
			for row in rows {
				row.insert(in: context, entity: entity)
			}
			try context.save()
			context.reset()
			try coordinator.remove(store)
		}
	}

	private nonisolated enum Schema: Sendable {
		case indexed, searchable
	}

	private func readRows(at url: URL, schema: Schema) async throws -> [StoredRow] {
		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		return try await context.perform {
			let versions = try ScrollbackModelMigration.versions()
			let model = switch schema {
			case .indexed: versions.indexed
			case .searchable: versions.searchable
			}
			let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
			let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
			context.persistentStoreCoordinator = coordinator
			defer { try? coordinator.remove(store) }
			let request = NSFetchRequest<NSManagedObject>(entityName: ScrollbackQueries.entityName)
			return try context.fetch(request).map(StoredRow.init)
		}
	}

	private func metadata(at url: URL) throws -> [String: Any] {
		try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url, options: nil)
	}

	private func sampleRows() -> [StoredRow] {
		let plain = archived("Hello World")
		let accented = archived("Caf\u{00E9} \u{02}bold\u{02} \u{03}04red\u{03} done", nickname: "bob")
		let action = archived("waves hello", nickname: "carol", type: .action)
		let join = archived("joined the channel", nickname: "dave", type: .join)
		let deleted = archived("a secret that was deleted", nickname: "erin", redacted: true)
		return [
			StoredRow(entryID: 1, createdAt: 1000, data: plain.data, lineID: plain.identifier, sessionID: 5, viewID: "main"),
			StoredRow(entryID: 2, createdAt: 1001, data: accented.data, lineID: accented.identifier, sessionID: 5, viewID: "main"),
			StoredRow(entryID: 3, createdAt: 1002, data: action.data, lineID: action.identifier, sessionID: 5, viewID: "main"),
			StoredRow(entryID: 4, createdAt: 1003, data: join.data, lineID: join.identifier, sessionID: 5, viewID: "main"),
			StoredRow(entryID: 5, createdAt: 1004, data: deleted.data, lineID: deleted.identifier, sessionID: 5, viewID: "main"),
			StoredRow(entryID: 1, createdAt: 1005, data: Data("not a property list".utf8), lineID: "broken", sessionID: 6, viewID: "side"),
			// Two physical rows that share a line identity must both survive.
			StoredRow(entryID: 2, createdAt: 1006, data: plain.data, lineID: "shared", sessionID: 6, viewID: "side"),
			StoredRow(entryID: 2, createdAt: 1006, data: plain.data, lineID: "shared", sessionID: 6, viewID: "side"),
		]
	}

	@Test("An indexed store gains the search columns, backfilled from each archive, without changing a row")
	func upgradeBackfillsEveryRowAndKeepsTheOriginals() async throws {
		let directory = try makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("history.sqlite")
		let seeded = sampleRows()
		try await seedIndexedStore(at: url, rows: seeded)
		let versions = try ScrollbackModelMigration.versions()
		let before = try metadata(at: url)
		#expect(versions.indexed.isConfiguration(withName: nil, compatibleWithStoreMetadata: before))
		#expect(!versions.searchable.isConfiguration(withName: nil, compatibleWithStoreMetadata: before))

		let fractions = Mutex<[Double]>([])
		let store = ScrollbackStore(
			filenameSetting: ScrollbackFilenameFixture("history.sqlite").store,
			migrationProgress: { fraction in fractions.withLock { $0.append(fraction) } }
		)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		#expect(await store.close() == .saved)

		let after = try metadata(at: url)
		#expect(versions.searchable.isConfiguration(withName: nil, compatibleWithStoreMetadata: after))
		let rows = try await readRows(at: url, schema: .searchable)
		// Row-count parity, and every original column exactly as it was.
		#expect(rows.count == seeded.count)
		#expect(rows.map(\.original).sorted { ($0.viewID, $0.entryID, $0.lineID) < ($1.viewID, $1.entryID, $1.lineID) }
			== seeded.sorted { ($0.viewID, $0.entryID, $0.lineID) < ($1.viewID, $1.entryID, $1.lineID) })
		let byEntry = Dictionary(grouping: rows, by: \.lineID)

		let hello = try #require(byEntry[seeded[0].lineID]?.first)
		#expect(hello.plainText == "Hello World")
		#expect(hello.sender == "alice")
		#expect(hello.searchText == "hello world")
		// Control codes are not text, and the search column is folded.
		let accented = try #require(byEntry[seeded[1].lineID]?.first)
		#expect(accented.plainText == "Caf\u{00E9} bold red done")
		#expect(accented.searchText == "cafe bold red done")
		#expect(byEntry[seeded[2].lineID]?.first?.plainText == "waves hello")
		// Events narrate the session; they carry no searchable text.
		#expect(byEntry[seeded[3].lineID]?.first?.plainText == "")
		// Deleted words are in no column, and the sender stays.
		let deleted = try #require(byEntry[seeded[4].lineID]?.first)
		#expect(deleted.plainText == "")
		#expect(deleted.searchText == "")
		#expect(deleted.sender == "erin")
		// An unreadable archive stays in history with empty search columns.
		let broken = try #require(byEntry["broken"]?.first)
		#expect(broken.plainText == "")
		#expect(broken.sender == "")
		#expect(broken.searchText == "")
		#expect(byEntry["shared"]?.count == 2)

		// Progress was reported, never went backwards, and finished.
		let reported = fractions.withLock { $0 }
		#expect(reported.first == 0)
		#expect(reported.last == 1)
		#expect(reported == reported.sorted())
	}

	@Test("Opening an upgraded store again changes nothing and reports no progress")
	func upgradeIsIdempotent() async throws {
		let directory = try makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("history.sqlite")
		try await seedIndexedStore(at: url, rows: sampleRows())
		let setting = ScrollbackFilenameFixture("history.sqlite").store

		let first = ScrollbackStore(filenameSetting: setting)
		#expect(await first.openDatabase(inDirectory: directory.path).isOpen)
		#expect(await first.close() == .saved)
		let upgraded = try await readRows(at: url, schema: .searchable)
		let storeUUID = try #require(try metadata(at: url)[NSStoreUUIDKey] as? String)

		let fractions = Mutex<[Double]>([])
		let second = ScrollbackStore(
			filenameSetting: setting,
			migrationProgress: { fraction in fractions.withLock { $0.append(fraction) } }
		)
		#expect(await second.openDatabase(inDirectory: directory.path).isOpen)
		#expect(await second.close() == .saved)

		#expect(fractions.withLock { $0 }.isEmpty)
		#expect(try metadata(at: url)[NSStoreUUIDKey] as? String == storeUUID)
		#expect(try await Set(readRows(at: url, schema: .searchable)) == Set(upgraded))
		let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
			.filter { $0.hasSuffix(".sqlite") }
		#expect(leftovers == ["history.sqlite"])
	}

	@Test("A store larger than one batch keeps every row and reports steady progress")
	func upgradeSpansSeveralBatches() async throws {
		let directory = try makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("history.sqlite")
		let count = ScrollbackModelMigration.copyBatchSize * 2 + 117
		let rows = (0 ..< count).map { index in
			let line = archived("message number \(index)")
			return StoredRow(
				entryID: Int64(index + 1), createdAt: Double(1000 + index), data: line.data,
				lineID: line.identifier, sessionID: 1, viewID: "view-\(index % 3)"
			)
		}
		try await seedIndexedStore(at: url, rows: rows)

		let fractions = Mutex<[Double]>([])
		let store = ScrollbackStore(
			filenameSetting: ScrollbackFilenameFixture("history.sqlite").store,
			migrationProgress: { fraction in fractions.withLock { $0.append(fraction) } }
		)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		#expect(await store.close() == .saved)

		let upgraded = try await readRows(at: url, schema: .searchable)
		#expect(upgraded.count == count)
		#expect(Set(upgraded.map(\.lineID)) == Set(rows.map(\.lineID)))
		#expect(upgraded.allSatisfy { $0.plainText?.hasPrefix("message number ") == true })
		let reported = fractions.withLock { $0 }
		#expect(reported.count > 3)
		#expect(reported == reported.sorted())
		#expect(reported.last == 1)
	}

	@Test("A copy an earlier process left half built is discarded and the upgrade runs again")
	func interruptedWorkingCopyIsRebuilt() async throws {
		let directory = try makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("history.sqlite")
		let seeded = sampleRows()
		try await seedIndexedStore(at: url, rows: seeded)
		let workingCopy = ScrollbackModelMigration.workingCopyURL(for: url)
		try Data("half written".utf8).write(to: workingCopy)

		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture("history.sqlite").store)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		#expect(await store.close() == .saved)

		#expect(try await readRows(at: url, schema: .searchable).count == seeded.count)
		#expect(!FileManager.default.fileExists(atPath: workingCopy.path))
	}

	@Test("A failure before the swap leaves the old store exactly as it was")
	func failedUpgradeLeavesTheOldStoreIntact() async throws {
		let directory = try makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("history.sqlite")
		let seeded = sampleRows()
		try await seedIndexedStore(at: url, rows: seeded)
		let versions = try ScrollbackModelMigration.versions()
		let bytesBefore = try Data(contentsOf: url)
		let uuidBefore = try #require(try metadata(at: url)[NSStoreUUIDKey] as? String)

		/* A working copy that cannot be cleared stops the upgrade before it
		 writes anything: a directory holding a file is not something it may
		 remove. */
		let workingCopy = ScrollbackModelMigration.workingCopyURL(for: url)
		try FileManager.default.createDirectory(at: workingCopy, withIntermediateDirectories: true)
		try Data("keep".utf8).write(to: workingCopy.appendingPathComponent("occupant"))

		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture("history.sqlite").store)
		let outcome = await store.openDatabase(inDirectory: directory.path)
		#expect(!outcome.isOpen)

		let after = try metadata(at: url)
		#expect(versions.indexed.isConfiguration(withName: nil, compatibleWithStoreMetadata: after))
		#expect(after[NSStoreUUIDKey] as? String == uuidBefore)
		#expect(try Data(contentsOf: url) == bytesBefore)
		let rows = try await readRows(at: url, schema: .indexed)
		#expect(rows.count == seeded.count)
		#expect(Set(rows.map(\.original)) == Set(seeded))
	}

	@Test("A store the build does not recognise is left untouched")
	func unknownSchemaIsNotUpgraded() async throws {
		let directory = try makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("history.sqlite")

		let model = NSManagedObjectModel()
		let entity = NSEntityDescription()
		entity.name = "Unrelated"
		let attribute = NSAttributeDescription()
		attribute.name = "title"
		attribute.attributeType = .stringAttributeType
		entity.properties = [attribute]
		model.entities = [entity]
		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
		let seeded = try coordinator.addPersistentStore(type: .sqlite, at: url)
		try coordinator.remove(seeded)
		let bytesBefore = try Data(contentsOf: url)

		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture("history.sqlite").store)
		#expect(await !(store.openDatabase(inDirectory: directory.path).isOpen))
		#expect(try Data(contentsOf: url) == bytesBefore)
	}
}
