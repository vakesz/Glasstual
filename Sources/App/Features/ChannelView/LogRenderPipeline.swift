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

/** One unit of work for a log view's render pipeline.

 The closure runs off the main actor and returns the main-actor half of the job
 — the part that touches the transcript view — or `nil` when there is nothing to
 apply.
 A closure isolated to the main actor may capture values that are not `Sendable`
 because it can only ever run there, which is what lets a job carry an
 `NSAttributedString`, a `LogLine` or a caller's completion block home.

 `@concurrent` rather than the project's `nonisolated(nonsending)` default: a
 job that inherited its caller's isolation would render on the pipeline actor
 and serialise there, which is the executor this whole step exists to leave. */
typealias LogRenderJob = @Sendable @concurrent () async -> (@MainActor () -> Void)?

/// A job together with the ordering it asked for.
struct LogRenderSubmission: Sendable {
	/** A standalone job is applied after everything already submitted, but the
	 jobs submitted after it do not wait for it. The initial history load is
	 standalone, so a burst of live lines does not queue behind a database read;
	 printed lines and scrollback pages are not, because each one has to reach
	 the document behind the line before it. */
	var isStandalone: Bool
	var waitsForAllSubmissions = false
	var job: LogRenderJob
}

/** Ordered rendering for one log view.

 The controller yields into ``submissions`` from the main actor, and that is
 what fixes the order: a synchronous yield cannot be reordered the way two
 `Task`s racing to reach an actor can. The pipeline renders the jobs
 concurrently on the cooperative pool and applies their results on the main
 actor in the order they arrived, so a burst of lines still reaches the document
 in the order the client printed them.

 Nothing here is a lock or a queue: the ordering is the delivery chain, the
 back-pressure is the task group's width, and cancellation is ``stop()``, which
 cancels the deliveries still in flight, plus the controller's own generation
 check for the one that has already reached the main actor. */
actor LogRenderPipeline {
	/** How many lines render at once. The pipeline is per view, so this is a
	 per-view width; rendering is CPU-bound string work with no shared state. */
	private static let maximumConcurrentRenders = 4

	/** The controller's end of the pipeline. Yielding is synchronous and
	 thread-safe, which is what makes submission order the render order. */
	nonisolated let submissions: AsyncStream<LogRenderSubmission>.Continuation // nonisolated: let

	private let stream: AsyncStream<LogRenderSubmission>
	private var isStopped = false
	/// The deliveries that have not been applied yet, so ``stop()`` can reach
	/// them. A delivery withdraws its own entry as it finishes.
	private var deliveries: [UUID: Task<Void, Never>] = [:]
	private var drainWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

	init() {
		/* Unbounded on purpose. A dropping policy would silently lose lines
		 under a burst — a netsplit rejoin prints hundreds in one turn — and the
		 back-pressure that matters is on rendering, which the task group's width
		 already applies. */
		let (stream, continuation) = AsyncStream<LogRenderSubmission>.makeStream(
			bufferingPolicy: .unbounded
		)
		self.stream = stream
		submissions = continuation
	}

	/** Consumes submissions until the stream finishes. Call once, from a task
	 the owner keeps: the loop is the pipeline. */
	func run() async {
		await withTaskCancellationHandler {
			await withTaskGroup(of: Void.self) { group in
				var predecessor: Task<Void, Never>?
				var inFlight = 0

				for await submission in stream {
					if isStopped || Task.isCancelled {
						break
					}

					while inFlight >= Self.maximumConcurrentRenders {
						await group.next()
						inFlight -= 1
					}
					guard isStopped == false, Task.isCancelled == false else { break }

					let predecessors = submission.waitsForAllSubmissions
						? Array(deliveries.values) : predecessor.map { [$0] } ?? []
					let delivery = deliver(submission, after: predecessors)

					if submission.isStandalone == false {
						predecessor = delivery
					}

					group.addTask { await delivery.value }
					inFlight += 1
				}

				await group.waitForAll()
			}
		} onCancel: {
			Task { await self.stop() }
		}
	}

	/** Renders `submission` right away and holds its result until `predecessor`
	 has been applied. Starting the render before the wait is what makes the
	 pipeline concurrent; waiting afterwards is what keeps it in order. */
	private func deliver(
		_ submission: LogRenderSubmission,
		after predecessors: [Task<Void, Never>]
	) -> Task<Void, Never> {
		let identifier = UUID()

		let delivery = Task { [weak self] in
			let apply = await submission.job()

			for predecessor in predecessors {
				await predecessor.value
			}

			if Task.isCancelled == false {
				await MainActor.run {
					if Task.isCancelled == false {
						apply?()
					}
				}
			}

			await self?.finishDelivery(identifier)
		}

		deliveries[identifier] = delivery

		return delivery
	}

	private func finishDelivery(_ identifier: UUID) {
		deliveries.removeValue(forKey: identifier)
	}

	/** Ends the pipeline and stops accepting submissions.

	 Cancelling the deliveries is what makes it take effect on the work already
	 running: a render in flight stops rendering, and one that finished before
	 the cancellation reached it applies nothing. */
	func stop() {
		isStopped = true
		submissions.finish()

		for delivery in deliveries.values {
			delivery.cancel()
		}

		deliveries.removeAll()
		let waiters = drainWaiters.values
		drainWaiters.removeAll()
		for waiter in waiters {
			waiter.resume()
		}
	}

	/** Waits for the ordered lane, not outstanding standalone work. Stopping
	 the pipeline or cancelling the caller also ends the wait. Tests use this
	 instead of sleeping; the app has no reason to. */
	func drain() async {
		await waitForSubmissions(includingStandalone: false)
	}

	/// A fence in the submission stream. Later submissions do not extend this wait.
	func barrier() async {
		await waitForSubmissions(includingStandalone: true)
	}

	private func waitForSubmissions(includingStandalone: Bool) async {
		let identifier = UUID()
		await withTaskCancellationHandler {
			guard isStopped == false, Task.isCancelled == false else { return }
			await withCheckedContinuation { continuation in
				drainWaiters[identifier] = continuation
				/* `onCancel` hops back to the actor, so it can run before the
				 continuation is stored and find nothing to resume. Storing it
				 first and then reading the cancellation closes that window:
				 whichever order the two arrive in, one of them resumes. */
				guard Task.isCancelled == false else {
					finishDrain(identifier)
					return
				}
				let result = submissions.yield(LogRenderSubmission(
					isStandalone: true,
					waitsForAllSubmissions: includingStandalone
				) { [weak self] in
					{ Task { await self?.finishDrain(identifier) } }
				})
				if case .terminated = result {
					finishDrain(identifier)
				}
			}
		} onCancel: {
			Task { await self.finishDrain(identifier) }
		}
	}

	private func finishDrain(_ identifier: UUID) {
		drainWaiters.removeValue(forKey: identifier)?.resume()
	}
}
