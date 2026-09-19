// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Holds every fetch at the door until the test lets them through, so the
/// order requests were made in is the only thing the queue can go by.
private actor FetchGate {
	private var isOpen: Bool
	private var waiting: [CheckedContinuation<Void, Never>] = []

	init(isOpen: Bool = false) {
		self.isOpen = isOpen
	}

	func wait() async {
		guard isOpen == false else {
			return
		}

		await withCheckedContinuation { continuation in
			waiting.append(continuation)
		}
	}

	func open() {
		isOpen = true

		for continuation in waiting {
			continuation.resume()
		}

		waiting.removeAll()
	}
}

private actor ScrollbackTestService {
	/// The storage value the session drives, forwarding to this service.
	nonisolated var storage: ScrollbackStoreOperations { // nonisolated: pure
		ScrollbackStoreOperations(
			openDatabase: { await self.openDatabase(inDirectory: $0) },
			close: { await self.close() },
			setMaximumLineCount: { await self.setMaximumLineCount($0) },
			writeChatLine: { await self.writeChatLine($0) },
			forgetView: { await self.forgetView($0) },
			resetData: { await self.resetData(forView: $0) },
			saveData: { await self.saveData() },
			fetchOutcome: { await self.fetchOutcome($0) }
		)
	}

	let probe: IsolationProbe
	let openGate = FetchGate()
	/// Open unless a test asked to hold pages at the door.
	let fetchGate: FetchGate
	private(set) var openCount = 0
	private(set) var closeCount = 0
	private(set) var fetchCount = 0
	/// What the store was asked to do, in the order it was asked.
	private(set) var operations: [String] = []
	private(set) var entries: [ScrollbackEntry] = []
	private var outcome = ScrollbackOpenOutcome.failed(reason: "Injected open failure")
	private var fetchFailure: ScrollbackFetchFailure?
	private var directory: String? = "/injected/history"

	init(probe: IsolationProbe, holdsFetches: Bool = false) {
		self.probe = probe
		fetchGate = FetchGate(isOpen: !holdsFetches)
	}

	func setOutcome(_ outcome: ScrollbackOpenOutcome) {
		self.outcome = outcome
	}

	func setFetchFailure(_ failure: ScrollbackFetchFailure?) {
		fetchFailure = failure
	}

	func setDirectory(_ directory: String?) {
		self.directory = directory
	}

	func databaseDirectory() -> String? {
		directory
	}

	func openDatabase(inDirectory databaseDirectory: String) async -> ScrollbackOpenOutcome {
		#expect(databaseDirectory == "/injected/history")
		openCount += 1
		await probe.record("open")
		await openGate.wait()
		return outcome
	}

	func close() -> ScrollbackSaveOutcome {
		closeCount += 1
		return .saved
	}

	func setMaximumLineCount(_: UInt) {}
	func writeChatLine(_ chatLine: ScrollbackEntry) -> ScrollbackWriteOutcome {
		operations.append("write \(chatLine.uniqueIdentifier)")
		entries.append(chatLine)
		return .accepted
	}

	func forgetView(_ view: String) -> ScrollbackDeletionOutcome {
		operations.append("forget")
		return remove(view)
	}

	func resetData(forView view: String) -> ScrollbackDeletionOutcome {
		operations.append("reset")
		return remove(view)
	}

	private func remove(_ view: String) -> ScrollbackDeletionOutcome {
		let removed = entries.filter { $0.viewIdentifier == view }
		entries.removeAll { $0.viewIdentifier == view }
		return .deleted(.init(deletedCount: UInt(removed.count), uniqueIdentifiers: removed.map(\.uniqueIdentifier)))
	}

	func saveData() -> ScrollbackSaveOutcome {
		.saved
	}

	func fetchOutcome(_ request: ScrollbackFetchRequest) async -> ScrollbackFetchOutcome {
		fetchCount += 1
		operations.append("fetch")
		switch request.kind {
		case .before: await probe.record("before")
		case let .rowPage(cursor, _, _): await probe.record(cursor == nil ? "newest" : "before")
		}
		await fetchGate.wait()
		return fetchFailure.map(ScrollbackFetchOutcome.failed) ?? .page(entries)
	}
}

