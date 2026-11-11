// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/** Who holds the scrollback store's transaction, and who waits for it.

 Operations queued behind the one in flight wait oldest first. `head` is the
 next to resume, so handing the turn on is O(1) rather than the shift
 `removeFirst` makes of every entry behind it. Every waiter is resumed by a
 hand-off and each operation runs even for a cancelled caller, so cancellation
 has nothing to remove and nothing to strand. */
nonisolated struct ScrollbackTurnQueue {
	private var occupied = false
	private var waiting: [CheckedContinuation<Void, Never>?] = []
	private var head = 0

	/// Operations waiting for the turn.
	var pendingCount: Int {
		waiting.count - head
	}

	/// Takes the turn if it is free. False means the caller has to wait.
	mutating func claim() -> Bool {
		guard occupied == false else { return false }
		occupied = true
		return true
	}

	/// Queues a caller that `claim()` turned away.
	mutating func enqueue(_ waiter: CheckedContinuation<Void, Never>) {
		waiting.append(waiter)
	}

	/// Passes the turn to the oldest waiter, which the caller resumes, or frees
	/// it when nobody waits.
	mutating func handOff() -> CheckedContinuation<Void, Never>? {
		guard head < waiting.count else {
			waiting.removeAll(keepingCapacity: true)
			head = 0
			occupied = false
			return nil
		}
		let next = waiting[head]
		waiting[head] = nil
		head += 1
		/* Reclaim the consumed prefix once it dominates, keeping the cost amortized O(1). */
		if head >= 32, head * 2 >= waiting.count {
			waiting.removeFirst(head)
			head = 0
		}
		return next
	}
}
