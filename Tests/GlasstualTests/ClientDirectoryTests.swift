// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Client directory bookkeeping")
struct ClientDirectoryTests {
	@Test("Wake clears automatic away, but preserves a manual change made while asleep")
	func screenAwayOwnership() {
		let client = TestClient()
		client.isLoggedIn = true
		client.setAwayForScreenSleep()
		#expect(client.automaticallyAwayForScreenSleep)
		client.clearAwayAfterScreenSleep()
		#expect(client.lastAwayMessage == nil)
		#expect(!client.automaticallyAwayForScreenSleep)
		client.setAwayForScreenSleep()
		client.toggleAwayStatus(true, withComment: "Back tomorrow")
		client.sentLines.removeAllObjects()
		client.clearAwayAfterScreenSleep()
		#expect(client.sentLines.count == 0)
		#expect(client.lastAwayMessage == "Back tomorrow")
	}

	@Test("Screen sleep and wake preserve manually selected away status")
	func screenSleepPreservesManualAway() {
		var preferences = ClientPreferences()
		preferences.awayOnScreenSleep = true
		let fixture = ClientEnvironmentFixture(preferences: preferences)
		let client = TestClient(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		client.isLoggedIn = true
		client.userIsAway = true
		client.lastAwayMessage = "Back tomorrow"
		let world = ClientDirectory(environment: fixture.environment)
		world.clientList = [client]
		world.prepareForScreenSleep()
		world.wakeFromScreenSleep()
		#expect(client.sentLines.count == 0)
		#expect(client.lastAwayMessage == "Back tomorrow")
	}

	@Test("Traffic counters accumulate the lengths they are told about")
	func trafficCountersAccumulateLengths() {
		let world = ClientDirectory()

		world.noteMessageSent(length: 12)
		world.noteMessageSent(length: 7)
		world.noteMessageReceived(length: 31)

		#expect(world.messagesSent == 2)
		#expect(world.messagesReceived == 1)
		#expect(world.bandwidthOut == 19)
		#expect(world.bandwidthIn == 31)
	}
}
