// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** One unit of work for a transcript's render pipeline.

 The closure runs off the main actor and returns the main-actor half of the job
 — the part that touches the transcript view — or `nil` when there is nothing to
 apply.
 A closure isolated to the main actor may capture values that are not `Sendable`
 because it can only ever run there, which is what lets a job carry an
 `NSAttributedString`, a `ChatLine` or a caller's completion block home.

 `@concurrent` rather than the project's `nonisolated(nonsending)` default: a
 job that inherited its caller's isolation would render on the pipeline actor
 and serialise there, which is the executor this whole step exists to leave. */
typealias TranscriptRenderJob = @Sendable @concurrent () async -> (@MainActor () -> Void)?

/// What running a job costs, which decides whether it takes a slot from the
/// shared render budget.
enum RenderCost: Sendable {
	/// Waits on storage, the main actor or nothing at all. Never takes a slot,
	/// so a slow read cannot hold up the lines being printed.
	case io
	/// Renders text on the CPU: a printed line, a delivery replacement, a page
	/// of history.
	case cpu
}

/// A job together with the ordering it asked for.
struct TranscriptRenderSubmission: Sendable {
	/** A standalone job is applied after everything already submitted, but the
	 jobs submitted after it do not wait for it. The initial history load is
	 standalone, so a burst of live lines does not queue behind a database read;
	 printed lines and scrollback pages are not, because each one has to reach
	 the document behind the line before it. */
	var isStandalone: Bool
	var waitsForAllSubmissions = false
	var cost = RenderCost.io
	var job: TranscriptRenderJob
}

/** Ordered rendering for one transcript.

 The controller yields into ``submissions`` from the main actor, and that is
 what fixes the order: a synchronous yield cannot be reordered the way two
 `Task`s racing to reach an actor can. The pipeline renders the jobs
 concurrently on the cooperative pool and applies their results on the main
 actor in the order they arrived, so a burst of lines still reaches the document
 in the order the session printed them.

 Nothing here is a lock or a queue: the ordering is the delivery chain, the
 render concurrency is the task group's width, and cancellation is ``stop()``, which
 cancels the deliveries still in flight, plus the controller's own generation
 check for the one that has already reached the main actor. */
