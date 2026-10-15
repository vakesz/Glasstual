// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** One transcript's render pipeline and the main-actor applications it hands
 back, in the order they reach the view.

 Jobs render on a ``TranscriptRenderPipeline``. What each one returns is queued
 here and applied in batches, one batch per turn of the main actor, so a burst
 of lines is drawn in a few edits rather than one edit per line and input still
 gets its turn between them.

 Cancellation has two halves. ``invalidate()`` bumps the generation: a job that
 is already rendering compares the generation it was submitted under before it
 applies, which is the synchronous half. ``restart()`` and ``stop()`` drop what
 is queued and retire the pipeline, which drops the jobs that had not started;
 nothing waits for it. */
@MainActor
final class TranscriptRenderScheduler {
	/// How many applications one turn of the main actor runs.
	private static let batchSize = 32

	/// Bumped by ``invalidate()``. A job checks the value it was submitted
	/// under before it applies.
	private(set) var generation = 0

	/** The pipeline and the task that drains it. Replaced wholesale on
	 ``restart()``: dropping the stream is how queued work is cancelled. */
	private var pipeline = TranscriptRenderPipeline()
	private var pipelineTask: Task<Void, Never>?

	private var applications: [@MainActor () -> Void] = []
	/// Applications parked until the history replay finishes.
	private var heldApplications: [@MainActor () -> Void] = []
	private var applicationTask: Task<Void, Never>?

	/// Wraps one batch of applications. The owner supplies the view's editing
	/// batch, so the edits one batch makes are laid out once.
	private var performBatch: @MainActor (_ edits: () -> Void) -> Void = { $0() }

	isolated deinit {
		pipelineTask?.cancel()
		applicationTask?.cancel()
	}

	/// Starts the pipeline. Call once, when the owner can supply the batch
	/// wrapper.
	func start(applyingBatchesWith performBatch: @escaping @MainActor (_ edits: () -> Void) -> Void) {
		self.performBatch = performBatch
		startPipeline()
	}

	/// Hands a job to the pipeline. Submission order is render-application
	/// order, except that the jobs after a standalone one do not wait for it.
	func submit(isStandalone: Bool, _ job: @escaping TranscriptRenderJob) {
		pipeline.submissions.yield(TranscriptRenderSubmission(isStandalone: isStandalone, job: job))
	}

	/// Queues one finished render for application, and starts the drain if it
	/// is not already running.
	func enqueue(_ apply: @escaping @MainActor () -> Void) {
		applications.append(apply)
		guard applicationTask == nil else { return }
		applicationTask = Task { @MainActor [weak self] in
			await Task.yield()
			while let self, !Task.isCancelled {
				guard !applications.isEmpty else {
					applicationTask = nil
					return
				}
				applyBatch()
				await Task.yield()
			}
		}
	}

	/** Puts `batch` ahead of everything queued.

	 The replay applies its own lines this way, from an application the drain is
	 already running, so it does not start the drain itself. */
	func prioritize(_ batch: [@MainActor () -> Void]) {
		applications.insert(contentsOf: batch, at: 0)
	}

	/// Parks an application until ``releaseHeldApplications()``.
	func hold(_ apply: @escaping @MainActor () -> Void) {
		heldApplications.append(apply)
	}

	/// Moves the parked applications ahead of everything queued, in the order
	/// they were parked.
	func releaseHeldApplications() {
		applications.insert(contentsOf: heldApplications, at: 0)
		heldApplications.removeAll()
	}

	/// Makes every job submitted so far stale.
	func invalidate() {
		generation += 1
	}

	/// Drops what is queued and starts over with a fresh pipeline.
	func restart() {
		stop()
		pipeline = TranscriptRenderPipeline()
		startPipeline()
	}

	/// Drops what is queued and retires the pipeline for good.
	func stop() {
		applications.removeAll()
		heldApplications.removeAll()
		applicationTask?.cancel()
		applicationTask = nil
		let retired = pipeline
		Task { await retired.stop() }
		pipelineTask?.cancel()
		pipelineTask = nil
	}

	/// Returns once everything submitted before the call has been applied.
	func drain() async {
		await pipeline.barrier()
		while !applications.isEmpty {
			applyBatch()
			await Task.yield()
		}
	}

	private func startPipeline() {
		let pipeline = pipeline
		pipelineTask = Task {
			await pipeline.run()
		}
	}

	private func applyBatch() {
		let count = min(Self.batchSize, applications.count)
		let batch = Array(applications.prefix(count))
		applications.removeFirst(count)
		performBatch {
			for apply in batch {
				apply()
			}
		}
	}
}
