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
import Synchronization
import Testing

/// The order deliveries arrived in. A `Mutex` around a value because the
/// deliveries all land on the main actor but the renders do not.
private final class DeliveryLog: Sendable {
	private let storage = Mutex<[String]>([])

	func append(_ label: String) {
		storage.withLock { $0.append(label) }
	}

	var labels: [String] {
		storage.withLock { $0 }
	}
}

/// A gate a render half can park on so that a test decides when it finishes.
private actor RenderGate {
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
		guard isOpen == false else {
			return
		}
		await withCheckedContinuation { waiters.append($0) }
	}
}

/// A one-shot signal that a synchronous main-actor apply can fire and an async
/// test can wait for. `AsyncStream` buffers, so firing first is safe.
private final nonisolated class DeliverySignal: Sendable { // nonisolated: immutable
	private let stream: AsyncStream<Void>
	private let continuation: AsyncStream<Void>.Continuation

	init() {
		(stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded)
	}

	func fire() {
		continuation.yield()
		continuation.finish()
	}

	func wait() async {
		for await _ in stream {
			return
		}
	}
}

@Suite("Log render pipeline")
struct LogRenderPipelineTests {
	@Test("Every view keeps its own submission order under 200 interleaved prints")
	func orderIsPreservedPerViewUnderABurst() async {
		let viewCount = 3
		let lineCount = 200
		let pipelines = (0 ..< viewCount).map { _ in LogRenderPipeline() }
		let logs = (0 ..< viewCount).map { _ in DeliveryLog() }
		let runners = pipelines.map { pipeline in Task { await pipeline.run() } }

		/* Interleaved on purpose: the views share the cooperative pool, and each
		 render takes a different number of hops, so a pipeline that delivered in
		 completion order rather than submission order would shuffle here. */
		for line in 0 ..< lineCount {
			for (view, pipeline) in pipelines.enumerated() {
				let log = logs[view]
				let label = String(line)
				let hops = (line &* (view &+ 1)) % 7
				pipeline.submissions.yield(LogRenderSubmission(isStandalone: false) {
					for _ in 0 ..< hops {
						await Task.yield()
					}
					return { log.append(label) }
				})
			}
		}

		for pipeline in pipelines {
			await pipeline.drain()
			await pipeline.stop()
		}
		for runner in runners {
			await runner.value
		}

		let expected = (0 ..< lineCount).map(String.init)
		for (view, log) in logs.enumerated() {
			#expect(log.labels == expected, "view \(view) delivered out of order")
		}
	}

	@Test("Rendering happens off the main actor and delivery happens on it")
	func renderLeavesTheMainActorAndDeliveryReturnsToIt() async {
		let pipeline = LogRenderPipeline()
		let runner = Task { await pipeline.run() }
		let delivered = DeliverySignal()

		pipeline.submissions.yield(LogRenderSubmission(isStandalone: false) {
			await expectOffMainActor("the render half must not run on the main actor")
			/* The apply half is `@MainActor` by declaration, so the compiler is
			 what proves the other direction; firing from it proves it ran. */
			return { delivered.fire() }
		})

		await delivered.wait()
		await pipeline.stop()
		await runner.value
	}

	/** The burst above pins delivery order; this pins the other half of the same
	 contract — that every render ran off the main actor, not just the first.

	 Only the apply half is ordered. Four renders run at once on the cooperative
	 pool, so which of them finishes rendering first is the pool's business:
	 asserting submission order over the probe made this fail whenever the pool
	 happened to finish them out of order. The probe answers where each render
	 ran and that all five ran; the delivery log answers the ordering. */
	@Test("Every render in a burst leaves the main actor, and every apply lands in order")
	func everyRenderLeavesTheMainActor() async {
		let pipeline = LogRenderPipeline()
		let runner = Task { await pipeline.run() }
		let probe = IsolationProbe()
		let log = DeliveryLog()

		for line in 0 ..< 5 {
			let label = String(line)
			pipeline.submissions.yield(LogRenderSubmission(isStandalone: false) {
				await probe.record(label)
				return { log.append(label) }
			})
		}

		await pipeline.drain()

		#expect(log.labels == ["0", "1", "2", "3", "4"])
		#expect(probe.labels.sorted() == ["0", "1", "2", "3", "4"])
		probe.expectNoneOnMainActor()

		await pipeline.stop()
		await runner.value
	}

	@Test("A batched job waits for the one before it even when it renders first")
	func batchedJobsDeliverInSubmissionOrder() async {
		let pipeline = LogRenderPipeline()
		let runner = Task { await pipeline.run() }
		let log = DeliveryLog()
		let gate = RenderGate()
		let secondRendered = DeliverySignal()

		pipeline.submissions.yield(LogRenderSubmission(isStandalone: false) {
			await gate.wait()
			return { log.append("first") }
		})
		pipeline.submissions.yield(LogRenderSubmission(isStandalone: false) {
			secondRendered.fire()
			return { log.append("second") }
		})

		/* The second line has finished rendering while the first is still
		 parked, which is the case the delivery chain exists for. */
		await secondRendered.wait()

		#expect(log.labels.isEmpty, "the second line was applied ahead of the first")

		await gate.open()
		await pipeline.drain()

		#expect(log.labels == ["first", "second"])

		await pipeline.stop()
		await runner.value
	}

	@Test("A standalone job does not hold up what was submitted after it")
	func standaloneJobBypassesTheBatch() async {
		let pipeline = LogRenderPipeline()
		let runner = Task { await pipeline.run() }
		let log = DeliveryLog()
		let gate = RenderGate()
		let standaloneDelivered = DeliverySignal()

		/* The history load and the topic are standalone. They deliver behind
		 whatever was already queued, but a line printed afterwards must not sit
		 behind a scrollback fetch. */
		pipeline.submissions.yield(LogRenderSubmission(isStandalone: true) {
			await gate.wait()
			return {
				log.append("standalone")
				standaloneDelivered.fire()
			}
		})
		pipeline.submissions.yield(LogRenderSubmission(isStandalone: false) {
			{ log.append("batched") }
		})

		await pipeline.drain()

		#expect(log.labels == ["batched"], "the batched job waited for the standalone one")

		await gate.open()
		await standaloneDelivered.wait()

		#expect(log.labels == ["batched", "standalone"])

		await pipeline.stop()
		await runner.value
	}

	@Test("Work is delivered without a web view readiness signal")
	func workDoesNotWaitForAWebView() async {
		let pipeline = LogRenderPipeline()
		let log = DeliveryLog()
		let runner = Task { await pipeline.run() }

		for line in 0 ..< 5 {
			let label = String(line)
			pipeline.submissions.yield(LogRenderSubmission(isStandalone: false) {
				{ log.append(label) }
			})
		}

		await pipeline.drain()

		#expect(log.labels == ["0", "1", "2", "3", "4"])

		await pipeline.stop()
		await runner.value
	}

	/// Stopping is the pipeline's cancellation: a render that is still parked
	/// when the view is cleared must not reach the document afterwards.
	@Test("Stopping cancels a render that has not been applied yet")
	func stoppingCancelsWorkStillInFlight() async {
		let pipeline = LogRenderPipeline()
		let runner = Task { await pipeline.run() }
		let log = DeliveryLog()
		let gate = RenderGate()
		let rendering = DeliverySignal()

		pipeline.submissions.yield(LogRenderSubmission(isStandalone: false) {
			rendering.fire()
			await gate.wait()
			return { log.append("parked") }
		})

		await rendering.wait()
		await pipeline.stop()
		await gate.open()
		await runner.value

		#expect(log.labels.isEmpty, "a cancelled render still reached the transcript")
	}
}
