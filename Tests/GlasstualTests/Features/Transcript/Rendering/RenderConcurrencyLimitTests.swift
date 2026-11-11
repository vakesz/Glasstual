// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Synchronization
import Testing

/// How many renders are running now and the most there have been at once.
private final nonisolated class ConcurrencyProbe: Sendable { // nonisolated: immutable
	private let storage = Mutex((current: 0, maximum: 0))

	func enter() {
		storage.withLock {
			$0.current += 1
			$0.maximum = max($0.maximum, $0.current)
		}
	}

	func leave() {
		storage.withLock { $0.current -= 1 }
	}

	var current: Int {
		storage.withLock { $0.current }
	}

	var maximum: Int {
		storage.withLock { $0.maximum }
	}
}

private final nonisolated class AppliedLog: Sendable { // nonisolated: immutable
	private let storage = Mutex<[String]>([])

	func append(_ label: String) {
		storage.withLock { $0.append(label) }
	}

	var labels: [String] {
		storage.withLock { $0 }
	}
}

private actor ParkGate {
	private var isOpen = false
	private var waiters: [CheckedContinuation<Void, Never>] = []

	func open() {
		isOpen = true
		let parked = waiters
		waiters.removeAll()
		for waiter in parked {
			waiter.resume()
		}
	}

	func wait() async {
		guard isOpen == false else { return }
		await withCheckedContinuation { waiters.append($0) }
	}
}

@Suite("Render concurrency limit")
struct RenderConcurrencyLimitTests {
	// MARK: - The budget

	@Test("A slot is handed to the longest waiter, one release at a time", .timeLimit(.minutes(1)))
	func slotsAreHandedOverInOrder() async throws {
		let limit = RenderConcurrencyLimit(capacity: 2)
		#expect(await limit.acquire())
		#expect(await limit.acquire())
		let order = AppliedLog()

		let first = Task {
			let granted = await limit.acquire()
			order.append("first")
			return granted
		}
		try await Eventually.until("1 waiter in the queue") { limit.waitingCount >= 1 }
		let second = Task {
			let granted = await limit.acquire()
			order.append("second")
			return granted
		}
		try await Eventually.until("2 waiters in the queue") { limit.waitingCount >= 2 }

		limit.release()
		#expect(await first.value)
		#expect(order.labels == ["first"])
		#expect(limit.waitingCount == 1)

		limit.release()
		#expect(await second.value)
		#expect(order.labels == ["first", "second"])
	}

	@Test("A cancelled waiter leaves the queue without taking a slot", .timeLimit(.minutes(1)))
	func cancelledWaiterTakesNothing() async throws {
		let limit = RenderConcurrencyLimit(capacity: 1)
		#expect(await limit.acquire())

		let waiter = Task { await limit.acquire() }
		try await Eventually.until("1 waiter in the queue") { limit.waitingCount >= 1 }
		waiter.cancel()

		#expect(await waiter.value == false)
		#expect(limit.waitingCount == 0)
		limit.release()
		#expect(limit.availableCount == 1)
	}

	@Test("A caller cancelled before it asks is refused without waiting", .timeLimit(.minutes(1)))
	func alreadyCancelledCallerIsRefused() async {
		let limit = RenderConcurrencyLimit(capacity: 1)
		#expect(await limit.acquire())

		let caller = Task {
			try? await Task.sleep(for: .seconds(60))
			return await limit.acquire()
		}
		caller.cancel()

		#expect(await caller.value == false)
		#expect(limit.waitingCount == 0)
	}

	// MARK: - The pipelines

	private func cpuJob(
		_ probe: ConcurrencyProbe,
		log: AppliedLog,
		label: String,
		milliseconds: Int = 3
	) -> TranscriptRenderSubmission {
		TranscriptRenderSubmission(isStandalone: false, cost: .cpu) {
			probe.enter()
			try? await Task.sleep(for: .milliseconds(milliseconds))
			probe.leave()
			return { log.append(label) }
		}
	}

	@Test("Renders across every pipeline never exceed the shared budget", .timeLimit(.minutes(1)))
	func budgetBoundsRendersAcrossPipelines() async {
		let limit = RenderConcurrencyLimit(capacity: 2)
		let probe = ConcurrencyProbe()
		let log = AppliedLog()
		let pipelines = (0 ..< 4).map { _ in TranscriptRenderPipeline(limit: limit) }
		let runners = pipelines.map { pipeline in Task { await pipeline.run() } }

		for (index, pipeline) in pipelines.enumerated() {
			for line in 0 ..< 6 {
				pipeline.submissions.yield(cpuJob(probe, log: log, label: "\(index).\(line)"))
			}
		}
		for pipeline in pipelines {
			await pipeline.barrier()
		}

		#expect(probe.maximum <= 2)
		#expect(probe.maximum >= 1)
		#expect(log.labels.count == 24)
		for index in 0 ..< 4 {
			let own = log.labels.filter { $0.hasPrefix("\(index).") }
			#expect(own == (0 ..< 6).map { "\(index).\($0)" }, "pipeline \(index) applied out of order")
		}
		#expect(limit.availableCount == 2)

		for pipeline in pipelines {
			await pipeline.stop()
		}
		for runner in runners {
			await runner.value
		}
	}

