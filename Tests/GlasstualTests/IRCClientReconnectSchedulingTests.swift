/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** The ping and pong schedule is covered by `IRCClientConnectionTimerPolicy`;
 what happens after the connection has actually dropped is this timer. Two
 things go wrong silently here: a client that schedules nothing never comes
 back, and a client that restarts an already-pending run reconnects in a tight
 loop rather than every twenty seconds.

 A sleep-mode disconnect is a separate switch: the user who turned off
 "disconnect on sleep" expects to be reconnected on wake even when automatic
 reconnection is otherwise off. */
@MainActor
@Suite("Reconnect scheduling")
struct IRCClientReconnectSchedulingTests {
	private func client(autoReconnect: Bool, autoSleepModeDisconnect: Bool = true) -> GLTTestClient {
		let client = GLTTestClient(configDictionary: ["nickname": "mara", "username": "mara"])
		client.config.autoReconnect = autoReconnect
		client.config.autoSleepModeDisconnect = autoSleepModeDisconnect

		return client
	}

	@Test("Automatic reconnection off schedules nothing")
	func reconnectionOffSchedulesNothing() {
		let client = client(autoReconnect: false)

		client.startReconnectTimer()

		#expect(client.reconnectTimer.isActive == false)
	}

	@Test("Automatic reconnection on schedules a repeating run")
	func reconnectionOnSchedulesARepeatingRun() {
		let client = client(autoReconnect: true)
		defer { client.stopReconnectTimer() }

		client.startReconnectTimer()

		#expect(client.reconnectTimer.isActive)
	}

	/// A second drop while a reconnect is already pending must not restart the
	/// countdown, or the interval collapses towards zero.
	@Test("A pending run is left alone rather than restarted")
	func aPendingRunIsNotRestarted() {
		let client = client(autoReconnect: true)
		defer { client.stopReconnectTimer() }

		client.startReconnectTimer()
		let scheduled = client.reconnectTimer
		client.startReconnectTimer()

		#expect(client.reconnectTimer === scheduled)
		#expect(client.reconnectTimer.isActive)
	}

	@Test("Stopping clears the pending run, and stopping twice is harmless")
	func stoppingClearsThePendingRun() {
		let client = client(autoReconnect: true)

		client.startReconnectTimer()
		client.stopReconnectTimer()
		client.stopReconnectTimer()

		#expect(client.reconnectTimer.isActive == false)
	}

	/** After a sleep-mode disconnect the switch that decides is
	 `autoSleepModeDisconnect`, inverted: the user who asked not to be
	 disconnected on sleep is the one who wants reconnecting on wake, whatever
	 the general reconnection setting says. */
	@Test("A sleep-mode drop follows the disconnect-on-sleep setting instead")
	func sleepModeUsesTheSleepSetting() {
		let reconnecting = client(autoReconnect: false, autoSleepModeDisconnect: false)
		defer { reconnecting.stopReconnectTimer() }
		reconnecting.reconnectEnabledBecauseOfSleepMode = true

		reconnecting.startReconnectTimer()

		#expect(reconnecting.reconnectTimer.isActive)

		let quiet = client(autoReconnect: true, autoSleepModeDisconnect: true)
		defer { quiet.stopReconnectTimer() }
		quiet.reconnectEnabledBecauseOfSleepMode = true

		quiet.startReconnectTimer()

		#expect(quiet.reconnectTimer.isActive == false)
	}

	/// The run fires on a schedule, so it has to answer for a client that
	/// reconnected in the meantime by doing nothing at all.
	@Test("The scheduled run does nothing while the client is already connected")
	func theRunIsANoOperationWhileConnected() {
		let client = client(autoReconnect: true)
		client.isConnected = true

		client.onReconnectTimer()

		#expect(client.isConnecting == false)
		#expect(client.sentLines.count == 0)
	}
}