@Suite("Scrollback session")
struct ScrollbackSessionTests {
	@Test("Read failures and empty pages remain distinct through the production session")
	func typedReadFailureCanBeRetried() async {
		let service = ScrollbackTestService(probe: IsolationProbe())
		await service.setOutcome(.opened)
		await service.openGate.open()
		let session = ScrollbackSession(store: service.storage, databaseDirectory: { await service.databaseDirectory() },
		                                reportFailure: { _ in Issue.record("The database opened successfully") })
		let request = Self.request(view: "a", label: "a1")
		await service.setFetchFailure(.read("Injected read failure"))
		guard case .failed(.read("Injected read failure")) = await session.fetchOutcome(request) else {
			Issue.record("A failed read was converted to an empty page")
			await session.prepareForTermination()
			return
		}
		#expect(await session.fetchOutcome(request).entries.isEmpty)
		await service.setFetchFailure(nil)
		guard case let .page(entries) = await session.fetchOutcome(request) else {
			Issue.record("A read failure prevented retry")
			await session.prepareForTermination()
			return
		}
		#expect(entries.isEmpty)
		#expect(await service.openCount == 1)
		await session.prepareForTermination()
	}

	@Test("Cancelling a caller answers cancellation rather than exhaustion")
	func cancelledFetchHasTypedOutcome() async {
		let service = ScrollbackTestService(probe: IsolationProbe(), holdsFetches: true)
		await service.setOutcome(.opened)
		await service.openGate.open()
		let session = Self.session(on: service)
		let task = Task { await session.fetchOutcome(Self.request(view: "a", label: "a1")) }
		while await service.fetchCount == 0 {
			await Task.yield()
		}
		task.cancel()
		await service.fetchGate.open()
		if case .cancelled = await task.value {} else {
			Issue.record("Cancellation was reported as a page")
		}
		await session.prepareForTermination()
	}

