/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// Holds every fetch at the door until the test lets them through, so the
/// order requests were made in is the only thing the queue can go by.
private actor FetchGate {
	private var isOpen = false
	private var waiting: [CheckedContinuation<Void, Never>] = []

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

private actor HistoricLogTestService: HistoricLogServicing {
	let probe: IsolationProbe
	let openGate = FetchGate()
	private(set) var openCount = 0
	private(set) var closeCount = 0
	private(set) var fetchCount = 0
	private(set) var entries: [HistoricLogEntry] = []
	private var outcome = HistoricLogOpenOutcome.failed(reason: "Injected open failure")
	private var fetchFailure: HistoricLogFetchFailure?
	private var directory: String? = "/injected/history"

	init(probe: IsolationProbe) {
		self.probe = probe
	}

	func setOutcome(_ outcome: HistoricLogOpenOutcome) {
		self.outcome = outcome
	}

	func setFetchFailure(_ failure: HistoricLogFetchFailure?) {
		fetchFailure = failure
	}

	func setDirectory(_ directory: String?) {
		self.directory = directory
	}

	func databaseDirectory() -> String? {
		directory
	}

	func openDatabase(inDirectory databaseDirectory: String) async -> HistoricLogOpenOutcome {
		#expect(databaseDirectory == "/injected/history")
		openCount += 1
		await probe.record("open")
		await openGate.wait()
		return outcome
	}

	func close() -> HistoricLogSaveOutcome {
		closeCount += 1
		return .saved
	}

	func setMaximumLineCount(_: UInt) {}
	func writeLogLine(_ logLine: HistoricLogEntry) -> HistoricLogWriteOutcome {
		entries.append(logLine)
		return .accepted
	}

	func forgetView(_ view: String) -> HistoricLogDeletionOutcome {
		let removed = entries.filter { $0.viewIdentifier == view }
		entries.removeAll { $0.viewIdentifier == view }
		return .deleted(.init(deletedCount: UInt(removed.count), uniqueIdentifiers: removed.map(\.uniqueIdentifier)))
	}

	func resetData(forView view: String) -> HistoricLogDeletionOutcome {
		forgetView(view)
	}

	func saveData() -> HistoricLogSaveOutcome {
		.saved
	}

	func fetchOutcome(_ request: HistoricLogFetchRequest) async -> HistoricLogFetchOutcome {
		fetchCount += 1
		switch request.kind {
		case .newest: await probe.record("newest")
		case .before: await probe.record("before")
		case let .rowPage(cursor, _, _): await probe.record(cursor == nil ? "newest" : "before")
		}
		return fetchFailure.map(HistoricLogFetchOutcome.failed) ?? .page(entries)
	}
}

@Suite("Historic log client")
struct HistoricLogClientTests {
	@Test("Read failures and empty pages remain distinct through the production client")
	func typedReadFailureCanBeRetried() async {
		let service = HistoricLogTestService(probe: IsolationProbe())
		await service.setOutcome(.opened)
		await service.openGate.open()
		let client = HistoricLogClient(store: service, databaseDirectory: { await service.databaseDirectory() },
		                               reportFailure: { _ in Issue.record("The database opened successfully") })
		let request = Self.request(view: "a", label: "a1")
		await service.setFetchFailure(.read("Injected read failure"))
		guard case .failed(.read("Injected read failure")) = await client.fetchOutcome(request) else {
			Issue.record("A failed read was converted to an empty page")
			await client.prepareForTermination()
			return
		}
		#expect(await client.fetchEntries(request).isEmpty)
		await service.setFetchFailure(nil)
		guard case let .page(entries) = await client.fetchOutcome(request) else {
			Issue.record("A read failure prevented retry")
			await client.prepareForTermination()
			return
		}
		#expect(entries.isEmpty)
		#expect(await service.openCount == 1)
		await client.prepareForTermination()
	}

	@Test("Cancelling a queued caller answers cancellation rather than exhaustion")
	func cancelledFetchHasTypedOutcome() async {
		let gate = FetchGate()
		let queue = HistoricLogRequestQueue { _ in
			await gate.wait()
			return .page([])
		}
		let task = Task { await queue.fetchOutcome(Self.request(view: "a", label: "a1")) }
		while await queue.pendingCount == 0 {
			await Task.yield()
		}
		task.cancel()
		if case .cancelled = await task.value {} else {
			Issue.record("Cancellation was reported as a page")
		}
		#expect(await queue.pendingCount == 0)
		await gate.open()
		await queue.cancelAll()
	}

	/// A request labelled by the line number it asks for, which is what the
	/// recorder reads back.
	private static func request(view: String, label: String) -> HistoricLogFetchRequest {
		HistoricLogFetchRequest(
			viewIdentifier: view,
			kind: .before(uniqueIdentifier: label, fetchLimit: 1, limitToDate: nil)
		)
	}

	private nonisolated static func label(of request: HistoricLogFetchRequest) -> String { // nonisolated: pure
		guard case let .before(uniqueIdentifier, _, _) = request.kind else {
			return ""
		}

		return uniqueIdentifier
	}

	/// Queues `requests` one at a time, waiting until each is registered before
	/// making the next, so the queue sees them in exactly this order.
	private static func enqueue(
		_ requests: [HistoricLogFetchRequest],
		on queue: HistoricLogRequestQueue
	) async -> [Task<[HistoricLogEntry], Never>] {
		var tasks: [Task<[HistoricLogEntry], Never>] = []

		for request in requests {
			tasks.append(Task { await queue.fetch(request) })

			while await queue.pendingCount < tasks.count {
				await Task.yield()
			}
		}

		return tasks
	}

	@Test("Ten interleaved fetches for two views are served first in, first out per view")
	func fetchesAreServedInOrderPerView() async {
		let gate = FetchGate()
		let probe = IsolationProbe()
		let queue = HistoricLogRequestQueue { request in
			await gate.wait()
			await probe.record(Self.label(of: request))
			return .page([])
		}

		let labels = ["a1", "b1", "a2", "b2", "a3", "b3", "a4", "b4", "a5", "b5"]
		let requests = labels.map { Self.request(view: String($0.prefix(1)), label: $0) }
		let tasks = await Self.enqueue(requests, on: queue)

		await gate.open()

		for task in tasks {
			_ = await task.value
		}

		let served = probe.labels
		#expect(served.count == labels.count)
		#expect(served.filter { $0.hasPrefix("a") } == ["a1", "a2", "a3", "a4", "a5"])
		#expect(served.filter { $0.hasPrefix("b") } == ["b1", "b2", "b3", "b4", "b5"])

		/* Scrollback comes out of Core Data. A fetch that ran on the main actor
		 would block the transcript for as long as the store took. */
		probe.expectNoneOnMainActor()
	}

	@Test("Forgetting a view answers everything still queued for it and leaves the others alone")
	func forgettingAViewAnswersItsQueuedFetches() async {
		let gate = FetchGate()
		let queue = HistoricLogRequestQueue { request in
			await gate.wait()
			return .page([
				HistoricLogEntry(
					logLineData: Data(),
					uniqueIdentifier: Self.label(of: request),
					viewIdentifier: request.viewIdentifier,
					sessionIdentifier: 0,
					creationDate: 0
				),
			])
		}

		let tasks = await Self.enqueue(
			[
				Self.request(view: "a", label: "a1"),
				Self.request(view: "a", label: "a2"),
				Self.request(view: "b", label: "b1"),
			],
			on: queue
		)

		await queue.forget(view: "a")

		#expect(await tasks[0].value.isEmpty)
		#expect(await tasks[1].value.isEmpty)

		await gate.open()

		#expect(await tasks[2].value.count == 1)
		#expect(await queue.pendingCount == 0)
	}

	@Test("Invalidating the connection answers every pending fetch with the empty result")
	func invalidationAnswersEveryPendingFetch() async {
		let gate = FetchGate()
		let queue = HistoricLogRequestQueue { _ in
			await gate.wait()
			return .page([])
		}

		let tasks = await Self.enqueue(
			[
				Self.request(view: "a", label: "a1"),
				Self.request(view: "a", label: "a2"),
				Self.request(view: "b", label: "b1"),
			],
			on: queue
		)

		await queue.cancelAll()

		for task in tasks {
			#expect(await task.value.isEmpty)
		}

		#expect(await queue.pendingCount == 0)
	}

	@Test(
		"Failed opens report once across concurrent and serial operations until explicit retry",
		arguments: [false, true]
	)
	func failedOpenRequiresExplicitRetry(withReason: Bool) async {
		let probe = IsolationProbe()
		let service = HistoricLogTestService(probe: probe)
		let reason = withReason ? "Injected open failure" : nil
		await service.setOutcome(.failed(reason: reason))
		var reports: [String] = []
		let client = HistoricLogClient(
			store: service,
			databaseDirectory: { await service.databaseDirectory() },
			reportFailure: {
				#expect(isMainActor(#isolation))
				reports.append($0)
			}
		)
		let entry = HistoricLogEntry(
			logLineData: Data(), uniqueIdentifier: "line", viewIdentifier: "a",
			sessionIdentifier: 0, creationDate: 0
		)
		let request = Self.request(view: "a", label: "a1")
		let firstWrite = Task { await client.writeEntry(entry) }
		while await service.openCount == 0 {
			await Task.yield()
		}
		await withTaskGroup(of: Void.self) { group in
			for _ in 0 ..< 10 {
				group.addTask { await client.writeEntry(entry) }
				group.addTask { #expect(await client.fetchEntries(request).isEmpty) }
			}
			await service.openGate.open()
		}
		#expect(await firstWrite.value == .unavailable)
		for _ in 0 ..< 3 {
			await client.writeEntry(entry)
			#expect(await client.fetchEntries(request).isEmpty)
		}
		await client.forgetView("a")
		await client.resetData(forView: "a")
		#expect(await service.openCount == 1)
		#expect(await service.entries.isEmpty)
		#expect(await service.fetchCount == 0)
		#expect(await client.isLoaded == false)
		#expect(await client.isUnavailable)
		let message = reason.map(PromptStrings.Logging.lastError) ?? PromptStrings.Logging.scrollbackFailureBody
		#expect(reports == [message])

		#expect(await client.retryLoading() == false)
		await client.writeEntry(entry)
		#expect(await client.fetchEntries(request).isEmpty)
		#expect(await service.openCount == 2)
		#expect(reports == [message, message])

		await service.setOutcome(.opened)
		// Recovery alone does not make ordinary traffic reopen the preserved file.
		await client.writeEntry(entry)
		#expect(await service.openCount == 2)
		#expect(await client.retryLoading())
		#expect(await client.isLoaded)
		#expect(await client.isUnavailable == false)
		await client.writeEntry(entry)
		#expect(await client.fetchEntries(request).map(\.uniqueIdentifier) == ["line"])
		let newest = HistoricLogFetchRequest(
			viewIdentifier: "a", kind: .newest(ascending: true, fetchLimit: 1, limitToDate: nil)
		)
		#expect(await client.fetchEntries(newest).map(\.uniqueIdentifier) == ["line"])
		#expect(await client.retryLoading())
		#expect(await service.openCount == 3)
		#expect(await service.fetchCount == 2)
		#expect(reports == [message, message])
		probe.expectOrder(["open", "open", "open", "before", "newest"])
		probe.expectNoneOnMainActor()
		await client.prepareForTermination()
		#expect(await client.retryLoading() == false)
		#expect(await service.openCount == 3)
		#expect(await service.closeCount == 1)
	}

	@Test("A missing setup directory stays retryable without reporting an open failure")
	func missingDatabaseDirectoryAnswersSafely() async {
		let service = HistoricLogTestService(probe: IsolationProbe())
		await service.setDirectory(nil)
		await service.setOutcome(.opened)
		await service.openGate.open()
		let client = HistoricLogClient(
			store: service,
			databaseDirectory: { await service.databaseDirectory() },
			reportFailure: { _ in Issue.record("No database open failed") }
		)
		let result = await client.fetchEntries(Self.request(view: "a", label: "a1"))

		#expect(result.isEmpty)
		#expect(await client.isLoaded == false)
		#expect(await client.isUnavailable == false)
		#expect(await service.openCount == 0)
		await service.setDirectory("/injected/history")
		_ = await client.fetchEntries(Self.request(view: "a", label: "a1"))
		#expect(await client.isLoaded)
		#expect(await service.openCount == 1)
		#expect(await service.fetchCount == 1)
		await client.prepareForTermination()
	}
}
