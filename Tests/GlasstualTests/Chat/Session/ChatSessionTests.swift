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
		session.applyAutoAway(owner: .screenSleep, message: "Be back later")
		#expect(session.away.autoReason == .screenSleep)
		session.applyAutoAway(owner: nil, message: nil)
		#expect(session.away.message == nil)
		#expect(session.away.autoReason == nil)
		session.applyAutoAway(owner: .screenSleep, message: "Be back later")
		session.toggleAwayStatus(true, withComment: "Back tomorrow")
		session.sentLines.removeAllObjects()
		session.applyAutoAway(owner: nil, message: nil)
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

	@Test("A Focus filter sets away on the networks it reaches and ends with it")
	func focusFilterAwayIsPerNetwork() {
		let fixture = ChatEnvironmentFixture(settings: ChatSettings())
		let reached = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		let other = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		reached.isLoggedIn = true
		other.isLoggedIn = true
		let chatSession = ChatSession(environment: fixture.environment)
		chatSession.sessions = [reached, other]

		var filter = FocusFilterState(mode: .setAway, networkIdentifiers: [reached.config.uniqueIdentifier])
		filter.awayMessage = "heads down"
		chatSession.setFocusFilter(filter)
		#expect(reached.away.autoReason == .focus)
		#expect(reached.away.message == "heads down")
		#expect(other.away.autoReason == nil)

		chatSession.setFocusFilter(nil)
		#expect(reached.away.autoReason == nil)
		#expect(reached.away.message == nil)
	}

	@Test("A channel added to a server is saved at once, not at the next periodic save")
	func addedConversationIsSaved() throws {
		let key = SettingsKeys.Sessions.serverSessions
		let original = key.propertyListValue
		defer { key.propertyListValue = original }
		key.propertyListValue = nil

		let fixture = ChatEnvironmentFixture(settings: ChatSettings())
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		let chatSession = ChatSession(environment: fixture.environment)
		chatSession.sessions = [session]

		chatSession.addConversation(with: ConversationConfig(name: "#added"), on: session)

		let stored = try #require(key.propertyListValue)
		let configs = try SettingsSessionArchive.decode(stored)
		#expect(configs.count == 1)
		#expect(configs.first?.conversationList.map(\.name) == ["#added"])
	}

	@Test("A restored Focus filter is ignored when the system delivered one after it was read")
	func staleFocusRestoreIsIgnored() {
		let fixture = ChatEnvironmentFixture(settings: ChatSettings())
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		session.isLoggedIn = true
		let chatSession = ChatSession(environment: fixture.environment)
		chatSession.sessions = [session]

		let generation = chatSession.focusFilterGeneration
		chatSession.setFocusFilter(nil)

		let applied = chatSession.restoreFocusFilter(
			FocusFilterState(mode: .muteAndSetAway),
			readAtGeneration: generation
		)

		#expect(applied == false)
		#expect(chatSession.focusFilter == nil)
		#expect(session.away.autoReason == nil)
	}

	@Test("A restored Focus filter applies when nothing was delivered while it was read")
	func currentFocusRestoreApplies() {
		let fixture = ChatEnvironmentFixture(settings: ChatSettings())
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		session.isLoggedIn = true
		let chatSession = ChatSession(environment: fixture.environment)
		chatSession.sessions = [session]

		let filter = FocusFilterState(mode: .muteAndSetAway)
		let applied = chatSession.restoreFocusFilter(filter, readAtGeneration: chatSession.focusFilterGeneration)

		#expect(applied)
		#expect(chatSession.focusFilter == filter)
		#expect(session.away.autoReason == .focus)
	}

	@Test("Removing a Focus filter counts as a delivery too")
	func clearingTheFocusFilterBumpsTheGeneration() {
		let chatSession = ChatSession(environment: ChatEnvironmentFixture(settings: ChatSettings()).environment)
		let before = chatSession.focusFilterGeneration

		chatSession.setFocusFilter(nil)
		#expect(chatSession.focusFilterGeneration == before + 1)

		chatSession.setFocusFilter(FocusFilterState())
		#expect(chatSession.focusFilterGeneration == before + 2)
	}

	@Test("The higher-priority reason takes over and the away ends with the last one")
	func overlappingReasonsShareOneAway() {
		let fixture = ChatEnvironmentFixture(settings: ChatSettings())
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		session.isLoggedIn = true
		let chatSession = ChatSession(environment: fixture.environment)
		chatSession.sessions = [session]

		chatSession.setAutoAwayReason(.screenSleep, holds: true)
		let sentAfterFirst = session.sentLines.count
		chatSession.setAutoAwayReason(.idle, holds: true)
		#expect(session.away.autoReason == .idle)
		#expect(session.sentLines.count == sentAfterFirst)

		chatSession.setAutoAwayReason(.idle, holds: false)
		#expect(session.away.autoReason == .screenSleep)
		chatSession.setAutoAwayReason(.screenSleep, holds: false)
		#expect(session.away.autoReason == nil)
		#expect(session.away.message == nil)
	}

	@Test("A manual away is never taken over or cleared by an automatic reason")
	func manualAwayWins() {
		let fixture = ChatEnvironmentFixture(settings: ChatSettings())
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		session.isLoggedIn = true
		session.toggleAwayStatus(true, withComment: "Back tomorrow")
		let chatSession = ChatSession(environment: fixture.environment)
		chatSession.sessions = [session]

		chatSession.setFocusFilter(FocusFilterState(mode: .muteAndSetAway))
		chatSession.setAutoAwayReason(.idle, holds: true)
		chatSession.setAutoAwayReason(.idle, holds: false)
		chatSession.setFocusFilter(nil)

		#expect(session.away.autoReason == nil)
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
