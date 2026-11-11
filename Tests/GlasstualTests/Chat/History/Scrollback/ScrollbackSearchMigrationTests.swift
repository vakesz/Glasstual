// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
@testable import Glasstual
import Synchronization
import Testing

/// One stored row as a test reads it back: the six original columns, the
/// three the searchable schema added and the message identifier the current
/// one added. `nil` marks a column the schema does not have, which is how the
/// old schemas' rows read.
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
	let messageID: String?

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
		messageID = nil
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
		let hasMessageColumn = object.entity.propertiesByName[ScrollbackAttribute.messageID.rawValue] != nil
		messageID = hasMessageColumn ? object.value(forKey: ScrollbackAttribute.messageID.rawValue) as? String : nil
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

/** The upgrades from the earlier schemas to the current one, which adds the
 searchable columns and the indexed message identifier.

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
		redacted: Bool = false,
		messageIdentifier: String? = nil
	) -> (data: Data, identifier: String) {
		var line = ChatLine()
		line.messageBody = body
		line.nickname = nickname
		line.lineType = type
		line.messageIdentifier = messageIdentifier
		if redacted {
			line.redact()
		}
		let entry = line.scrollbackEntry(forView: "unused")
		return (entry.data, line.uniqueIdentifier)
	}

	/// Mints a store in the indexed schema, which is what every store written
	/// before searchable columns holds.
	private func seedIndexedStore(at url: URL, rows: [StoredRow]) async throws {
		try await seedStore(at: url, schema: .indexed, rows: rows)
	}

	/// Mints a store in an earlier schema. Only the six original columns are
	/// written, which is all a copy reads from it.
	private func seedStore(at url: URL, schema: Schema, rows: [StoredRow]) async throws {
		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		try await context.perform {
			let model = try Self.model(for: schema)
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
		case indexed, searchable, current
	}

	private nonisolated static func model(for schema: Schema) throws -> NSManagedObjectModel { // nonisolated: pure
		let versions = try ScrollbackModelMigration.versions()
		return switch schema {
		case .indexed: versions.indexed
		case .searchable: versions.searchable
		case .current: versions.current
		}
	}

	private func readRows(at url: URL, schema: Schema) async throws -> [StoredRow] {
		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		return try await context.perform {
			let model = try Self.model(for: schema)
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
		#expect(!versions.current.isConfiguration(withName: nil, compatibleWithStoreMetadata: before))

		let fractions = Mutex<[Double]>([])
		let store = ScrollbackStore(
			filenameSetting: ScrollbackFilenameFixture("history.sqlite").store,
			migrationProgress: { fraction in fractions.withLock { $0.append(fraction) } }
		)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		#expect(await store.close() == .saved)

		let after = try metadata(at: url)
		#expect(versions.current.isConfiguration(withName: nil, compatibleWithStoreMetadata: after))
		let rows = try await readRows(at: url, schema: .current)
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
		let upgraded = try await readRows(at: url, schema: .current)
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
		#expect(try await Set(readRows(at: url, schema: .current)) == Set(upgraded))
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

		let upgraded = try await readRows(at: url, schema: .current)
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

		#expect(try await readRows(at: url, schema: .current).count == seeded.count)
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

	@Test("A searchable store gains the message identifier column, and its old rows can be redacted")
	func searchableStoreGainsMessageIdentifiers() async throws {
		let directory = try makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("history.sqlite")
		let tagged = archived("a secret said before the update", messageIdentifier: "msg-1")
		let other = archived("an unrelated line", nickname: "bob", messageIdentifier: "msg-2")
		let untagged = archived("no identifier at all")
		let seeded = [
			StoredRow(entryID: 1, createdAt: 1000, data: tagged.data, lineID: tagged.identifier, sessionID: 5, viewID: "main"),
			StoredRow(entryID: 2, createdAt: 1001, data: other.data, lineID: other.identifier, sessionID: 5, viewID: "main"),
			StoredRow(entryID: 3, createdAt: 1002, data: untagged.data, lineID: untagged.identifier, sessionID: 5, viewID: "main"),
			StoredRow(entryID: 1, createdAt: 1003, data: Data("not a property list".utf8), lineID: "broken", sessionID: 6, viewID: "side"),
		]
		try await seedStore(at: url, schema: .searchable, rows: seeded)
		let versions = try ScrollbackModelMigration.versions()
		let before = try metadata(at: url)
		#expect(versions.searchable.isConfiguration(withName: nil, compatibleWithStoreMetadata: before))
		#expect(!versions.current.isConfiguration(withName: nil, compatibleWithStoreMetadata: before))

		let fractions = Mutex<[Double]>([])
		let store = ScrollbackStore(
			filenameSetting: ScrollbackFilenameFixture("history.sqlite").store,
			migrationProgress: { fraction in fractions.withLock { $0.append(fraction) } }
		)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		#expect(fractions.withLock { $0.last } == 1)

		// A row written before the update is found through the new column.
		guard case let .redacted(line) = await store.redactChatLine(messageIdentifier: "msg-1", inView: "main") else {
			Issue.record("The migrated row was not found by its message identifier")
			return
		}
		#expect(line.uniqueIdentifier == tagged.identifier)
		#expect(line.messageBody.isEmpty)
		#expect(await store.close() == .saved)

		#expect(try versions.current.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata(at: url)))
		let rows = try await readRows(at: url, schema: .current)
		#expect(rows.count == seeded.count)
		let byLine = Dictionary(uniqueKeysWithValues: rows.map { ($0.lineID, $0) })
		#expect(byLine[tagged.identifier]?.messageID == "msg-1")
		#expect(byLine[tagged.identifier]?.plainText == "")
		#expect(byLine[other.identifier]?.messageID == "msg-2")
		#expect(byLine[other.identifier]?.plainText == "an unrelated line")
		#expect(byLine[untagged.identifier]?.messageID == nil)
		#expect(byLine["broken"]?.messageID == nil)
		#expect(byLine["broken"]?.data == Data("not a property list".utf8))
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
