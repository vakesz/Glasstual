import Foundation
import HistoricLogStoreKit
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

/// A filename store of the test's own, so a run neither reads nor writes the
/// preference the service keeps the real database's name in.
private nonisolated struct ScratchFilenameStore: HistoricLogFilenameStoring {
	private let storage = Locked<String?>(nil)

	var databaseFilename: String? {
		get { storage.value }
		nonmutating set { storage.set(newValue) }
	}
}

/// The client half. Records what the store said it truncated.
private final nonisolated class ClientRecorder: NSObject, HistoricLogClientProtocol {
	private let storage = Locked<[String]>([])

	var deletedIdentifiers: [String] {
		storage.value
	}

	func willDeleteUniqueIdentifiers(_ uniqueIdentifiers: [String], inView _: String) {
		storage.set(storage.value + uniqueIdentifiers)
	}
}

/// A live connection to a store, over a real anonymous `NSXPCListener`.
///
/// Everything NSXPC hands out is non-`Sendable`, so the listener, the
/// connection and the proxy are created in here and never leave: a test drives
/// the store by awaiting this actor, and ten of those awaits are ten XPC calls
/// in flight at once.
private actor StoreHarness {
	private let listener: NSXPCListener
	private let delegate: HistoricLogProcessDelegate
	private let connection: NSXPCConnection
	private let proxy: any HistoricLogServerProtocol
	private let recorder: ClientRecorder

	let directory: URL

	init() throws {
		directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("historic-log-\(UUID().uuidString)", isDirectory: true)

		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		listener = NSXPCListener.anonymous()
		delegate = HistoricLogProcessDelegate(filenameStore: ScratchFilenameStore())
		recorder = ClientRecorder()

		listener.delegate = delegate
		listener.resume()

		let serverInterface = NSXPCInterface(with: HistoricLogServerProtocol.self)

		guard HistoricLogInterface.configure(serverInterface) else {
			throw CocoaError(.coderInvalidValue)
		}

		connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
		connection.remoteObjectInterface = serverInterface
		connection.exportedInterface = NSXPCInterface(with: HistoricLogClientProtocol.self)
		connection.exportedObject = recorder
		connection.resume()

		guard let proxy = connection.remoteObjectProxy as? any HistoricLogServerProtocol else {
			throw CocoaError(.coderInvalidValue)
		}

		self.proxy = proxy
	}

	func shutdown() async {
		connection.invalidate()
		listener.invalidate()

		/* The store closes its Core Data stack when the invalidation reaches
		 it. Removing the directory before that lands leaves it writing into a
		 file that is no longer there, which Core Data is loud about. */
		try? await Task.sleep(for: .milliseconds(200), clock: .continuous)

		try? FileManager.default.removeItem(at: directory)
	}

	var deletedIdentifiers: [String] {
		recorder.deletedIdentifiers
	}

	func openDatabase() async -> Bool {
		let path = directory.path

		return await withCheckedContinuation { continuation in
			proxy.openDatabase(inDirectory: path) { continuation.resume(returning: $0) }
		}
	}

	func write(_ index: Int, inView view: String) {
		proxy.writeLogLine(
			LogLineXPC(
				logLineData: Data("line \(index)".utf8),
				uniqueIdentifier: "line-\(index)",
				viewIdentifier: view,
				sessionIdentifier: 1,
				creationDate: Date().timeIntervalSince1970
			)
		)
	}

	func save() async {
		await withCheckedContinuation { continuation in
			proxy.saveData { continuation.resume() }
		}
	}

	func forgetView(_ view: String) {
		proxy.forgetView(view)
	}

	func lineCount(inView view: String, limit: UInt = 100) async -> Int {
		await withCheckedContinuation { continuation in
			proxy.fetchEntries(forView: view, ascending: true, fetchLimit: limit, limitTo: nil) { entries in
				continuation.resume(returning: entries.count)
			}
		}
	}
}

/// The store under the traffic it actually sees: many XPC calls at once,
/// against the same exported object and the same ownership rules the service
/// itself uses.
@Suite("Historic log store over XPC", .serialized)
struct HistoricLogStoreConcurrencyTests {
	@Test("Ten fetches at once all see the lines that were written")
	func concurrentFetchesAllSeeTheWrites() async throws {
		let harness = try StoreHarness()

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

			return await group.reduce(into: [Int]()) { $0.append($1) }
		}

		#expect(results.count == 10)

		/* Every fetch is the same query against the same view, so they all have
		 to agree — a store that let two of them interleave would not. */
		#expect(Set(results) == [lineCount])

		await harness.shutdown()
	}

	@Test("A view that is forgotten reports its lines to the client and comes back empty")
	func forgettingAViewReportsAndEmptiesIt() async throws {
		let harness = try StoreHarness()

		#expect(await harness.openDatabase())

		let view = "view-\(UUID().uuidString)"

		for index in 0 ..< 5 {
			await harness.write(index, inView: view)
		}

		await harness.save()

		#expect(await harness.lineCount(inView: view) == 5)

		await harness.forgetView(view)

		/* forgetView is one way, so the fetch that follows it is what proves it
		 landed: the store answers XPC calls in order. */
		#expect(await harness.lineCount(inView: view) == 0)

		/* The deletion notice goes out through the client proxy the store was
		 handed, and comes back to this process asynchronously. */
		for _ in 0 ..< 50 where await harness.deletedIdentifiers.count < 5 {
			try await Task.sleep(for: .milliseconds(20), clock: .continuous)
		}

		#expect(await Set(harness.deletedIdentifiers) == Set((0 ..< 5).map { "line-\($0)" }))

		await harness.shutdown()
	}

	@Test("Two views written at once do not see each other's lines")
	func viewsAreIsolatedFromEachOther() async throws {
		let harness = try StoreHarness()

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
