// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Scrollback turn queue")
struct ScrollbackTurnQueueTests {
	private final class Harness {
		var queue = ScrollbackTurnQueue()
		var resumed: [Int] = []

		func wait(_ index: Int) async {
			await withCheckedContinuation { queue.enqueue($0) }
			resumed.append(index)
		}
	}

	@Test("A free turn is taken once, and freed when nobody waits")
	func freeTurnIsClaimedOnce() {
		var queue = ScrollbackTurnQueue()

		let first = queue.claim()
		let second = queue.claim()
		let handedOff = queue.handOff()
		let afterRelease = queue.claim()

		#expect(first)
		#expect(second == false)
		#expect(handedOff == nil)
		#expect(afterRelease)
	}

	/// Forty waiters pass the compaction point at 32, which must not reorder them.
	@Test("Waiters resume oldest first, across compaction")
	func waitersResumeInOrder() async throws {
		let harness = Harness()
		let claimed = harness.queue.claim()
		#expect(claimed)
		var tasks: [Task<Void, Never>] = []
		for index in 0 ..< 40 {
			tasks.append(Task { await harness.wait(index) })
			while harness.queue.pendingCount < index + 1 {
				await Task.yield()
			}
		}
		#expect(harness.queue.pendingCount == 40)

		for index in 0 ..< 40 {
			let handedOff = harness.queue.handOff()
			let next = try #require(handedOff)
			next.resume()
			await tasks[index].value
			#expect(harness.queue.pendingCount == 39 - index)
		}

		let last = harness.queue.handOff()
		let reclaimed = harness.queue.claim()
		#expect(harness.resumed == Array(0 ..< 40))
		#expect(last == nil)
		#expect(reclaimed)
	}
}
