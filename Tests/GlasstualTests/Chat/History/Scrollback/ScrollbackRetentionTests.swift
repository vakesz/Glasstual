// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Synchronization
import Testing

/// Signals each retention pass as it takes the store's lane. A caller that
/// waits for the count it expects is behind that pass in the lane, so the work
/// it reads back has finished.
private actor RetentionPassCounter {
	private var passes = 0
	private var waiting: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

	func record() {
		passes += 1
		let ready = waiting.filter { $0.target <= passes }
		waiting.removeAll { $0.target <= passes }
		for entry in ready {
			entry.continuation.resume()
		}
	}

	func wait(for target: Int) async {
		guard passes < target else { return }
		await withCheckedContinuation { waiting.append((target, $0)) }
	}
}

@MainActor
@Suite("Scrollback retention", .serialized)
struct ScrollbackRetentionTests {
	@Test("Fetching a reopened view schedules retention without a new message", .timeLimit(.minutes(1)))
	func reopenedViewSchedulesRetention() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let passes = RetentionPassCounter()
		let store = ScrollbackStore(
			filenameSetting: ScrollbackFilenameFixture().store,
			resizeDelay: { .zero },
			willPerform: { operation in
				if case .resize = operation {
					await passes.record()
				}
			}
		)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		await store.setMaximumLineCount(100)
		for index in 0 ..< 5 {
			#expect(await store.writeChatLine(entry("line-\(index)")) == .accepted)
		}
		#expect(await store.close() == .saved)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		await store.setMaximumLineCount(2)
		_ = await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 10))
		await passes.wait(for: 1)
		#expect(await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 10)).entries.count == 2)
		#expect(await store.close() == .saved)
	}

	private func entry(_ id: String, date: TimeInterval = 100) -> ScrollbackEntry {
		ScrollbackEntry(
			lineData: Data(id.utf8),
			uniqueIdentifier: id,
			viewIdentifier: "view",
			sessionIdentifier: 1,
			creationDate: date
		)
	}

	/** A server-history page is written after the live lines it is older than,
	 so its rows carry the highest insertion identifiers. Retention has to agree
	 with the reads about which lines are oldest, or it prunes the conversation
	 the reader just had and keeps the page they scrolled back to. */
	@Test("Retention prunes by each line's own time, not by the order rows were inserted",
	      .timeLimit(.minutes(1)))
	func retentionPrunesByLineTime() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString, isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture().store, resizeDelay: { .seconds(1800) })
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		await store.setMaximumLineCount(3)
		let rows: [(String, TimeInterval)] = [
			("live-0", 1000), ("live-1", 1001), ("live-2", 1002),
			("history-0", 10), ("history-1", 11), ("history-2", 12),
		]
		for (identifier, date) in rows {
			#expect(await store.writeChatLine(entry(identifier, date: date)) == .accepted)
		}

		guard case let .deleted(result) = await store.resize("view") else {
			Issue.record("Retention failed")
			return
		}
		#expect(result.deletedCount == 3)
		#expect(result.uniqueIdentifiers == ["history-0", "history-1", "history-2"])
		let retained = await store.fetchOutcome(ScrollbackFetchRequest(
			viewIdentifier: "view",
			kind: .rowPage(before: nil, fetchLimit: 10, limitToDate: nil)
		)).entries
		#expect(retained.map(\.uniqueIdentifier) == ["live-2", "live-1", "live-0"])
		#expect(await store.close() == .saved)
	}

	/** A pass is scheduled once and waits up to half an hour, so the limit it
	 was armed for has to be able to change under it, and the slot it holds has
	 to come back afterwards. Both are observed here: a lowered limit prunes
	 without waiting for the pass that was already parked, and the write that
	 follows arms a pass of its own. */
	@Test("A lowered limit retires the waiting pass, and the pass releases its slot",
	      .timeLimit(.minutes(1)))
	func loweringTheLimitPrunesAndLeavesTheSlotFree() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString, isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let delay = Mutex<Duration>(.seconds(1800))
		let passes = RetentionPassCounter()
		let store = ScrollbackStore(
			filenameSetting: ScrollbackFilenameFixture().store,
			resizeDelay: { delay.withLock { $0 } },
			willPerform: { operation in
				if case .resize = operation {
					await passes.record()
				}
			}
		)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		await store.setMaximumLineCount(10)
		for index in 0 ..< 12 {
			#expect(await store.writeChatLine(entry("line-\(index)")) == .accepted)
		}
		// The pass the eleventh write armed is parked for the full half hour.
		#expect(await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 100)).entries
			.count == 12)

		delay.withLock { $0 = .zero }
		await store.setMaximumLineCount(5)
		await passes.wait(for: 1)
		#expect(await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 100)).entries
			.map(\.uniqueIdentifier) == (7 ..< 12).reversed().map { "line-\($0)" })

		/* Nothing lowers the limit again: the write alone has to be able to arm
		 the next pass, which it can only do if the finished one gave its slot
		 back. */
		#expect(await store.writeChatLine(entry("line-12")) == .accepted)
		await passes.wait(for: 2)
		#expect(await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 100)).entries
			.map(\.uniqueIdentifier) == (8 ..< 13).reversed().map { "line-\($0)" })
		#expect(await store.close() == .saved)
	}
}
