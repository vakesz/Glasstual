// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Chat session bookkeeping")
struct ChatSessionTests {
	@Test("Wake clears automatic away, but preserves a manual change made while asleep")
	func screenAwayOwnership() {
		let session = TestServerSession()
		session.isLoggedIn = true
		session.setAwayForScreenSleep()
		#expect(session.away.forScreenSleep)
		session.clearAwayAfterScreenSleep()
		#expect(session.away.message == nil)
		#expect(!session.away.forScreenSleep)
		session.setAwayForScreenSleep()
		session.toggleAwayStatus(true, withComment: "Back tomorrow")
		session.sentLines.removeAllObjects()
		session.clearAwayAfterScreenSleep()
		#expect(session.sentLines.count == 0)
		#expect(session.away.message == "Back tomorrow")
	}

	@Test("Screen sleep and wake preserve manually selected away status")
	func screenSleepPreservesManualAway() {
		var settings = ChatSettings()
		settings.awayOnScreenSleep = true
		let fixture = ChatEnvironmentFixture(settings: settings)
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		session.isLoggedIn = true
		session.away.isAway = true
		session.away.message = "Back tomorrow"
		let chatSession = ChatSession(environment: fixture.environment)
		chatSession.sessions = [session]
		chatSession.prepareForScreenSleep()
		chatSession.wakeFromScreenSleep()
		#expect(session.sentLines.count == 0)
		#expect(session.away.message == "Back tomorrow")
	}

	@Test("Traffic counters accumulate the lengths they are told about")
	func trafficCountersAccumulateLengths() {
		let chatSession = ChatSession()

		chatSession.noteMessageSent(length: 12)
		chatSession.noteMessageSent(length: 7)
		chatSession.noteMessageReceived(length: 31)

		#expect(chatSession.messagesSent == 2)
		#expect(chatSession.messagesReceived == 1)
		#expect(chatSession.bandwidthOut == 19)
		#expect(chatSession.bandwidthIn == 31)
	}
}