actor TranscriptRenderPipeline {
	/** How many jobs one pipeline renders at once. Alone, a view may use the
	 whole width; with a shared ``RenderConcurrencyLimit`` the limit is what
	 bounds the machine, and a narrower view keeps one busy conversation from
	 queueing most of the budget's waiters. */
	private static let unlimitedWidth = 4
	private static let limitedWidth = 2

	private let maximumConcurrentRenders: Int
	private let limit: RenderConcurrencyLimit?

	/** The controller's end of the pipeline. Yielding is synchronous and
	 thread-safe, which is what makes submission order the render order. */
	nonisolated let submissions: AsyncStream<TranscriptRenderSubmission>.Continuation

	private let stream: AsyncStream<TranscriptRenderSubmission>
	private var isStopped = false
	/// The deliveries that have not been applied yet, so ``stop()`` can reach
	/// them. A delivery withdraws its own entry as it finishes.
	private var deliveries: [UUID: Task<Void, Never>] = [:]
	/// The position of the next ordered job in the delivery chain.
	private var nextSequence = 0
	/// Ordered jobs that have rendered and wait for their turn, by position.
	private var rendered: [Int: Application] = [:]
	/// Ordered jobs another delivery already applied, by position.
	private var appliedEarly: Set<Int> = []
	/// How many main-actor turns ordered jobs were applied in. For tests.
	private(set) var orderedBatchCount = 0

	/// How many ordered jobs have rendered and wait for their turn. For tests.
	var readyApplicationCount: Int {
		rendered.count
	}

	private var drainWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

	/// `limit` is the budget CPU-bound jobs draw their render slot from; nil
	/// leaves the pipeline bounded by its own width alone.
	init(limit: RenderConcurrencyLimit? = nil) {
		self.limit = limit
		maximumConcurrentRenders = limit == nil ? Self.unlimitedWidth : Self.limitedWidth
		/* Submission preserves synchronous print order. The session's admission
		 budget makes network producers suspend before another wire line, and
		 counts this work through transcript application. A single wire event
		 can fan out to several views; none of those lines may be dropped. */
		let (stream, continuation) = AsyncStream<TranscriptRenderSubmission>.makeStream(
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

					while inFlight >= maximumConcurrentRenders {
						await group.next()
						inFlight -= 1
					}
					guard isStopped == false, Task.isCancelled == false else { break }

					let predecessors = submission.waitsForAllSubmissions
						? Array(deliveries.values) : predecessor.map { [$0] } ?? []
					let (rendering, delivery) = deliver(
						submission, after: predecessors, at: sequence(for: submission)
					)

					if submission.isStandalone == false {
						predecessor = delivery
					}

					/* The width bounds renders, not lines waiting to be applied: a
					 job that has rendered gives its place back while it waits for
					 the main actor, so a burst reaches the view as many finished
					 lines per turn rather than one or two, and the view edits its
					 text once for all of them. */
					group.addTask { await rendering.value }
					inFlight += 1
				}

				await group.waitForAll()
			}
			for delivery in deliveries.values {
				await delivery.value
			}
		} onCancel: {
			Task { await self.stop() }
		}
	}

	typealias Application = (@MainActor () -> Void)?

	/** The job's position among the ordered jobs, or nil for a job that is
	 applied on its own. A job every earlier one has to precede leaves a gap,
	 so no batch of ordered jobs is applied across it. */
	private func sequence(for submission: TranscriptRenderSubmission) -> Int? {
		guard submission.isStandalone == false else { return nil }
		defer { nextSequence += 1 }
		return submission.waitsForAllSubmissions ? nil : nextSequence
	}

	/** Renders `submission` right away and holds its result until `predecessor`
	 has been applied. Starting the render before the wait is what makes the
	 pipeline concurrent; waiting afterwards is what keeps it in order. Returns
	 the render, which ends when the result is ready, and the delivery, which
	 ends when it has been applied.

	 An ordered job whose turn comes applies, in the same main-actor turn, every
	 job after it that has already rendered: the chain otherwise reached the
	 main actor once per line, and a burst reached the view one line per edit. */
	private func deliver(
		_ submission: TranscriptRenderSubmission,
		after predecessors: [Task<Void, Never>],
		at sequence: Int?
	) -> (rendering: Task<Void, Never>, delivery: Task<Void, Never>) {
		let identifier = UUID()
		let limit = limit
		let render = Task { await Self.render(submission, limit: limit) }

		let delivery = Task { [weak self] in
			let apply = await withTaskCancellationHandler {
				await render.value
			} onCancel: {
				render.cancel()
			}
			if let sequence {
				await self?.noteRendered(apply, at: sequence)
			}

			for predecessor in predecessors {
				await predecessor.value
			}

			let batch = if let sequence {
				await self?.takeBatch(startingAt: sequence) ?? []
			} else {
				[apply]
			}
			if Task.isCancelled == false, batch.isEmpty == false {
				await MainActor.run {
					for apply in batch where Task.isCancelled == false {
						apply?()
					}
				}
			}

			await self?.finishDelivery(identifier)
		}

		deliveries[identifier] = delivery

		return (Task { _ = await render.value }, delivery)
	}

	/** Runs the job, holding a render slot for exactly as long as a CPU-bound job
	 renders. A caller cancelled while waiting for the slot never runs the job. */
	private nonisolated static func render( // nonisolated: pure
		_ submission: TranscriptRenderSubmission,
		limit: RenderConcurrencyLimit?
	) async -> (@MainActor () -> Void)? {
		guard submission.cost == .cpu, let limit else {
			return await submission.job()
		}
		guard await limit.acquire() else {
			return nil
		}
		defer { limit.release() }
		return await submission.job()
	}

	private func noteRendered(_ apply: Application, at sequence: Int) {
		/* `updateValue`: assigning a job that rendered nothing would remove
		 the entry instead of recording that it is ready. */
		rendered.updateValue(apply, forKey: sequence)
	}

	/** The applications from `sequence` on that are ready, in order, or none
	 when an earlier delivery has already applied this one. Called once its
	 predecessor has been applied, so nothing before `sequence` is pending. */
	private func takeBatch(startingAt sequence: Int) -> [Application] {
		guard appliedEarly.remove(sequence) == nil else { return [] }
		var batch: [Application] = []
		var position = sequence
		while let apply = rendered.removeValue(forKey: position) {
			batch.append(apply)
			if position != sequence {
				appliedEarly.insert(position)
			}
			position += 1
		}
		if batch.isEmpty == false {
			orderedBatchCount += 1
		}
		return batch
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
		rendered.removeAll()
		appliedEarly.removeAll()
		let waiters = drainWaiters.values
		drainWaiters.removeAll()
		for waiter in waiters {
			waiter.resume()
		}
	}

	/** A fence in the submission stream: everything submitted before this call
	 has been applied when it returns, and later submissions do not extend the
	 wait. Stopping the pipeline or cancelling the caller also ends it. */
	func barrier() async {
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
				let result = submissions.yield(TranscriptRenderSubmission(
					isStandalone: true,
					waitsForAllSubmissions: true
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