	/** The changes and the page a caller asks for in one turn, in that order.

	 The queue is the only thing that puts them in order: the write, the clear and
	 the write behind it reach the store from three different tasks, and a page
	 asked for last has to hold what the writes ahead of it stored. */
	@Test("Writes, a clear and a page run in the order they were asked for")
	func changesRunInTheOrderTheyWereAskedFor() async {
		let service = ScrollbackTestService(probe: IsolationProbe())
		await service.setOutcome(.opened)
		await service.openGate.open()
		let session = Self.session(on: service)
		session.write(Self.entry("first")) { #expect($0 == .accepted) }
		session.write(Self.entry("second")) { #expect($0 == .accepted) }
		_ = session.removeHistory(forView: "a", forget: false) { outcome in
			guard case let .deleted(result) = outcome else {
				Issue.record("The clear did not run")
				return
			}
			#expect(result.uniqueIdentifiers == ["first", "second"])
		}
		session.write(Self.entry("third")) { #expect($0 == .accepted) }
		let page = await session.fetchOutcome(Self.request(view: "a", label: "a1"))
		#expect(page.entries.map(\.uniqueIdentifier) == ["third"])
		#expect(await service.operations == ["write first", "write second", "reset", "write third", "fetch"])
		await session.prepareForTermination()
	}

	/// A session on `service`, whose database opens and whose failures are a test
	/// failure.
	private static func session(on service: ScrollbackTestService) -> ScrollbackSession {
		ScrollbackSession(
			store: service.storage,
			databaseDirectory: { await service.databaseDirectory() },
			reportFailure: { Issue.record(Comment(rawValue: $0)) }
		)
	}

	private static func entry(_ identifier: String) -> ScrollbackEntry {
		ScrollbackEntry(
			lineData: Data(),
			uniqueIdentifier: identifier,
			viewIdentifier: "a",
			sessionIdentifier: 0,
			creationDate: 0
		)
	}

	/// A request labelled by the line number it asks for, which is what the
	/// recorder reads back.
	private static func request(view: String, label: String) -> ScrollbackFetchRequest {
		ScrollbackFetchRequest(
			viewIdentifier: view,
			kind: .before(uniqueIdentifier: label, fetchLimit: 1, limitToDate: nil)
		)
	}

	@Test(
		"Failed opens report once across concurrent and serial operations until explicit retry",
		arguments: [false, true]
	)
	func failedOpenRequiresExplicitRetry(withReason: Bool) async {
		let probe = IsolationProbe()
		let service = ScrollbackTestService(probe: probe)
		let reason = withReason ? "Injected open failure" : nil
		await service.setOutcome(.failed(reason: reason))
		var reports: [String] = []
		let session = ScrollbackSession(
			store: service.storage,
			databaseDirectory: { await service.databaseDirectory() },
			reportFailure: {
				#expect(isolationIsMainActor(#isolation))
				reports.append($0)
			}
		)
		let entry = ScrollbackEntry(
			lineData: Data(), uniqueIdentifier: "line", viewIdentifier: "a",
			sessionIdentifier: 0, creationDate: 0
		)
		let request = Self.request(view: "a", label: "a1")
		let firstWrite = Task { await session.writeEntry(entry) }
		while await service.openCount == 0 {
			await Task.yield()
		}
		await withTaskGroup(of: Void.self) { group in
			for _ in 0 ..< 10 {
				group.addTask { await session.writeEntry(entry) }
				group.addTask { #expect(await session.fetchOutcome(request).entries.isEmpty) }
			}
			await service.openGate.open()
		}
		#expect(await firstWrite.value == .unavailable)
		for _ in 0 ..< 3 {
			await session.writeEntry(entry)
			#expect(await session.fetchOutcome(request).entries.isEmpty)
		}
		await session.removeHistory("a", forget: true)
		await session.removeHistory("a", forget: false)
		#expect(await service.openCount == 1)
		#expect(await service.entries.isEmpty)
		#expect(await service.fetchCount == 0)
		#expect(await session.isLoaded == false)
		#expect(await session.isUnavailable)
		let message = reason.map(PromptStrings.Logging.lastError) ?? PromptStrings.Logging.scrollbackFailureBody
		#expect(reports == [message])

		#expect(await session.retryLoading() == false)
		await session.writeEntry(entry)
		#expect(await session.fetchOutcome(request).entries.isEmpty)
		#expect(await service.openCount == 2)
		#expect(reports == [message, message])

		await service.setOutcome(.opened)
		// Recovery alone does not make ordinary traffic reopen the preserved file.
		await session.writeEntry(entry)
		#expect(await service.openCount == 2)
		#expect(await session.retryLoading())
		#expect(await session.isLoaded)
		#expect(await session.isUnavailable == false)
		await session.writeEntry(entry)
		#expect(await session.fetchOutcome(request).entries.map(\.uniqueIdentifier) == ["line"])
		let newest = ScrollbackFetchRequest(
			viewIdentifier: "a", kind: .rowPage(before: nil, fetchLimit: 1, limitToDate: nil)
		)
		#expect(await session.fetchOutcome(newest).entries.map(\.uniqueIdentifier) == ["line"])
		#expect(await session.retryLoading())
		#expect(await service.openCount == 3)
		#expect(await service.fetchCount == 2)
		#expect(reports == [message, message])
		probe.expectOrder(["open", "open", "open", "before", "newest"])
		probe.expectNoneOnMainActor()
		await session.prepareForTermination()
		#expect(await session.retryLoading() == false)
		#expect(await service.openCount == 3)
		#expect(await service.closeCount == 1)
	}

	@Test("A missing setup directory stays retryable without reporting an open failure")
	func missingDatabaseDirectoryAnswersSafely() async {
		let service = ScrollbackTestService(probe: IsolationProbe())
		await service.setDirectory(nil)
		await service.setOutcome(.opened)
		await service.openGate.open()
		let session = ScrollbackSession(
			store: service.storage,
			databaseDirectory: { await service.databaseDirectory() },
			reportFailure: { _ in Issue.record("No database open failed") }
		)
		let result = await session.fetchOutcome(Self.request(view: "a", label: "a1")).entries

		#expect(result.isEmpty)
		#expect(await session.isLoaded == false)
		#expect(await session.isUnavailable == false)
		#expect(await service.openCount == 0)
		await service.setDirectory("/injected/history")
		_ = await session.fetchOutcome(Self.request(view: "a", label: "a1")).entries
		#expect(await session.isLoaded)
		#expect(await service.openCount == 1)
		#expect(await service.fetchCount == 1)
		await session.prepareForTermination()
	}
}
