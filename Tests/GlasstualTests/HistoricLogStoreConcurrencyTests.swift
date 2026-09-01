import Foundation
@testable import Glasstual
import Synchronization
import Testing

/// One value, shared by the store's isolation domain and the test's.
private final nonisolated class Locked<Value: Sendable>: Sendable {
	private let storage: Mutex<Value>

	init(_ value: Value) {
		storage = Mutex(value)
	}

	var value: Value {
		storage.withLock { $0 }
	}

	func set(_ value: Value) {
		storage.withLock { $0 = value }
	}
}

private nonisolated struct ScratchFilenameStore: HistoricLogFilenameStoring { // nonisolated: value
	private let storage = Locked<String?>(nil)

	var databaseFilename: String? {
		get { storage.value }
		nonmutating set { storage.set(newValue) }
	}
}

private actor DeletionRecorder {
	private(set) var identifiers: [String] = []

	func record(_ newIdentifiers: [String]) {
		identifiers.append(contentsOf: newIdentifiers)
	}
}

/// Drives the real in-process store while keeping temporary-file cleanup and
/// observation behind one actor.
private actor HistoricLogStoreHarness {
	private let store: HistoricLogStore
	private let recorder: DeletionRecorder

	let directory: URL

	init() throws {
		directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("historic-log-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		let recorder = DeletionRecorder()
		self.recorder = recorder
		store = HistoricLogStore(filenameStore: ScratchFilenameStore()) { identifiers, _ in
			await recorder.record(identifiers)
		}
	}

	func shutdown() async {
		await store.close()
		try? FileManager.default.removeItem(at: directory)
	}

	var deletedIdentifiers: [String] {
		get async { await recorder.identifiers }
	}

	func openDatabase() async -> Bool {
		await store.openDatabase(inDirectory: directory.path)
	}

	func write(_ index: Int, inView view: String) async {
		await store.writeLogLine(HistoricLogEntry(
			logLineData: Data("line \(index)".utf8),
			uniqueIdentifier: "line-\(index)",
			viewIdentifier: view,
			sessionIdentifier: 1,
			creationDate: Date().timeIntervalSince1970
		))
	}

	func save() async {
		await store.saveData()
	}

	func forgetView(_ view: String) async {
		await store.forgetView(view)
	}

	func lineCount(inView view: String, limit: UInt = 100) async -> Int {
		await store.fetchEntries(
			forView: view,
			ascending: true,
			fetchLimit: limit,
			limitToDate: nil
		).count
	}
}

@Suite("Historic log store", .serialized)
struct HistoricLogStoreConcurrencyTests {
	@Test("Ten concurrent fetches all see the lines that were written")
	func concurrentFetchesAllSeeTheWrites() async throws {
		let harness = try HistoricLogStoreHarness()
		#expect(await harness.openDatabase())

		let view = "view-\(UUID().uuidString)"
		let lineCount = 40
		for index in 0 ..< lineCount {
			await harness.write(index, inView: view)
		}
		await harness.save()

		let results = await withTaskGroup(of: Int.self) { group in
			for _ in 0 ..< 10 {
				group.addTask { await harness.lineCount(inView: view, limit: UInt(lineCount)) }
			}
			var values: [Int] = []
			for await value in group {
				values.append(value)
			}
			return values
		}

		#expect(results.count == 10)
		#expect(Set(results) == [lineCount])
		await harness.shutdown()
	}

	@Test("Forgetting a view reports its lines and empties it")
	func forgettingAViewReportsAndEmptiesIt() async throws {
		let harness = try HistoricLogStoreHarness()
		#expect(await harness.openDatabase())

		let view = "view-\(UUID().uuidString)"
		for index in 0 ..< 5 {
			await harness.write(index, inView: view)
		}
		await harness.save()
		#expect(await harness.lineCount(inView: view) == 5)

		await harness.forgetView(view)

		#expect(await harness.lineCount(inView: view) == 0)
		#expect(await Set(harness.deletedIdentifiers) == Set((0 ..< 5).map { "line-\($0)" }))
		await harness.shutdown()
	}

	@Test("Two views written at once do not see each other's lines")
	func viewsAreIsolatedFromEachOther() async throws {
		let harness = try HistoricLogStoreHarness()
		#expect(await harness.openDatabase())

		let first = "view-\(UUID().uuidString)"
		let second = "view-\(UUID().uuidString)"
		for index in 0 ..< 12 {
			await harness.write(index, inView: index.isMultiple(of: 2) ? first : second)
		}
		await harness.save()

		async let firstCount = harness.lineCount(inView: first)
		async let secondCount = harness.lineCount(inView: second)
		#expect(await firstCount == 6)
		#expect(await secondCount == 6)
		await harness.shutdown()
	}
}
