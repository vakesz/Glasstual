/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/**
 A cancellable timer for main-actor work.

 Everything the IRC layer schedules — pings, reconnects, autojoin pacing, ISON
 and WHO sweeps, read-marker debouncing, user timed commands — acts on
 main-actor state when it fires. A `Task` on the continuous clock puts the work
 where that state lives and makes stopping a timer an ordinary cancellation,
 rather than a dispatch source whose handler has to hop back.

 The continuous clock keeps counting while the machine sleeps, which is what
 these intervals mean: a connection that has heard nothing for four minutes has
 timed out whether or not the display was asleep for some of it.
 */
@MainActor
final class ClientTimer {
	private let action: @MainActor (ClientTimer) -> Void
	private var task: Task<Void, Never>?

	/// When the current interval started.
	private(set) var startTime: ContinuousClock.Instant = .now
	private(set) var interval: TimeInterval = 0
	private(set) var repeats = false
	/// How often a repeating timer fires before it stops; zero is unbounded.
	private(set) var iterations: UInt = 0
	private(set) var currentIteration: UInt = 0

	init(action: @escaping @MainActor (ClientTimer) -> Void) {
		self.action = action
	}

	deinit {
		task?.cancel()
	}

	var isActive: Bool {
		task != nil
	}

	/// How long the current interval still has to run, or zero once it is up.
	var timeRemaining: TimeInterval {
		max(0, interval - startTime.duration(to: .now).timeInterval)
	}

	func start(_ interval: TimeInterval, repeats: Bool = false, iterations: UInt = 0) {
		precondition(interval > 0)

		stop()

		self.interval = interval
		self.repeats = repeats
		self.iterations = iterations
		currentIteration = 0
		startTime = .now

		task = Task { [weak self] in
			while Task.isCancelled == false {
				try? await Task.sleep(for: .seconds(interval))

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
			startTime = .now
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
