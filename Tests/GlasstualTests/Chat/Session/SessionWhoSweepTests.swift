// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Timed WHO sweeps")
struct SessionWhoSweepTests {
	private func session() -> TestServerSession {
		TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
	}

	/// A WHO whose reply never came sits in front of every later request and
	/// makes their replies read as its own. The sweep expires those so the
	/// user's own request pairs with the replies it is waiting for.
	@Test("A sweep the server never answered is expired at the next tick")
	func unansweredSweepExpiresAtTheNextTick() throws {
		let session = session()
		session.markAsLoggedIn()
		let channel = try #require(session.findConversationOrCreate("#sweep"))
		channel.activate()

		#expect(session.config.sendWhoCommandRequestsToChannels)

		let now = Date(timeIntervalSinceReferenceDate: 1000)
		session.requestedCommands.recordWhoRequestOpened(
			for: "#sweep",
			sentAt: now.addingTimeInterval(-UserTrackingWhoBatchPolicy.timerInterval),
			expiresWithNextSweep: true
		)
		session.requestedCommands.recordWhoRequestOpenedAsVisible()
		#expect(session.requestedCommands.visibleWhoRequest == false)

		session.onWhoTimer(now: now)

		#expect(session.requestedCommands.visibleWhoRequest)
		#expect(session.sentLines.contains { ($0 as? String)?.hasPrefix("WHO ") == true })
	}

	/// Committed before the send guards, the initial WHO flag stood even when
	/// the setting or the channel size kept the request from going out, and
	/// enabling the setting mid-session left those channels without one.
	@Test("A channel WHO is kept from going out is not marked as having answered")
	func withheldRequestIsNotMarkedSent() throws {
		let session = session()
		session.markAsLoggedIn()
		let channel = try #require(session.findConversationOrCreate("#quiet"))
		channel.activate()
		session.config.sendWhoCommandRequestsToChannels = false

		session.onWhoTimer()

		#expect(channel.sentInitialWhoRequest == false)
		#expect(session.requestedCommands.hasOpenHiddenWhoRequest == false)

		/* Enabled mid-session, the sweep sends the initial WHO the flag would
		 otherwise have claimed was already answered. */
		session.config.sendWhoCommandRequestsToChannels = true

		session.onWhoTimer()

		#expect(channel.sentInitialWhoRequest)
		#expect(session.requestedCommands.hasOpenHiddenWhoRequest)
	}

	/// An initial WHO may be in flight immediately before the timer sends its
	/// periodic one. The first delayed `315` must close the initial request, not
	/// the fresh periodic request behind it.
	@Test("An initial WHO survives the next timer tick and its delayed terminator")
	func initialWhoSurvivesTickAndDelayedTerminator() throws {
		let session = session()
		session.markAsLoggedIn()
		let channel = try #require(session.findConversationOrCreate("#initial"))
		channel.activate()

		session.sendInitialWhoRequest(to: channel)
		#expect(session.requestedCommands.hasOpenHiddenWhoRequest)

		session.onWhoTimer(now: Date(timeIntervalSinceReferenceDate: 1000))
		try session.receiveNumericReply(#require(Message(line: ":irc.example.net 315 me #initial :End of /WHO list", on: session)))

		#expect(session.requestedCommands.hasOpenHiddenWhoRequest)

		try session.receiveNumericReply(#require(Message(line: ":irc.example.net 315 me #initial :End of /WHO list", on: session)))

		#expect(session.requestedCommands.hasOpenHiddenWhoRequest == false)
	}
}
