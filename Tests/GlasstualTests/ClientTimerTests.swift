/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** A `TimerClock` the test moves itself.

 Nothing here waits: `wait(_:)` parks the timer's task until ``advance(by:)``
 carries the virtual instant past its deadline, so a four-minute interval and a
 one-second interval cost the same and neither can be shaken loose by a busy
 machine. `advance(by:)` yields around each step because the timer does its
 work in a `Task`, which only runs when the test suspends.

 Every parked task has to be let go before the test ends, which is what
 ``finish()`` is for: a cancelled timer's task stays parked in `wait(_:)`
 forever otherwise, since a clock the test owns has no cancellation of its own.
 */
@MainActor
private final class TestClock {
	private struct Sleeper {
		let deadline: ContinuousClock.Instant
		let continuation: CheckedContinuation<Void, Never>
	}

	private var instant = ContinuousClock.now
	private var sleepers: [Sleeper] = []

	/// The clock to hand a `ClientTimer`.
	var timerClock: TimerClock {
		TimerClock(
			now: { [self] in instant },
			wait: { [self] interval in await wait(interval) }
		)
	}

	/// Moves the virtual instant forward and lets everything it woke run.
	func advance(by seconds: TimeInterval) async {
		await settle()

		instant = instant.advanced(by: .seconds(seconds))

		/* A repeating timer re-arms while it is being woken, so waking is
		 repeated until nothing else is due: the new deadline is always later
		 than the instant that woke the old one, so this ends. */
		while resumeDue() {
			await settle()
		}
	}

	/// Lets the tasks the test has already started reach their next wait.
	func settle() async {
		for _ in 0 ..< 8 {
			await Task.yield()
		}
	}

	/// Releases every parked task, whatever its deadline says.
	func finish() {
		let parked = sleepers

		sleepers.removeAll()

		for sleeper in parked {
			sleeper.continuation.resume()
		}
	}

	private func wait(_ interval: TimeInterval) async {
		guard Task.isCancelled == false else {
			return
		}

		let deadline = instant.advanced(by: .seconds(interval))

		await withCheckedContinuation { continuation in
			sleepers.append(Sleeper(deadline: deadline, continuation: continuation))
		}
	}

	private func resumeDue() -> Bool {
		let due = sleepers.filter { $0.deadline <= instant }

		guard due.isEmpty == false else {
			return false
		}

		sleepers.removeAll { $0.deadline <= instant }

		for sleeper in due {
			sleeper.continuation.resume()
		}

		return true
	}
}

@Suite("Client timer")
@MainActor
struct ClientTimerTests {
	@Test("A timer that has not been started is not active")
	func startsInactive() {
		let clock = TestClock()
		let timer = ClientTimer(clock: clock.timerClock) { _ in }

		#expect(timer.isActive == false)
		#expect(timer.timeRemaining == 0)
	}

	@Test("Stopping a timer keeps it from firing")
	func cancellationPreventsTheAction() async {
		let clock = TestClock()
		var fired = 0
		let timer = ClientTimer(clock: clock.timerClock) { _ in fired += 1 }

		defer { clock.finish() }

		timer.start(60, repeats: true)
		#expect(timer.isActive)

		timer.stop()
		#expect(timer.isActive == false)

		await clock.advance(by: 600)

		#expect(fired == 0)
	}

	@Test("A one-shot timer fires once its interval is up, and not before")
	func oneShotFiresWhenTheIntervalIsUp() async {
		let clock = TestClock()
		var fired = 0
		let timer = ClientTimer(clock: clock.timerClock) { _ in fired += 1 }

		defer { clock.finish() }

		timer.start(60)

		await clock.advance(by: 59)
		#expect(fired == 0)
		#expect(timer.isActive)

		await clock.advance(by: 1)
		#expect(fired == 1)
		#expect(timer.isActive == false)

		await clock.advance(by: 600)
		#expect(fired == 1)
	}

	@Test("A running timer reports the rest of its interval")
	func timeRemainingCountsDown() async {
		let clock = TestClock()
		let timer = ClientTimer(clock: clock.timerClock) { _ in }

		defer { clock.finish() }

		timer.start(60)
		#expect(timer.timeRemaining == 60)

		await clock.advance(by: 45)
		#expect(timer.timeRemaining == 15)

		await clock.advance(by: 15)
		#expect(timer.timeRemaining == 0)
	}

	@Test("Restarting a timer replaces the pending run rather than adding one")
	func restartingReplacesThePendingRun() async {
		let clock = TestClock()
		var fired = 0
		let timer = ClientTimer(clock: clock.timerClock) { _ in fired += 1 }

		defer { clock.finish() }

		timer.start(60)
		await clock.advance(by: 30)

		/* The restart puts the whole interval back, so the thirty seconds the
		 first run had already spent count for nothing. */
		timer.start(60)
		await clock.advance(by: 30)
		#expect(fired == 0)

		await clock.advance(by: 30)
		#expect(fired == 1)
	}

	@Test("A repeating timer fires once per interval")
	func repeatingFiresEveryInterval() async {
		let clock = TestClock()
		var fired = 0
		let timer = ClientTimer(clock: clock.timerClock) { _ in fired += 1 }

		defer { clock.finish() }

		timer.start(60, repeats: true)

		for expected in 1 ... 4 {
			await clock.advance(by: 60)

			#expect(fired == expected)
			#expect(timer.isActive)
		}
	}

	@Test("A repeating timer stops itself once it has run its iterations")
	func boundedRepeatStopsItself() async {
		let clock = TestClock()
		var fired = 0
		let timer = ClientTimer(clock: clock.timerClock) { _ in fired += 1 }

		defer { clock.finish() }

		timer.start(60, repeats: true, iterations: 2)

		await clock.advance(by: 60)
		#expect(fired == 1)
		#expect(timer.isActive)

		await clock.advance(by: 60)
		#expect(fired == 2)
		#expect(timer.isActive == false)

		await clock.advance(by: 600)
		#expect(fired == 2)
	}

	/// The action can stop the timer that called it, which is how the IRC layer
	/// ends a poll from inside its own handler.
	@Test("A repeating timer the action stops does not fire again")
	func theActionCanStopItsOwnTimer() async {
		let clock = TestClock()
		var fired = 0
		let timer = ClientTimer(clock: clock.timerClock) { timer in
			fired += 1
			timer.stop()
		}

		defer { clock.finish() }

		timer.start(60, repeats: true)

		await clock.advance(by: 60)
		#expect(fired == 1)
		#expect(timer.isActive == false)

		await clock.advance(by: 600)
		#expect(fired == 1)
	}

	/// A timer nobody holds any more has to stop: the owner that dropped it —
	/// a disconnected client, a closed channel — is not there to be called back.
	@Test("A timer nobody holds any more stops firing")
	func aReleasedTimerStopsFiring() async {
		let clock = TestClock()
		var fired = 0

		defer { clock.finish() }

		do {
			let timer = ClientTimer(clock: clock.timerClock) { _ in fired += 1 }

			timer.start(60, repeats: true)

			await clock.settle()
		}

		await clock.advance(by: 600)

		#expect(fired == 0)
	}
}
