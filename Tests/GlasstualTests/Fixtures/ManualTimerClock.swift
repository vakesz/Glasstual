// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual

/** A `TimerClock` the test moves itself.

 `wait(_:)` parks the timer's task until ``advance(by:)`` carries the virtual
 instant past its deadline, so no test sleeps. A cancelled wait is released at
 once, the way the continuous clock's is. ``finish()`` lets go of whatever is
 still parked before a test ends. */
@MainActor
final class ManualTimerClock {
	private struct Sleeper {
		let identifier: UUID
		let deadline: ContinuousClock.Instant
		let continuation: CheckedContinuation<Void, Never>
	}

	private var instant = ContinuousClock.now
	private var sleepers: [Sleeper] = []

	var timerClock: TimerClock {
		TimerClock(
			now: { [self] in instant },
			wait: { [self] interval in await wait(interval) }
		)
	}

	/// Moves the virtual instant forward and lets every task it woke run.
	func advance(by seconds: TimeInterval) async {
		await settle()
		instant = instant.advanced(by: .seconds(seconds))
		let due = sleepers.filter { $0.deadline <= instant }
		sleepers.removeAll { $0.deadline <= instant }
		for sleeper in due {
			sleeper.continuation.resume()
		}
		await settle()
	}

	/// Lets the tasks the test has already started reach their next wait.
	func settle() async {
		for _ in 0 ..< 8 {
			await Task.yield()
		}
	}

	func finish() {
		let parked = sleepers
		sleepers.removeAll()
		for sleeper in parked {
			sleeper.continuation.resume()
		}
	}

	private func wait(_ interval: TimeInterval) async {
		guard Task.isCancelled == false else { return }
		let identifier = UUID()
		await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				guard Task.isCancelled == false else {
					continuation.resume()
					return
				}
				sleepers.append(Sleeper(
					identifier: identifier,
					deadline: instant.advanced(by: .seconds(interval)),
					continuation: continuation
				))
			}
		} onCancel: {
			Task { await self.release(identifier) }
		}
	}

	private func release(_ identifier: UUID) {
		guard let index = sleepers.firstIndex(where: { $0.identifier == identifier }) else { return }
		sleepers.remove(at: index).continuation.resume()
	}
}
