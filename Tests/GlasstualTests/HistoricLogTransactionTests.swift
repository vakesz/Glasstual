/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CoreData
@testable import Glasstual
import Testing

private actor HistoryOperationGate {
	private var blocked: CheckedContinuation<Void, Never>?
	private var entered = false
	private var observer: CheckedContinuation<Void, Never>?
	func wait() async {
		entered = true
		observer?.resume()
		observer = nil
		await withCheckedContinuation { blocked = $0 }
	}

	func ready() async {
		if !entered {
			await withCheckedContinuation { observer = $0 }
		}
	}

	func release() {
		blocked?.resume(); blocked = nil
	}
}

/// Counts the saves the store makes once a test has started listening, and
/// lets the test wait for the first of them.
private actor SaveSignal {
	private var listening = false
	private var saves = 0
	private var waiting: CheckedContinuation<Void, Never>?

	func listen() {
		listening = true
	}

	func record() {
		guard listening else { return }
		saves += 1
		waiting?.resume()
		waiting = nil
	}

	func firstSave() async {
		guard saves == 0 else { return }
		await withCheckedContinuation { waiting = $0 }
	}
}

@MainActor
@Suite("Historic store transactions", .serialized)
struct HistoricLogTransactionTests {
	private func directory() throws -> URL {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	private func entry(_ id: String) -> HistoricLogEntry {
		HistoricLogEntry(
			logLineData: Data(id.utf8),
			uniqueIdentifier: id,
			viewIdentifier: "view",
			sessionIdentifier: 1,
			creationDate: 100
		)
	}

	@Test("Reset and forget serialize later writes instead of resetting their context", arguments: [false, true])
	func removalCannotEraseLaterWrite(forget: Bool) async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let gate = HistoryOperationGate()
		let store = HistoricLogStore(filenameStore: HistoricLogFilenameFixture(), willPerform: { operation in
			switch operation {
			case .reset, .forget: await gate.wait()
			default: break
			}
		})
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		#expect(await store.writeLogLine(entry("old")) == .accepted)
		let removal = Task {
			if forget {
				await store.forgetView("view")
			} else {
				await store.resetData(forView: "view")
			}
		}
		await gate.ready()
		let writer = Task { await store.writeLogLine(entry("new")) }
		while await store.pendingOperationCount == 0 {
			await Task.yield()
		}
		await gate.release()
		guard case let .deleted(result) = await removal.value else { Issue.record("Removal failed"); return }
		#expect(result.deletedCount == 1)
		#expect(result.uniqueIdentifiers == ["old"])
		#expect(await writer.value == .accepted)
		#expect(await store.close() == .saved)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		let rows = await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 10)).entries
		#expect(rows.map(\.data) == [entry("new").data])
		await store.close()
	}

	@Test("Close drains admitted writes and rejects later admission")
	func closeAdmission() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let gate = HistoryOperationGate()
		let store = HistoricLogStore(filenameStore: HistoricLogFilenameFixture(), willPerform: { operation in
			if case .write = operation {
				await gate.wait()
			}
		})
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		let writer = Task { await store.writeLogLine(entry("admitted")) }
		await gate.ready()
		let close = Task { await store.close() }
		while await store.pendingOperationCount == 0 {
			await Task.yield()
		}
		#expect(await store.writeLogLine(entry("late")) == .unavailable)
		await gate.release()
		#expect(await writer.value == .accepted)
		#expect(await close.value == .saved)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		#expect(await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 10)).entries
			.map(\.uniqueIdentifier) == ["admitted"])
		await store.close()
	}

	@Test("A close that fails to save leaves the store saving on its own again", .timeLimit(.minutes(1)))
	func failedCloseRearmsPeriodicSaves() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let context = try HistoricLogDatabase.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let signal = SaveSignal()
		let store = HistoricLogStore(
			filenameStore: HistoricLogFilenameFixture(),
			makeStack: { _ in context },
			saveInterval: .milliseconds(20),
			willPerform: { operation in
				if case .save = operation {
					await signal.record()
				}
			}
		)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		let row = entry("pending")
		/* Inserted and made invalid in one block on the context's queue, so no
		 periodic save can land between the two and store the row. */
		try await context.perform {
			HistoricLogDatabase.insert(row, in: context, entryIdentifier: 1)
			let inserted = try #require(context.insertedObjects.first)
			inserted.setValue(nil, forKey: HistoricLogAttribute.sessionIdentifier.rawValue)
		}
		if case .failed = await store.close() {} else {
			Issue.record("Close unexpectedly saved an invalid row")
		}
		await signal.listen()
		await signal.firstSave()
		try await context.perform {
			let inserted = try #require(context.insertedObjects.first)
			inserted.setValue(
				NSNumber(value: row.sessionIdentifier),
				forKey: HistoricLogAttribute.sessionIdentifier.rawValue
			)
		}
		#expect(await store.close() == .saved)
	}

	@Test("Failed save, deletion and close retain the accepted archive for repair")
	func failedTransactionsRetainState() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let context = try HistoricLogDatabase.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let store = HistoricLogStore(filenameStore: HistoricLogFilenameFixture(), makeStack: { _ in context })
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		let row = entry("pending")
		#expect(await store.writeLogLine(row) == .accepted)
		try await context.perform {
			let inserted = try #require(context.insertedObjects.first)
			inserted.setValue(nil, forKey: HistoricLogAttribute.sessionIdentifier.rawValue)
		}
		if case .failed = await store.saveData() {} else {
			Issue.record("Save unexpectedly succeeded")
		}
		switch await store.resetData(forView: "view") {
		case .failed: break
		default: Issue.record("Failed write was discarded by reset")
		}
		if case .failed = await store.close() {} else {
			Issue.record("Failed close dropped pending state")
		}
		try await context.perform {
			let inserted = try #require(context.insertedObjects.first)
			#expect(inserted.value(forKey: HistoricLogAttribute.logLineData.rawValue) as? Data == row.data)
			inserted.setValue(
				NSNumber(value: row.sessionIdentifier),
				forKey: HistoricLogAttribute.sessionIdentifier.rawValue
			)
		}
		#expect(await store.saveData() == .saved)
		#expect(await store.close() == .saved)
		let reopened = HistoricLogStore(filenameStore: HistoricLogFilenameFixture())
		#expect(await reopened.openDatabase(inDirectory: directory.path).isOpen)
		#expect(await reopened.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 10)).entries
			.map(\.data) == [row.data])
		await reopened.close()
	}
}
