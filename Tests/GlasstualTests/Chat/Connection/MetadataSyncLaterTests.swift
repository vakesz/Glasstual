// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Postponed metadata sync", .timeLimit(.minutes(1)))
struct MetadataSyncLaterTests {
	private func syncs(_ session: TestServerSession) -> Int {
		session.wireLines.filter { $0 == "METADATA #c SYNC" }.count
	}

	@Test("774 with a delay waits at least that long")
	func waitsForRetryAfter() async throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = try makeMetadataSession()
		session.metadata.clock = clock.timerClock

		try session.receive(":irc.example.net 774 ada #c 3")
		await clock.advance(by: 2.9)
		#expect(syncs(session) == 0)
		await clock.advance(by: 0.2)
		#expect(syncs(session) == 1)
	}

	@Test("774 without a delay waits five seconds, and a repeat doubles the floor")
	func doublingFloor() async throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = try makeMetadataSession()
		session.metadata.clock = clock.timerClock

		try session.receive(":irc.example.net 774 ada #c")
		await clock.advance(by: 5.1)
		#expect(syncs(session) == 1)

		try session.receive(":irc.example.net 774 ada #c 1")
		await clock.advance(by: 9.9)
		#expect(syncs(session) == 1)
		await clock.advance(by: 0.2)
		#expect(syncs(session) == 2)
	}

	@Test("The delay is capped at five minutes")
	func clamped() async throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = try makeMetadataSession()
		session.metadata.clock = clock.timerClock

		try session.receive(":irc.example.net 774 ada #c 100000")
		await clock.advance(by: 300.1)

		#expect(syncs(session) == 1)
	}

	@Test("After six postponements the session gives up")
	func givesUp() async throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = try makeMetadataSession()
		session.metadata.clock = clock.timerClock

		for _ in 0 ..< 6 {
			try session.receive(":irc.example.net 774 ada #c 1")
			await clock.advance(by: 301)
		}
		try session.receive(":irc.example.net 774 ada #c 1")
		await clock.advance(by: 301)

		#expect(syncs(session) == 6)
		#expect(session.metadata.syncRetries["#c"] == nil)
	}

	@Test("Leaving the channel cancels its sync")
	func partCancels() async throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = try makeMetadataSession()
		session.metadata.clock = clock.timerClock

		try session.receive(":irc.example.net 774 ada #c 1")
		try session.receive(":ada!a@host PART #c")
		await clock.advance(by: 2)

		#expect(syncs(session) == 0)
	}

	@Test("A disconnect cancels every sync")
	func disconnectCancels() async throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = try makeMetadataSession()
		session.metadata.clock = clock.timerClock

		try session.receive(":irc.example.net 774 ada #c 1")
		session.resetAllPropertyValues()
		await clock.advance(by: 2)

		#expect(syncs(session) == 0)
	}
}
