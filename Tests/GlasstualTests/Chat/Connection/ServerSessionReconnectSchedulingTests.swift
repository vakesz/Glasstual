// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** The ping and pong schedule is covered by `ConnectionTimerPolicy`;
 what happens after the connection has actually dropped is this timer. Two
 things go wrong silently here: a session that schedules nothing never comes
 back, and a session that restarts an already-pending run reconnects in a tight
 loop rather than every twenty seconds.

 A sleep-mode disconnect is a separate switch: the user who turned off
 "disconnect on sleep" expects to be reconnected on wake even when automatic
 reconnection is otherwise off. */
@MainActor
@Suite("Reconnect scheduling")
struct ServerSessionReconnectSchedulingTests {
	private func session(autoReconnect: Bool, autoSleepModeDisconnect: Bool = true) -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "mara", "username": "mara"])
		session.config.autoReconnect = autoReconnect
		session.config.autoSleepModeDisconnect = autoSleepModeDisconnect

		return session
	}

	@Test("Automatic reconnection off schedules nothing")
	func reconnectionOffSchedulesNothing() {
		let session = session(autoReconnect: false)

		session.startReconnectTimer()

		#expect(session.reconnect.timer.isActive == false)
	}

	@Test("Automatic reconnection on schedules a repeating run")
	func reconnectionOnSchedulesARepeatingRun() {
		let session = session(autoReconnect: true)
		defer { session.stopReconnectTimer() }

		session.startReconnectTimer()

		#expect(session.reconnect.timer.isActive)
	}

	/// A second drop while a reconnect is already pending must not restart the
	/// countdown, or the interval collapses towards zero.
	/** A fixed twenty seconds forever is a session that knocks at the same rate
	 whether the server bounced once or has been down since yesterday, and an
	 outage has every session on the network knock in lockstep. The delay doubles
	 to a five-minute ceiling, and the jitter takes up to a quarter back off so
	 the attempts spread out instead of arriving together. */
	@Test("The delay doubles up to the ceiling")
	func theDelayBacksOff() {
		let delay = { (attempt: UInt) in
			ConnectionTimerPolicy.reconnectDelay(attempt: attempt, jitter: 0)
		}

		#expect(delay(0) == ConnectionTimerPolicy.reconnectInterval)
		#expect(delay(1) == 40)
		#expect(delay(2) == 80)
		#expect(delay(3) == 160)
		#expect(delay(4) == ConnectionTimerPolicy.maximumReconnectInterval)
		#expect(delay(50) == ConnectionTimerPolicy.maximumReconnectInterval)
	}

	@Test("Jitter shortens the delay by at most a quarter, and never past zero")
	func jitterIsBounded() {
		for attempt in UInt(0) ... 8 {
			let full = ConnectionTimerPolicy.reconnectDelay(attempt: attempt, jitter: 0)

			for jitter in [0.0, 0.25, 0.5, 1.0, -3.0, 7.0] {
				let delay = ConnectionTimerPolicy.reconnectDelay(attempt: attempt, jitter: jitter)

				#expect(delay > 0)
				#expect(delay <= full)
				#expect(delay >= full * 0.75)
			}
		}
	}

	/// Each scheduled attempt has to wait longer than the last, or the backoff
	/// is a number nothing reads.
	@Test("Each scheduled run waits longer than the one before it")
	func consecutiveRunsGrow() {
		let session = session(autoReconnect: true)
		defer { session.stopReconnectTimer() }

		session.startReconnectTimer()
		let first = session.reconnect.timer.interval
		session.stopReconnectTimer()
		session.startReconnectTimer()
		let second = session.reconnect.timer.interval

		#expect(second > first)
		#expect(session.reconnect.attemptCount == 2)
	}

	/// Registration is the only evidence the endpoint is usable, so it is what
	/// clears the backoff — not a socket that connected and then dropped.
	@Test("Registering clears the backoff")
	func registrationClearsTheBackoff() {
		let session = session(autoReconnect: true)
		defer { session.stopReconnectTimer() }
		session.startReconnectTimer()
		session.stopReconnectTimer()
		session.startReconnectTimer()
		session.stopReconnectTimer()

		session.markAsLoggedIn()

		#expect(session.reconnect.attemptCount == 0)

		session.startReconnectTimer()

		let first = ConnectionTimerPolicy.reconnectInterval

		// The jitter is drawn at random, so the delay is a range, not a number.
		#expect(session.reconnect.timer.interval <= first)
		#expect(session.reconnect.timer.interval >= first * 0.75)
	}

	@Test("A pending run is left alone rather than restarted")
	func aPendingRunIsNotRestarted() {
		let session = session(autoReconnect: true)
		defer { session.stopReconnectTimer() }

		session.startReconnectTimer()
		let scheduled = session.reconnect.timer
		session.startReconnectTimer()

		#expect(session.reconnect.timer === scheduled)
		#expect(session.reconnect.timer.isActive)
	}

	@Test("Stopping clears the pending run, and stopping twice is harmless")
	func stoppingClearsThePendingRun() {
		let session = session(autoReconnect: true)

		session.startReconnectTimer()
		session.stopReconnectTimer()
		session.stopReconnectTimer()

		#expect(session.reconnect.timer.isActive == false)
	}

	/** After a sleep-mode disconnect the switch that decides is
	 `autoSleepModeDisconnect`, inverted: the user who asked not to be
	 disconnected on sleep is the one who wants reconnecting on wake, whatever
	 the general reconnection setting says. */
	@Test("A sleep-mode drop follows the disconnect-on-sleep setting instead")
	func sleepModeUsesTheSleepSetting() {
		let reconnecting = session(autoReconnect: false, autoSleepModeDisconnect: false)
		defer { reconnecting.stopReconnectTimer() }
		reconnecting.reconnect.isEnabledForSleepMode = true

		reconnecting.startReconnectTimer()

		#expect(reconnecting.reconnect.timer.isActive)

		let quiet = session(autoReconnect: true, autoSleepModeDisconnect: true)
		defer { quiet.stopReconnectTimer() }
		quiet.reconnect.isEnabledForSleepMode = true

		quiet.startReconnectTimer()

		#expect(quiet.reconnect.timer.isActive == false)
	}

	/// The run fires on a schedule, so it has to answer for a session that
	/// reconnected in the meantime by doing nothing at all.
	@Test("The scheduled run does nothing while the session is already connected")
	func theRunIsANoOperationWhileConnected() {
		let session = session(autoReconnect: true)
		session.setConnectionTransportForTesting(.connected)

		session.onReconnectTimer()

		#expect(session.isConnecting == false)
		#expect(session.sentLines.count == 0)
	}

	@Test("A refused reconnect retains the intent established by disconnect teardown")
	func refusedAttemptRearmsAfterTeardown() throws {
		let session = session(autoReconnect: true)
		defer { session.cancelReconnect() }
		session.config.serverList = []
		session.setConnectionTransportForTesting(.connected)
		session.reconnect.isEnabled = true

		session.changeStateOff()
		try #require(session.reconnect.timer.isActive)
		let firstDelay = session.reconnect.timer.interval

		// A one-shot timer stops itself before invoking its action.
		session.stopReconnectTimer()
		session.onReconnectTimer()

		#expect(!session.isConnecting)
		#expect(session.reconnect.isEnabled)
		#expect(session.reconnect.timer.isActive)
		#expect(session.reconnect.timer.interval > firstDelay)
		#expect(session.reconnect.attemptCount == 2)
	}

	@Test("Cancelling after teardown prevents a queued reconnect callback from restarting the schedule")
	func cancellationEndsReconnectIntent() {
		let session = session(autoReconnect: true)
		session.setConnectionTransportForTesting(.connected)
		session.reconnect.isEnabled = true
		session.changeStateOff()

		session.cancelReconnect()
		session.onReconnectTimer()

		#expect(!session.reconnect.isEnabled)
		#expect(!session.reconnect.timer.isActive)
		#expect(!session.isConnecting)
	}

	@Test("A disconnect with automatic reconnection disabled ends the reconnect intent")
	func disabledPolicyEndsReconnectIntent() {
		let session = session(autoReconnect: false)
		session.setConnectionTransportForTesting(.connected)
		session.reconnect.isEnabled = true
		session.reconnect.attemptCount = 3

		session.changeStateOff()

		#expect(!session.reconnect.isEnabled)
		#expect(!session.reconnect.timer.isActive)
		#expect(session.reconnect.attemptCount == 0)
	}
}
