/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** "Wait for NickServ before joining" has to end somewhere.

 When the client writes the IDENTIFY line itself, the write starts a thirty
 second deadline. When the user only turns the preference on — a bouncer that
 authenticates for them, a server that recognises their certificate — nothing
 writes it, so nothing armed a deadline and nothing armed the warnings either:
 the join list sat unsent, in silence, for the rest of the session. */
@MainActor
@Suite("Autojoin wait for identification")
struct ConnectionAutojoinWaitTests {
	private func waitingClient() -> GLTTestClient {
		let client = GLTTestClient(configDictionary: ["nickname": "mara", "autojoinWaitsForNickServ": true])
		client.markAsLoggedIn()
		client.startup.commands = .ready
		client.startup.requiresAuthentication = true

		return client
	}

	@Test("The wait arms both a warning and a deadline")
	func theWaitIsArmed() {
		let client = waitingClient()
		defer { client.stopAllTimers() }

		client.performAutoJoin()

		#expect(client.startup.authentication == .waiting)
		#expect(client.startup.authenticationTask != nil)
		#expect(client.autojoinDelayedWarningTimer.isActive)
	}

	/// Every automatic join stops the warnings on its way in, because most of
	/// them are about to join. Re-entering the wait has to put them back.
	@Test("Re-entering the wait keeps the warnings running")
	func reenteringTheWaitKeepsTheWarningsRunning() {
		let client = waitingClient()
		defer { client.stopAllTimers() }

		client.performAutoJoin()
		client.performAutoJoin()

		#expect(client.autojoinDelayedWarningTimer.isActive)
		#expect(client.startup.authentication == .waiting)
	}

	@Test("The warning says what is being waited for, and stops after three")
	func theWarningPrintsAndIsBounded() {
		let client = waitingClient()
		defer { client.stopAllTimers() }
		client.performAutoJoin()

		for _ in 0 ..< 5 {
			client.onAutojoinDelayedWarningTimer()
		}

		#expect(client.autojoinDelayedWarningCount == IRCClientAutojoinPolicy.maximumDelayedWarningCount)
		#expect(client.autojoinDelayedWarningTimer.isActive == false)

		let bodies = (client.printedLines as NSArray).compactMap {
			($0 as? [String: Any])?["messageBody"] as? String
		}

		#expect(bodies.contains(IRCConnectionStrings.autojoinDelayedForIdentification))
	}

	/// The user asked not to have the warnings, which is not the same as asking
	/// to wait for ever: the deadline still runs.
	@Test("Hidden warnings stop the printing, not the wait")
	func hiddenWarningsStillEndTheWait() {
		let client = waitingClient()
		defer { client.stopAllTimers() }
		client.config.hideAutojoinDelayedWarnings = true
		client.performAutoJoin()

		client.onAutojoinDelayedWarningTimer()

		#expect(client.autojoinDelayedWarningCount == 0)
		#expect(client.startup.authenticationTask != nil)
	}

	@Test("Autojoin proceeds once the deadline expires")
	func autojoinProceedsAfterTheDeadline() {
		let client = waitingClient()
		defer { client.stopAllTimers() }
		var channelConfig = ChannelConfig(channelName: "#glasstual")
		channelConfig.autoJoin = true
		client.findChannelOrCreate("#glasstual")?.updateConfig(channelConfig)
		client.performAutoJoin()

		#expect(client.isAutojoining == false)

		client.authenticationDeadlineExpired(for: client.startup.identifier)

		#expect(client.startup.authentication == .timedOut)
		#expect(client.isWaitingForNickServ == false)
		#expect(client.startup.canJoin)
		#expect(client.isAutojoining || client.isAutojoined)
	}

	/// The deadline belongs to one connection attempt. A reconnect replaces the
	/// coordinator, and the old attempt's expiry must not join for the new one.
	@Test("A deadline from a previous attempt is ignored")
	func aStaleDeadlineIsIgnored() {
		let client = waitingClient()
		defer { client.stopAllTimers() }
		client.performAutoJoin()
		let staleIdentifier = client.startup.identifier
		client.cancelConnectCommandSettling()

		client.authenticationDeadlineExpired(for: staleIdentifier)

		#expect(client.startup.authentication == .pending)
	}

	/** Identification that really is under way already has its own, shorter
	 deadline. Re-entering the wait turns the warnings back on and leaves that
	 deadline where it is, rather than restarting the clock on every automatic
	 join and pushing the answer further away each time. */
	@Test("A pending identification write keeps its own deadline")
	func aPendingIdentificationKeepsItsDeadline() {
		let client = waitingClient()
		defer { client.stopAllTimers() }

		client.noteNickServIdentificationWritten()

		#expect(client.startup.authentication == .waiting)

		client.performAutoJoin()

		#expect(client.startup.authentication == .waiting)
		#expect(client.autojoinDelayedWarningTimer.isActive)
	}
}
