/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Synchronization
import Testing

private nonisolated struct RetentionFilename: HistoricLogFilenameStoring { // nonisolated: value
	var databaseFilename: String? {
		get { "history.sqlite" }
		nonmutating set { Issue.record("Unexpected database replacement: \(newValue ?? "nil")") }
	}
}

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
@Suite("Historic log retention", .serialized)
struct HistoricLogRetentionTests {
	private func entry(_ id: String) -> HistoricLogEntry {
		HistoricLogEntry(
			logLineData: Data(id.utf8),
			uniqueIdentifier: id,
			viewIdentifier: "view",
			sessionIdentifier: 1,
			creationDate: 100
		)
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
		let store = HistoricLogStore(
			filenameStore: RetentionFilename(),
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
			#expect(await store.writeLogLine(entry("line-\(index)")) == .accepted)
		}
		// The pass the eleventh write armed is parked for the full half hour.
		#expect(await store.fetchEntries(forView: "view", ascending: true, fetchLimit: 100, limitToDate: nil)
			.count == 12)

		delay.withLock { $0 = .zero }
		await store.setMaximumLineCount(5)
		await passes.wait(for: 1)
		#expect(await store.fetchEntries(forView: "view", ascending: true, fetchLimit: 100, limitToDate: nil)
			.map(\.uniqueIdentifier) == (7 ..< 12).map { "line-\($0)" })

		/* Nothing lowers the limit again: the write alone has to be able to arm
		 the next pass, which it can only do if the finished one gave its slot
		 back. */
		#expect(await store.writeLogLine(entry("line-12")) == .accepted)
		await passes.wait(for: 2)
		#expect(await store.fetchEntries(forView: "view", ascending: true, fetchLimit: 100, limitToDate: nil)
			.map(\.uniqueIdentifier) == (8 ..< 13).map { "line-\($0)" })
		#expect(await store.close() == .saved)
	}
}
