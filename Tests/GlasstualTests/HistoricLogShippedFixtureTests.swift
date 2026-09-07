/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CoreData
@testable import Glasstual
import Testing

private nonisolated struct ShippedFixtureFilename: HistoricLogFilenameStoring { // nonisolated: value
	var databaseFilename: String? {
		get { "fixture.sqlite" }
		nonmutating set { Issue.record("The fixture was replaced: \(newValue ?? "nil")") }
	}
}

@MainActor
@Suite("v1.0.7 model-3 history fixture", .serialized)
struct HistoricLogShippedFixtureTests {
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
		let context = try HistoricLogDatabase.makeStack(at: destination)
		let original = try await context.perform {
			let request = NSFetchRequest<NSManagedObject>(entityName: HistoricLogDatabase.entityName)
			return try context.fetch(request).map { object in
				try (#require(HistoricLogEntry(managedObject: object)),
				     #require(object.value(forKey: HistoricLogAttribute.entryIdentifier.rawValue) as? NSNumber)
				     	.int64Value)
			}
		}
		#expect(original.count == 5)
		#expect(original.map(\.1).sorted() == [1, 100, 100, 100, 9000])
		let decoded = original.compactMap { LogLine(data: $0.0.data) }
		#expect(Set(decoded.map(\.messageBody)) == ["older", "duplicate-a", "duplicate-b", "duplicate-c", "newer"])
		#expect(decoded
			.allSatisfy { $0.sessionIdentifier == 77 && $0.nickname == "alice" && $0.reactions == ["+1": ["bob"]] })
		let store = HistoricLogStore(filenameStore: ShippedFixtureFilename())
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		var cursor: HistoricLogRowCursor?
		var visited: [HistoricLogEntry] = []
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
		let retained = await store.fetchEntries(
			forView: "v1.0.7-fixture",
			ascending: true,
			fetchLimit: 10,
			limitToDate: nil
		)
		#expect(retained.count == 4)
		#expect(retained.filter { $0.uniqueIdentifier == "duplicate" }.count == 2)
		#expect(Set(retained.map(\.data)).isSubset(of: Set(appendedPage.entries.map(\.data))))
		await store.close()
	}
}
