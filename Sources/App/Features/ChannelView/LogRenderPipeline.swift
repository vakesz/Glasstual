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
 — the part that touches the web view — or `nil` when there is nothing to apply.
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
	 jobs submitted after it do not wait for it. Topic changes, history loads and
	 scrollback pages are standalone; printed lines are not, because each one has
	 to reach the document behind the line before it. */
	var isStandalone: Bool
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
 back-pressure is the task group's width, and cancellation is
 ``stop()`` plus the controller's own generation check. */
actor LogRenderPipeline {
	/** How many lines render at once. The pipeline is per view, so this is a
	 per-view width; rendering is CPU-bound string work with no shared state. */
	private static let maximumConcurrentRenders = 4

	/** The controller's end of the pipeline. Yielding is synchronous and
	 thread-safe, which is what makes submission order the render order. */
	nonisolated let submissions: AsyncStream<LogRenderSubmission>.Continuation // nonisolated: let

	private let stream: AsyncStream<LogRenderSubmission>
	private var isStopped = false

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
		await withTaskGroup(of: Void.self) { group in
			var predecessor: Task<Void, Never>?
			var inFlight = 0

			for await submission in stream {
				if isStopped {
					break
				}

				while inFlight >= Self.maximumConcurrentRenders {
					await group.next()
					inFlight -= 1
				}

				let delivery = deliver(submission, after: predecessor)

				if submission.isStandalone == false {
					predecessor = delivery
				}

				group.addTask { await delivery.value }
				inFlight += 1
			}

			await group.waitForAll()
		}
	}

	/** Renders `submission` right away and holds its result until `predecessor`
	 has been applied. Starting the render before the wait is what makes the
	 pipeline concurrent; waiting afterwards is what keeps it in order. */
	private func deliver(
		_ submission: LogRenderSubmission,
		after predecessor: Task<Void, Never>?
	) -> Task<Void, Never> {
		Task {
			let apply = await submission.job()

			await predecessor?.value

			guard Task.isCancelled == false else {
				return
			}

			await MainActor.run { apply?() }
		}
	}

	/// Ends the pipeline and stops accepting submissions.
	func stop() {
		isStopped = true
		submissions.finish()
	}

	/** Waits until every job submitted so far has been applied. Tests use this
	 instead of sleeping; the app has no reason to. */
	func drain() async {
		await withCheckedContinuation { continuation in
			submissions.yield(LogRenderSubmission(isStandalone: false) {
				{ continuation.resume() }
			})
		}
	}
}
