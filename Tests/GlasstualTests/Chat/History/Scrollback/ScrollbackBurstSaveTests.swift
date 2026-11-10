// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreData
@testable import Glasstual
import Testing

/// Counts the saves the store begins and lets a test wait for the next one.
private actor SaveCounter {
	private(set) var saves = 0
	private var waiting: CheckedContinuation<Void, Never>?

	func record() {
		saves += 1
		waiting?.resume()
		waiting = nil
	}

	func nextSave(after count: Int) async {
		guard saves <= count else { return }
		await withCheckedContinuation { waiting = $0 }
	}
}

/// Holds the reason a save reported, and lets a test wait for it.
private actor FailureRecorder {
	private(set) var reasons: [String] = []
	private var waiting: CheckedContinuation<Void, Never>?

	func record(_ reason: String) {
		reasons.append(reason)
		waiting?.resume()
		waiting = nil
	}

	func first() async {
		guard reasons.isEmpty else { return }
		await withCheckedContinuation { waiting = $0 }
	}
}

/** Rows are saved after a short delay or a batch, so a busy channel does not
 hold its whole backlog in Core Data's unsaved objects until the slow loop. */
@MainActor
@Suite("Scrollback burst saves", .serialized)
struct ScrollbackBurstSaveTests {
	private func directory() throws -> URL {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	private func entry(_ id: String) -> ScrollbackEntry {
		ScrollbackEntry(
			lineData: Data(id.utf8),
			uniqueIdentifier: id,
			viewIdentifier: "view",
			sessionIdentifier: 1,
			creationDate: 100
		)
	}

	private func hasUnsavedChanges(_ context: NSManagedObjectContext) async -> Bool {
		await context.perform { context.hasChanges }
	}

	@Test("A batch of rows is saved at once", .timeLimit(.minutes(1)))
	func rowThresholdSavesImmediately() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let context = try ScrollbackQueries.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let counter = SaveCounter()
		let store = ScrollbackStore(
			filenameSetting: ScrollbackFilenameFixture().store,
			makeStack: { _ in context },
			saveInterval: .seconds(3600),
			saveRowThreshold: 3,
			saveDelay: .seconds(3600),
			willPerform: { operation in
				if case .save = operation {
					await counter.record()
				}
			}
		)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		for id in ["a", "b", "c"] {
			#expect(await store.writeChatLine(entry(id)) == .accepted)
		}
		await counter.nextSave(after: 0)
		#expect(await hasUnsavedChanges(context) == false)
		#expect(await store.close() == .saved)
		try await ScrollbackFixture.close(context)
	}

	@Test("A few rows are saved after the delay", .timeLimit(.minutes(1)))
	func delaySavesAFewRows() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let context = try ScrollbackQueries.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let counter = SaveCounter()
		let store = ScrollbackStore(
			filenameSetting: ScrollbackFilenameFixture().store,
			makeStack: { _ in context },
			saveInterval: .seconds(3600),
			saveRowThreshold: 1000,
			saveDelay: .milliseconds(30),
			willPerform: { operation in
				if case .save = operation {
					await counter.record()
				}
			}
		)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		#expect(await store.writeChatLine(entry("a")) == .accepted)
		await counter.nextSave(after: 0)
		#expect(await hasUnsavedChanges(context) == false)
		#expect(await store.close() == .saved)
		try await ScrollbackFixture.close(context)
	}

	@Test("Nothing is saved while nothing has been written", .timeLimit(.minutes(1)))
	func idleStoreDoesNotSave() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let context = try ScrollbackQueries.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let counter = SaveCounter()
		let store = ScrollbackStore(
			filenameSetting: ScrollbackFilenameFixture().store,
			makeStack: { _ in context },
			saveInterval: .seconds(3600),
			saveRowThreshold: 2,
			saveDelay: .milliseconds(10),
			willPerform: { operation in
				if case .save = operation {
					await counter.record()
				}
			}
		)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		try await Task.sleep(for: .milliseconds(150))
		#expect(await counter.saves == 0)
		#expect(await store.close() == .saved)
		try await ScrollbackFixture.close(context)
	}

	/// A deletion saves what is pending before it deletes, so the rows it
	/// committed are not counted again toward the next batch.
	@Test("A deletion resets the count of rows waiting for a save", .timeLimit(.minutes(1)))
	func deletionResetsTheRowCount() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let context = try ScrollbackQueries.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let counter = SaveCounter()
		let store = ScrollbackStore(
			filenameSetting: ScrollbackFilenameFixture().store,
			makeStack: { _ in context },
			saveInterval: .seconds(3600),
			saveRowThreshold: 3,
			saveDelay: .seconds(3600),
			willPerform: { operation in
				if case .save = operation {
					await counter.record()
				}
			}
		)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		for id in ["a", "b"] {
			#expect(await store.writeChatLine(entry(id)) == .accepted)
		}
		if case .deleted = await store.resetData(forView: "view") {} else {
			Issue.record("The deletion did not run")
		}
		#expect(await store.writeChatLine(entry("c")) == .accepted)
		try await Task.sleep(for: .milliseconds(150))
		#expect(await counter.saves == 0)
		#expect(await store.close() == .saved)
		try await ScrollbackFixture.close(context)
	}

	@Test("A burst save that fails is reported with its reason", .timeLimit(.minutes(1)))
	func failedBurstSaveIsReported() async throws {
		let directory = try directory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let context = try ScrollbackQueries.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let recorder = FailureRecorder()
		let store = ScrollbackStore(
			filenameSetting: ScrollbackFilenameFixture().store,
			makeStack: { _ in context },
			saveInterval: .seconds(3600),
			saveRowThreshold: 2,
			saveDelay: .seconds(3600),
			saveFailureHandler: { reason in await recorder.record(reason) }
		)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		let row = entry("pending")
		#expect(await store.writeChatLine(row) == .accepted)
		try await context.perform {
			let inserted = try #require(context.insertedObjects.first)
			inserted.setValue(nil, forKey: ScrollbackAttribute.sessionID.rawValue)
		}
		#expect(await store.writeChatLine(entry("second")) == .accepted)
		await recorder.first()
		#expect(await recorder.reasons.first?.isEmpty == false)
		await context.perform {
			for inserted in context.insertedObjects where inserted.value(forKey: ScrollbackAttribute.sessionID.rawValue) == nil {
				inserted.setValue(
					NSNumber(value: row.sessionIdentifier),
					forKey: ScrollbackAttribute.sessionID.rawValue
				)
			}
		}
		#expect(await store.close() == .saved)
		try await ScrollbackFixture.close(context)
	}
}