	@Test("One pipeline with a budget renders at most two jobs at once", .timeLimit(.minutes(1)))
	func limitedPipelineIsTwoWide() async throws {
		let limit = RenderConcurrencyLimit(capacity: 8)
		let pipeline = TranscriptRenderPipeline(limit: limit)
		let runner = Task { await pipeline.run() }
		let probe = ConcurrencyProbe()
		let log = AppliedLog()
		let gate = ParkGate()

		for line in 0 ..< 5 {
			pipeline.submissions.yield(TranscriptRenderSubmission(isStandalone: false, cost: .cpu) {
				probe.enter()
				await gate.wait()
				probe.leave()
				return { log.append("\(line)") }
			})
		}
		try await Eventually.until("2 renders in flight") { probe.current >= 2 }
		try await Task.sleep(for: .milliseconds(100))
		#expect(probe.current == 2)

		await gate.open()
		await pipeline.barrier()

		#expect(probe.maximum == 2)
		#expect(log.labels == ["0", "1", "2", "3", "4"])

		await pipeline.stop()
		await runner.value
	}

	@Test("A burst keeps its submission order when the budget is smaller than the burst", .timeLimit(.minutes(1)))
	func orderSurvivesTheBudget() async {
		let limit = RenderConcurrencyLimit(capacity: 2)
		let pipeline = TranscriptRenderPipeline(limit: limit)
		let runner = Task { await pipeline.run() }
		let probe = ConcurrencyProbe()
		let log = AppliedLog()

		for line in 0 ..< 60 {
			/* Later lines finish first, which is the case the delivery chain is for. */
			pipeline.submissions.yield(cpuJob(probe, log: log, label: "\(line)", milliseconds: line % 3 == 0 ? 6 : 1))
		}
		await pipeline.barrier()

		#expect(log.labels == (0 ..< 60).map(String.init))

		await pipeline.stop()
		await runner.value
	}

	@Test("A job that waits on storage never takes a render slot", .timeLimit(.minutes(1)))
	func ioJobsBypassTheBudget() async throws {
		let limit = RenderConcurrencyLimit(capacity: 1)
		let busy = TranscriptRenderPipeline(limit: limit)
		let other = TranscriptRenderPipeline(limit: limit)
		let busyRunner = Task { await busy.run() }
		let otherRunner = Task { await other.run() }
		let probe = ConcurrencyProbe()
		let log = AppliedLog()
		let gate = ParkGate()

		busy.submissions.yield(TranscriptRenderSubmission(isStandalone: false, cost: .cpu) {
			probe.enter()
			await gate.wait()
			probe.leave()
			return nil
		})
		try await Eventually.until("1 render in flight") { probe.current >= 1 }
		#expect(limit.availableCount == 0)

		other.submissions.yield(TranscriptRenderSubmission(isStandalone: true) { { log.append("history") } })
		await other.barrier()
		#expect(log.labels == ["history"])

		await gate.open()
		await busy.barrier()
		#expect(limit.availableCount == 1)

		await busy.stop()
		await other.stop()
		await busyRunner.value
		await otherRunner.value
	}

	@Test("Stopping a pipeline that is waiting for a slot gives nothing away", .timeLimit(.minutes(1)))
	func stoppingWhileWaitingForASlotDoesNotLeakIt() async throws {
		let limit = RenderConcurrencyLimit(capacity: 1)
		let holder = TranscriptRenderPipeline(limit: limit)
		let waiter = TranscriptRenderPipeline(limit: limit)
		let holderRunner = Task { await holder.run() }
		let waiterRunner = Task { await waiter.run() }
		let probe = ConcurrencyProbe()
		let log = AppliedLog()
		let gate = ParkGate()

		holder.submissions.yield(TranscriptRenderSubmission(isStandalone: false, cost: .cpu) {
			probe.enter()
			await gate.wait()
			probe.leave()
			return { log.append("held") }
		})
		try await Eventually.until("1 render in flight") { probe.current >= 1 }
		waiter.submissions.yield(cpuJob(probe, log: log, label: "never"))
		try await Eventually.until("1 waiter in the queue") { limit.waitingCount >= 1 }

		await waiter.stop()
		await waiterRunner.value
		#expect(limit.waitingCount == 0)

		await gate.open()
		await holder.barrier()
		#expect(log.labels == ["held"])
		#expect(limit.availableCount == 1)

		/* The budget still works for whoever comes next. */
		let next = TranscriptRenderPipeline(limit: limit)
		let nextRunner = Task { await next.run() }
		next.submissions.yield(cpuJob(probe, log: log, label: "after"))
		await next.barrier()
		#expect(log.labels == ["held", "after"])

		await holder.stop()
		await next.stop()
		await holderRunner.value
		await nextRunner.value
	}
}
