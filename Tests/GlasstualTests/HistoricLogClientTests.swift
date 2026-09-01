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

/// Records the order the fake service was asked for things in.
private actor FetchRecorder {
	private(set) var labels: [String] = []

	func record(_ label: String) {
		labels.append(label)
	}
}

@Suite("Historic log client")
struct HistoricLogClientTests {
	/// A request labelled by the line number it asks for, which is what the
	/// recorder reads back.
	private static func request(view: String, label: String) -> HistoricLogFetchRequest {
		HistoricLogFetchRequest(
			viewIdentifier: view,
			kind: .before(uniqueIdentifier: label, fetchLimit: 1, limitToDate: nil)
		)
	}

	private nonisolated static func label(of request: HistoricLogFetchRequest) -> String {
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
		let recorder = FetchRecorder()
		let queue = HistoricLogRequestQueue { request in
			await gate.wait()
			await recorder.record(Self.label(of: request))
			return []
		}

		let labels = ["a1", "b1", "a2", "b2", "a3", "b3", "a4", "b4", "a5", "b5"]
		let requests = labels.map { Self.request(view: String($0.prefix(1)), label: $0) }
		let tasks = await Self.enqueue(requests, on: queue)

		await gate.open()

		for task in tasks {
			_ = await task.value
		}

		let served = await recorder.labels
		#expect(served.count == labels.count)
		#expect(served.filter { $0.hasPrefix("a") } == ["a1", "a2", "a3", "a4", "a5"])
		#expect(served.filter { $0.hasPrefix("b") } == ["b1", "b2", "b3", "b4", "b5"])
	}

	@Test("Forgetting a view answers everything still queued for it and leaves the others alone")
	func forgettingAViewAnswersItsQueuedFetches() async {
		let gate = FetchGate()
		let queue = HistoricLogRequestQueue { request in
			await gate.wait()
			return [
				HistoricLogEntry(
					logLineData: Data(),
					uniqueIdentifier: Self.label(of: request),
					viewIdentifier: request.viewIdentifier,
					sessionIdentifier: 0,
					creationDate: 0
				),
			]
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
			return []
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

	@Test("A client without a database directory stays unloaded and answers safely")
	func missingDatabaseDirectoryAnswersSafely() async {
		let client = HistoricLogClient(databaseDirectory: nil)
		let result = await client.fetchEntries(Self.request(view: "a", label: "a1"))

		#expect(result.isEmpty)
		#expect(await client.isLoaded == false)
	}
}
