/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CoreData
import Foundation
@testable import Glasstual
import Testing

/// Names the database file, so the test can seed the store before the real
/// store opens it and read it back afterwards.
private nonisolated struct FixedFilenameStore: HistoricLogFilenameStoring { // nonisolated: value
	let filename: String

	var databaseFilename: String? {
		get { filename }
		nonmutating set {
			Issue.record("The store renamed its database to \(newValue ?? "nothing").")
		}
	}
}

/// Rows written before the insert started storing the line's own time carry the
/// moment they reached the database instead, so they sort against newer rows by
/// a different clock. These cover the one-off pass that corrects them.
@Suite("Historic log re-stamp", .serialized)
struct HistoricLogRestampTests {
	private static let view = "restamp-view"

	private func makeDirectory() throws -> URL {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("historic-log-restamp-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		return directory
	}

	/// A row in the shape an earlier version wrote: the archived line carries
	/// the time it was said, and the column carries the time it was stored.
	private func rowWrittenByAnEarlierVersion(
		body: String,
		said: Date,
		stored: Date
	) -> (entry: HistoricLogEntry, receivedAt: Date) {
		var line = LogLine()
		line.receivedAt = said
		line.messageBody = body

		let archived = line.historicEntry(forView: Self.view)

		return (
			HistoricLogEntry(
				logLineData: archived.data,
				uniqueIdentifier: archived.uniqueIdentifier,
				viewIdentifier: Self.view,
				sessionIdentifier: archived.sessionIdentifier,
				creationDate: stored.timeIntervalSince1970
			),
			said
		)
	}

	private func seed(_ rows: [HistoricLogEntry], at url: URL, startingAt firstIdentifier: UInt) async throws {
		let context = try HistoricLogDatabase.makeStack(at: url)

		await context.perform {
			for (offset, row) in rows.enumerated() {
				HistoricLogDatabase.insert(
					row,
					in: context,
					entryIdentifier: firstIdentifier + UInt(offset)
				)
			}

			HistoricLogDatabase.quickSave(context)
		}
	}

	private func storedCreationDates(at url: URL) async throws -> [String: TimeInterval] {
		let context = try HistoricLogDatabase.makeStack(at: url)

		return await context.perform {
			HistoricLogDatabase.fetchEntries(
				in: context,
				viewIdentifier: Self.view,
				ascending: true,
				fetchLimit: 0,
				limitToDate: nil
			)
			.reduce(into: [:]) { result, entry in
				result[entry.uniqueIdentifier] = entry.creationDate
			}
		}
	}

	private func restampIsOutstanding(at url: URL) async throws -> Bool {
		let context = try HistoricLogDatabase.makeStack(at: url)

		return await context.perform {
			HistoricLogDatabase.needsEntryCreationDateRestamp(in: context)
		}
	}

	@Test("Opening a store written by an earlier version re-stamps its rows once")
	func openingRestampsStoredRowsOnce() async throws {
		let directory = try makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let filename = "logControllerHistoricLog_\(UUID().uuidString).sqlite"
		let url = directory.appendingPathComponent(filename, isDirectory: false)

		let stored = Date()
		let rows = (0 ..< 3).map { index in
			rowWrittenByAnEarlierVersion(
				body: "line \(index)",
				said: stored.addingTimeInterval(TimeInterval(-3600 * (index + 1))),
				stored: stored
			)
		}
		try await seed(rows.map(\.entry), at: url, startingAt: 1)

		#expect(try await restampIsOutstanding(at: url))

		let store = HistoricLogStore(filenameStore: FixedFilenameStore(filename: filename))
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		await store.close()

		let restamped = try await storedCreationDates(at: url)
		for row in rows {
			let stamp = try #require(restamped[row.entry.uniqueIdentifier])
			#expect(abs(stamp - row.receivedAt.timeIntervalSince1970) < 0.001)
		}

		#expect(try await restampIsOutstanding(at: url) == false)
	}

	@Test("A second open leaves the stamps it finds alone")
	func secondOpenLeavesStampsAlone() async throws {
		let directory = try makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let filename = "logControllerHistoricLog_\(UUID().uuidString).sqlite"
		let url = directory.appendingPathComponent(filename, isDirectory: false)

		let stored = Date()
		let first = rowWrittenByAnEarlierVersion(
			body: "first",
			said: stored.addingTimeInterval(-7200),
			stored: stored
		)
		try await seed([first.entry], at: url, startingAt: 1)

		let store = HistoricLogStore(filenameStore: FixedFilenameStore(filename: filename))
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		await store.close()

		/* Written after the flag was recorded, so it stands in for a row the
		 pass would have corrected had it run a second time. */
		let late = rowWrittenByAnEarlierVersion(
			body: "late",
			said: stored.addingTimeInterval(-10800),
			stored: stored
		)
		try await seed([late.entry], at: url, startingAt: 2)

		let reopened = HistoricLogStore(filenameStore: FixedFilenameStore(filename: filename))
		#expect(await reopened.openDatabase(inDirectory: directory.path).isOpen)
		await reopened.close()

		let stamps = try await storedCreationDates(at: url)
		let lateStamp = try #require(stamps[late.entry.uniqueIdentifier])
		#expect(abs(lateStamp - stored.timeIntervalSince1970) < 0.001)

		let firstStamp = try #require(stamps[first.entry.uniqueIdentifier])
		#expect(abs(firstStamp - first.receivedAt.timeIntervalSince1970) < 0.001)
	}
}
