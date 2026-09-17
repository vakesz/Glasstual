// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
@testable import Glasstual
import Testing

@MainActor
@Suite("v1.0.7 model-3 history fixture", .serialized)
struct ScrollbackShippedFixtureTests {
	@Test("Physical row cursors page tied duplicate line IDs across reopen; retention counts actual rows")
	func shippedStoreRoundTrip() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString,
			isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Corpora/History/v1.0.7-history.sqlite")
		let destination = directory.appendingPathComponent("fixture.sqlite")
		try FileManager.default.copyItem(at: source, to: destination)
		let original = try await ScrollbackFixture.withContext(at: destination) { context in
			let request = NSFetchRequest<NSManagedObject>(entityName: ScrollbackDatabase.entityName)
			return try context.fetch(request).map { object in
				try (#require(ScrollbackEntry(managedObject: object)),
				     #require(object.value(forKey: ScrollbackAttribute.entryIdentifier.rawValue) as? NSNumber)
				     	.int64Value)
			}
		}
		#expect(original.count == 5)
		#expect(original.map(\.1).sorted() == [1, 100, 100, 100, 9000])
		let store = ScrollbackStore(filenameStore: ScrollbackFilenameFixture("fixture.sqlite").store)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		var cursor: ScrollbackRowCursor?
		var visited: [ScrollbackEntry] = []
		for _ in 0 ..< 6 {
			let outcome = await store.fetchOutcome(.init(viewIdentifier: "v1.0.7-fixture",
			                                             kind: .rowPage(
			                                             	before: cursor,
			                                             	fetchLimit: 1,
			                                             	limitToDate: nil
			                                             )))
			guard case let .page(rows) = outcome else { Issue.record("Row pagination failed"); return }
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
		var newLine = LogLine()
		newLine.messageBody = "appended"
		newLine.receivedAt = Date(timeIntervalSince1970: 4000)
		#expect(await store.writeLogLine(newLine.historicEntry(forView: "v1.0.7-fixture")) == .accepted)
		#expect(await store.close() == .saved)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		let appendedPage = await store.fetchOutcome(.init(viewIdentifier: "v1.0.7-fixture",
		                                                  kind: .rowPage(
		                                                  	before: nil,
		                                                  	fetchLimit: 10,
		                                                  	limitToDate: nil
		                                                  )))
		#expect(appendedPage.entries.first?.cursor?.insertionIdentifier == 9001)
		#expect(Set(original.map(\.0.data)).isSubset(of: Set(appendedPage.entries.map(\.data))))
		await store.setMaximumLineCount(4)
		guard case let .deleted(result) = await store.resize("v1.0.7-fixture")
		else { Issue.record("Retention failed"); return }
		#expect(result.deletedCount == 2)
		#expect(result.uniqueIdentifiers == ["old"])
		let retained = await store.fetchOutcome(
			.newestEntries(forView: "v1.0.7-fixture", fetchLimit: 10)
		).entries
		#expect(retained.count == 4)
		#expect(retained.filter { $0.uniqueIdentifier == "duplicate" }.count == 2)
		#expect(Set(retained.map(\.data)).isSubset(of: Set(appendedPage.entries.map(\.data))))
		await store.close()
	}
}
