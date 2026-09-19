// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** "Wait for NickServ before joining" has to end somewhere.

 When the session writes the IDENTIFY line itself, the write starts a thirty
 second deadline. When the user only turns the setting on — a bouncer that
 authenticates for them, a server that recognises their certificate — nothing
 writes it, so nothing armed a deadline and nothing armed the warnings either:
 the join list sat unsent, in silence, for the rest of the session. */
@MainActor
@Suite("Autojoin wait for identification")
struct ConnectionAutojoinWaitTests {
	private func waitingSession() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "mara", "autojoinWaitsForNickServ": true])
		session.markAsLoggedIn()
		session.startup.commands = .ready
		session.startup.requiresAuthentication = true

		return session
	}

	@Test("The wait arms both a warning and a deadline")
	func theWaitIsArmed() {
		let session = waitingSession()
		defer { session.stopAllTimers() }

		session.performAutoJoin()

		#expect(session.startup.authentication == .waiting)
		#expect(session.startup.authenticationTask != nil)
		#expect(session.autojoin.delayedWarningTimer.isActive)
	}

	/// Every automatic join stops the warnings on its way in, because most of
	/// them are about to join. Re-entering the wait has to put them back.
	@Test("Re-entering the wait keeps the warnings running")
	func reenteringTheWaitKeepsTheWarningsRunning() {
		let session = waitingSession()
		defer { session.stopAllTimers() }

		session.performAutoJoin()
		session.performAutoJoin()

		#expect(session.autojoin.delayedWarningTimer.isActive)
		#expect(session.startup.authentication == .waiting)
	}

	@Test("The warning says what is being waited for, and stops after three")
	func theWarningPrintsAndIsBounded() {
		let session = waitingSession()
		defer { session.stopAllTimers() }
		session.performAutoJoin()

		for _ in 0 ..< 5 {
			session.onAutojoinDelayedWarningTimer()
		}

		#expect(session.autojoin.delayedWarningCount == AutojoinPolicy.maximumDelayedWarningCount)
		#expect(session.autojoin.delayedWarningTimer.isActive == false)

		let bodies = (session.printedLines as NSArray).compactMap {
			($0 as? [String: Any])?["messageBody"] as? String
		}

		#expect(bodies.contains(String(localized: .IRC.joiningChannelsHasBeenDelayedBecause)))
	}

	/// The user asked not to have the warnings, which is not the same as asking
	/// to wait for ever: the deadline still runs.
	@Test("Hidden warnings stop the printing, not the wait")
	func hiddenWarningsStillEndTheWait() {
		let session = waitingSession()
		defer { session.stopAllTimers() }
		session.config.hideAutojoinDelayedWarnings = true
		session.performAutoJoin()

		session.onAutojoinDelayedWarningTimer()

		#expect(session.autojoin.delayedWarningCount == 0)
		#expect(session.startup.authenticationTask != nil)
	}

	@Test("Autojoin proceeds once the deadline expires")
	func autojoinProceedsAfterTheDeadline() {
		let session = waitingSession()
		defer { session.stopAllTimers() }
		var channelConfig = ConversationConfig(name: "#glasstual")
		channelConfig.autoJoin = true
		session.findConversationOrCreate("#glasstual")?.updateConfig(channelConfig)
		session.performAutoJoin()

		#expect(session.isAutojoining == false)

		session.authenticationDeadlineExpired(for: session.startup.identifier)

		#expect(session.startup.authentication == .timedOut)
		#expect(session.nickServ.isWaiting == false)
		#expect(session.startup.canJoin)
		#expect(session.isAutojoining || session.isAutojoined)
	}

	/// The deadline belongs to one connection attempt. A reconnect replaces the
	/// coordinator, and the old attempt's expiry must not join for the new one.
	@Test("A deadline from a previous attempt is ignored")
	func aStaleDeadlineIsIgnored() {
		let session = waitingSession()
		defer { session.stopAllTimers() }
		session.performAutoJoin()
		let staleIdentifier = session.startup.identifier
		session.cancelConnectCommandSettling()

		session.authenticationDeadlineExpired(for: staleIdentifier)

		#expect(session.startup.authentication == .pending)
	}

	/** Identification that really is under way already has its own, shorter
	 deadline. Re-entering the wait turns the warnings back on and leaves that
	 deadline where it is, rather than restarting the clock on every automatic
	 join and pushing the answer further away each time. */
	@Test("A pending identification write keeps its own deadline")
	func aPendingIdentificationKeepsItsDeadline() {
		let session = waitingSession()
		defer { session.stopAllTimers() }

		session.noteNickServIdentificationWritten()

		#expect(session.startup.authentication == .waiting)

		session.performAutoJoin()

		#expect(session.startup.authentication == .waiting)
		#expect(session.autojoin.delayedWarningTimer.isActive)
	}
}
