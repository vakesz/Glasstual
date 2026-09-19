// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
@testable import Glasstual
import Testing

/** Several rows of one view can carry the same line identifier, the same
 timestamp and the same insertion identifier at once, because a line identifier
 names a line and a row is a row. Paging and retention therefore have to work off
 the physical row, and this drives a store seeded with exactly that shape. */
@MainActor
@Suite("Scrollback rows that share a line identity", .serialized)
struct ScrollbackDuplicateRowTests {
	private static let view = "duplicate-row-view"

	/// One seeded row, written straight through `ScrollbackQueries.insert` so the
	/// insertion identifier is the test's to choose rather than the store's.
	private struct SeededRow {
		let entryIdentifier: UInt
		let lineIdentifier: String
		let body: String
		let time: Double

		var entry: ScrollbackEntry {
			ScrollbackEntry(
				lineData: Data(body.utf8),
				uniqueIdentifier: lineIdentifier,
				viewIdentifier: ScrollbackDuplicateRowTests.view,
				sessionIdentifier: 77,
				creationDate: time
			)
		}
	}

	/// Gapped insertion identifiers, and three rows that tie on the line
	/// identifier, the timestamp and the insertion identifier at once.
	private static let seeded = [
		SeededRow(entryIdentifier: 1, lineIdentifier: "old", body: "older", time: 1000),
		SeededRow(entryIdentifier: 100, lineIdentifier: "duplicate", body: "duplicate-a", time: 2000),
		SeededRow(entryIdentifier: 100, lineIdentifier: "duplicate", body: "duplicate-b", time: 2000),
		SeededRow(entryIdentifier: 100, lineIdentifier: "duplicate", body: "duplicate-c", time: 2000),
		SeededRow(entryIdentifier: 9000, lineIdentifier: "new", body: "newer", time: 3000),
	]

	@Test("Physical row cursors page tied line identities across reopen; retention counts actual rows")
	func tiedRowsPageAndPruneByRow() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString,
			isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let filenameSetting = ScrollbackFilenameFixture.unique()
		let url = directory.appendingPathComponent(filenameSetting.filename)
		let seeded = Self.seeded.map { row in (row.entry, row.entryIdentifier) }
		try await ScrollbackFixture.withContext(at: url) { context in
			for (entry, identifier) in seeded {
				ScrollbackQueries.insert(entry, in: context, entryIdentifier: identifier)
			}
			try context.save()
		}

		let original = try await ScrollbackFixture.withContext(at: url) { context in
			let request = NSFetchRequest<NSManagedObject>(entityName: ScrollbackQueries.entityName)
			return try context.fetch(request).map { object in
				try (#require(ScrollbackEntry(managedObject: object)),
				     #require(object.value(forKey: ScrollbackAttribute.entryID.rawValue) as? NSNumber).int64Value)
			}
		}
		#expect(original.count == 5)
		#expect(original.map(\.1).sorted() == [1, 100, 100, 100, 9000])

		let store = ScrollbackStore(filenameSetting: filenameSetting.store)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)

		/* One row at a time, closing and reopening between pages: the cursor is
		 persisted, so it has to still name the same row in a new stack. */
		var cursor: ScrollbackRowCursor?
		var visited: [ScrollbackEntry] = []
		for _ in 0 ..< 6 {
			let outcome = await store.fetchOutcome(.init(
				viewIdentifier: Self.view,
				kind: .rowPage(before: cursor, fetchLimit: 1, limitToDate: nil)
			))
			guard case let .page(rows) = outcome else {
				Issue.record("Row pagination failed")
				return
			}
			if rows.isEmpty {
				break
			}
			visited += rows
			cursor = try #require(rows.last?.cursor)
			#expect(await store.close() == .saved)
			#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		}
		#expect(visited.count == 5)
		#expect(Set(visited.compactMap(\.cursor).map(\.rowURI)).count == 5)
		#expect(Set(visited.map(\.data)) == Set(original.map(\.0.data)))
		#expect(visited.filter { $0.uniqueIdentifier == "duplicate" }.count == 3)

		// Identifier allocation continues past the gap rather than colliding with it.
		var newLine = ChatLine()
		newLine.messageBody = "appended"
		newLine.receivedAt = Date(timeIntervalSince1970: 4000)
		#expect(await store.writeChatLine(newLine.scrollbackEntry(forView: Self.view)) == .accepted)
		#expect(await store.close() == .saved)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)

		let appendedPage = await store.fetchOutcome(
			.newestEntries(forView: Self.view, fetchLimit: 10)
		)
		#expect(appendedPage.entries.first?.cursor?.insertionIdentifier == 9001)
		#expect(Set(original.map(\.0.data)).isSubset(of: Set(appendedPage.entries.map(\.data))))

		/* Six rows down to four removes two rows, and only "old" loses its last
		 row — "duplicate" still has two, so it is not reported as gone. */
		await store.setMaximumLineCount(4)
		guard case let .deleted(result) = await store.resize(Self.view) else {
			Issue.record("Retention failed")
			return
		}
		#expect(result.deletedCount == 2)
		#expect(result.uniqueIdentifiers == ["old"])

		let retained = await store.fetchOutcome(
			.newestEntries(forView: Self.view, fetchLimit: 10)
		).entries
		#expect(retained.count == 4)
		#expect(retained.filter { $0.uniqueIdentifier == "duplicate" }.count == 2)
		#expect(Set(retained.map(\.data)).isSubset(of: Set(appendedPage.entries.map(\.data))))
		await store.close()
	}
}
