// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// What the applications ran, and in which batches.
@MainActor
private final class ApplicationLog {
	var entries: [String] = []
	var batchSizes: [Int] = []
}

@MainActor
@Suite("Transcript render scheduler")
struct TranscriptRenderSchedulerTests {
	private func makeScheduler(_ log: ApplicationLog) -> TranscriptRenderScheduler {
		let scheduler = TranscriptRenderScheduler()
		scheduler.start { edits in
			let before = log.entries.count
			edits()
			log.batchSizes.append(log.entries.count - before)
		}
		return scheduler
	}

	@Test("Prioritized applications run ahead of everything already queued")
	func prioritizedRunFirst() async {
		let log = ApplicationLog()
		let scheduler = makeScheduler(log)
		scheduler.enqueue { log.entries.append("queued") }
		scheduler.prioritize([{ log.entries.append("first") }, { log.entries.append("second") }])
		await scheduler.drain()
		#expect(log.entries == ["first", "second", "queued"])
	}

	@Test("Held applications wait for release, then run ahead of the queue in the order they were held")
	func heldApplicationsWaitForRelease() async {
		let log = ApplicationLog()
		let scheduler = makeScheduler(log)
		scheduler.hold { log.entries.append("held 1") }
		scheduler.hold { log.entries.append("held 2") }
		scheduler.enqueue { log.entries.append("queued") }
		await scheduler.drain()
		#expect(log.entries == ["queued"])
		scheduler.enqueue { log.entries.append("later") }
		scheduler.releaseHeldApplications()
		await scheduler.drain()
		#expect(log.entries == ["queued", "held 1", "held 2", "later"])
	}

	@Test("Applications run through the owner's batch wrapper, at most 32 at a time")
	func applicationsRunInBoundedBatches() async {
		let log = ApplicationLog()
		let scheduler = makeScheduler(log)
		for index in 0 ..< 70 {
			scheduler.enqueue { log.entries.append("\(index)") }
		}
		await scheduler.drain()
		#expect(log.entries == (0 ..< 70).map(String.init))
		#expect(log.batchSizes == [32, 32, 6])
	}

	@Test("Restarting drops queued and held work, and the fresh pipeline renders what follows")
	func restartDropsQueuedWork() async {
		let log = ApplicationLog()
		let scheduler = makeScheduler(log)
		let generation = scheduler.generation
		scheduler.enqueue { log.entries.append("queued") }
		scheduler.hold { log.entries.append("held") }
		scheduler.invalidate()
		scheduler.restart()
		#expect(scheduler.generation != generation)
		scheduler.submit(isStandalone: false) {
			{ log.entries.append("rendered") }
		}
		scheduler.releaseHeldApplications()
		await scheduler.drain()
		#expect(log.entries == ["rendered"])
	}
}
