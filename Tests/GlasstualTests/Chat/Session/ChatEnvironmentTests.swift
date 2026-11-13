// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Chat environment")
struct ChatEnvironmentTests {
	@Test("A session made by a chat session carries that chat session's environment")
	func sessionsInheritTheChatSessionEnvironment() {
		let fixture = ChatEnvironmentFixture()
		let session = fixture.chatSession.createSession(with: ServerConfig())

		#expect(session.chatSession === fixture.chatSession)
		#expect(session.output === fixture.output)
		#expect(session.menu === fixture.menu)
	}

	@Test("A preference the fixture was built with is what the session branches on")
	func sessionsReadTheInjectedSnapshot() {
		var settings = ChatSettings()
		settings.showJoinLeave = true
		settings.defaultKickMessage = "so long"
		let fixture = ChatEnvironmentFixture(settings: settings)

		let session = fixture.chatSession.createSession(with: ServerConfig())

		#expect(session.environment.settings.showJoinLeave)
		#expect(session.environment.settings.defaultKickMessage == "so long")
	}

	@Test("Refreshing the chat session's snapshot republishes it to every session")
	func refreshReachesExistingSessions() {
		let fixture = ChatEnvironmentFixture(settings: ChatSettings())
		let session = fixture.chatSession.createSession(with: ServerConfig())
		#expect(session.environment.settings.showJoinLeave == false)

		var updated = ChatSettings()
		updated.showJoinLeave = true
		fixture.chatSession.applySettings(updated)

		#expect(session.environment.settings.showJoinLeave)
	}

	@Test("A sidebar item falls back to the declared defaults once its session has gone")
	func itemsWithoutASessionUseTheDeclaredDefaults() {
		let item = ChatItem()

		#expect(item.chatSettings == ChatSettings())
	}

	/** Each key is given a value nothing else in the store holds before the
	 snapshot is taken. Comparing a field against the key it is supposed to read
	 proves nothing on its own: at the shipped defaults most of these keys agree
	 with one another, so a field wired to the wrong key still matches. */
	@Test("The snapshot read from the store carries the store's values")
	func liveSnapshotReadsTheStore() {
		let kickMessage = SettingsKeys.Commands.kickMessage
		let showJoinLeave = SettingsKeys.Messages.showJoinLeave
		let identifyDelay = SettingsKeys.Connection.autojoinDelayAfterIdentification
		let storedKickMessage = kickMessage.storedValue
		let storedShowJoinLeave = showJoinLeave.storedValue
		let storedIdentifyDelay = identifyDelay.storedValue
		defer {
			kickMessage.storedValue = storedKickMessage
			showJoinLeave.storedValue = storedShowJoinLeave
			identifyDelay.storedValue = storedIdentifyDelay
		}

		kickMessage.value = "a reason no other key holds"
		showJoinLeave.value = showJoinLeave.defaultValue == false
		identifyDelay.value = 17

		let snapshot = ChatSettings.current()

		#expect(snapshot.defaultKickMessage == "a reason no other key holds")
		#expect(snapshot.showJoinLeave == (showJoinLeave.defaultValue == false))
		#expect(snapshot.autojoinDelayAfterIdentification == 17)
	}

	/// The list is stored as an array and branched on as a set, so the read is
	/// worth its own check: a field left at the empty default would silently
	/// negotiate every capability the user switched off.
	@Test("The snapshot carries the capabilities the user switched off")
	func liveSnapshotReadsDisabledCapabilities() {
		let key = SettingsKeys.Connection.disabledCapabilities
		let stored = key.storedValue
		defer { key.storedValue = stored }

		key.value = ["away-notify", "znc.in/playback"]

		#expect(ChatSettings.current().disabledCapabilities == ["away-notify", "znc.in/playback"])

		key.reset()

		#expect(ChatSettings.current().disabledCapabilities.isEmpty)
	}

	@Test("Services are shared by reference, so installing a window reaches the sessions")
	func servicesAreSharedByReference() {
		let fixture = ChatEnvironmentFixture()
		let session = fixture.chatSession.createSession(with: ServerConfig())

		fixture.environment.services.output = nil

		#expect(session.output == nil)
	}
}
