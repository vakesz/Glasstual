/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/**
 Where a ``ClientTimer`` reads the time and where it waits.

 Production is the continuous clock, and nothing in the app substitutes another
 one. Tests do: the intervals the IRC layer schedules run from a second to
 several minutes, and a suite that waits for them either takes minutes or
 shrinks them to a hundredth of a second and then fails on a machine that was
 merely busy. A clock the test steps by hand asks the timer the same questions
 with no clock left in the answer.
 */
@MainActor
struct TimerClock {
	/// The instant a running interval measures itself against.
	var now: @MainActor () -> ContinuousClock.Instant

	/// Waits `interval` seconds, returning early if the task is cancelled.
	var wait: @MainActor (_ interval: TimeInterval) async -> Void

	static let continuous = TimerClock(
		now: { .now },
		wait: { try? await Task.sleep(for: .seconds($0)) }
	)
}

/**
 A cancellable timer for main-actor work.

 Everything the IRC layer schedules — pings, reconnects, autojoin pacing, ISON
 and WHO sweeps, read-marker debouncing, user timed commands — acts on
 main-actor state when it fires. A `Task` on the continuous clock puts the work
 where that state lives and makes stopping a timer an ordinary cancellation,
 rather than a dispatch source whose handler has to hop back.

 The continuous clock keeps counting while the machine sleeps, which is what
 these intervals mean: a connection that has heard nothing for four minutes has
 timed out whether or not the display was asleep for some of it. It is the
 default and the only clock the app uses; a test passes ``TimerClock`` one it
 steps itself.
 */
@MainActor
final class ClientTimer {
	private let action: @MainActor (ClientTimer) -> Void
	private let clock: TimerClock
	private var task: Task<Void, Never>?

	/// When the current interval started.
	private(set) var startTime: ContinuousClock.Instant
	private(set) var interval: TimeInterval = 0
	private(set) var repeats = false
	/// How often a repeating timer fires before it stops; zero is unbounded.
	private(set) var iterations: UInt = 0
	private(set) var currentIteration: UInt = 0

	init(clock: TimerClock = .continuous, action: @escaping @MainActor (ClientTimer) -> Void) {
		self.action = action
		self.clock = clock

		startTime = clock.now()
	}

	deinit {
		task?.cancel()
	}

	var isActive: Bool {
		task != nil
	}

	/// How long the current interval still has to run, or zero once it is up.
	var timeRemaining: TimeInterval {
		max(0, interval - startTime.duration(to: clock.now()).timeInterval)
	}

	func start(_ interval: TimeInterval, repeats: Bool = false, iterations: UInt = 0) {
		precondition(interval > 0)

		stop()

		self.interval = interval
		self.repeats = repeats
		self.iterations = iterations
		currentIteration = 0
		startTime = clock.now()

		task = Task { [weak self, clock] in
			while Task.isCancelled == false {
				await clock.wait(interval)

				guard Task.isCancelled == false, let self else { return }

				fire()

				guard isActive else { return }
			}
		}
	}

	func stop() {
		task?.cancel()
		task = nil
	}

	private func fire() {
		currentIteration += 1

		if repeats == false || (iterations > 0 && currentIteration >= iterations) {
			stop()
		} else {
			startTime = clock.now()
		}

		action(self)
	}
}

private extension Duration {
	/// The duration in seconds, the unit every interval in the IRC layer uses.
	var timeInterval: TimeInterval {
		TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
	}
}
