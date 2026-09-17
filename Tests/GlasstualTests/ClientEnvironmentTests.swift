// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Client environment")
struct ClientEnvironmentTests {
	@Test("A client made by a world carries that world's environment")
	func clientsInheritTheWorldEnvironment() {
		let fixture = ClientEnvironmentFixture()
		let client = fixture.clientDirectory.createClient(with: ClientConfig())

		#expect(client.clientDirectory === fixture.clientDirectory)
		#expect(client.output === fixture.output)
		#expect(client.menu === fixture.menu)
	}

	@Test("A preference the fixture was built with is what the client branches on")
	func clientsReadTheInjectedSnapshot() {
		var preferences = ClientPreferences()
		preferences.showJoinLeave = true
		preferences.defaultKickMessage = "so long"
		let fixture = ClientEnvironmentFixture(preferences: preferences)

		let client = fixture.clientDirectory.createClient(with: ClientConfig())

		#expect(client.environment.preferences.showJoinLeave)
		#expect(client.environment.preferences.defaultKickMessage == "so long")
	}

	@Test("Refreshing the world's snapshot republishes it to every client")
	func refreshReachesExistingClients() {
		let fixture = ClientEnvironmentFixture(preferences: ClientPreferences())
		let client = fixture.clientDirectory.createClient(with: ClientConfig())
		#expect(client.environment.preferences.showJoinLeave == false)

		var updated = ClientPreferences()
		updated.showJoinLeave = true
		fixture.clientDirectory.applyPreferences(updated)

		#expect(client.environment.preferences.showJoinLeave)
	}

	@Test("A tree item falls back to the declared defaults once its client has gone")
	func itemsWithoutAClientUseTheDeclaredDefaults() {
		let item = ChatItem()

		#expect(item.clientPreferences == ClientPreferences())
	}

	/** Each key is given a value nothing else in the store holds before the
	 snapshot is taken. Comparing a field against the key it is supposed to read
	 proves nothing on its own: at the shipped defaults most of these keys agree
	 with one another, so a field wired to the wrong key still matches. */
	@Test("The snapshot read from the store carries the store's values")
	func liveSnapshotReadsTheStore() {
		let kickMessage = Preferences.Commands.kickMessage
		let showJoinLeave = Preferences.Messages.showJoinLeave
		let identifyDelay = Preferences.Connection.autojoinDelayAfterIdentification
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

		let snapshot = ClientPreferences.current()

		#expect(snapshot.defaultKickMessage == "a reason no other key holds")
		#expect(snapshot.showJoinLeave == (showJoinLeave.defaultValue == false))
		#expect(snapshot.autojoinDelayAfterIdentification == 17)
	}

	/// The list is stored as an array and branched on as a set, so the read is
	/// worth its own check: a field left at the empty default would silently
	/// negotiate every capability the user switched off.
	@Test("The snapshot carries the capabilities the user switched off")
	func liveSnapshotReadsDisabledCapabilities() {
		let key = Preferences.Connection.disabledCapabilities
		let stored = key.storedValue
		defer { key.storedValue = stored }

		key.value = ["away-notify", "znc.in/playback"]

		#expect(ClientPreferences.current().disabledCapabilities == ["away-notify", "znc.in/playback"])

		key.reset()

		#expect(ClientPreferences.current().disabledCapabilities.isEmpty)
	}

	@Test("Services are shared by reference, so installing a window reaches the clients")
	func servicesAreSharedByReference() {
		let fixture = ClientEnvironmentFixture()
		let client = fixture.clientDirectory.createClient(with: ClientConfig())

		fixture.environment.services.output = nil

		#expect(client.output == nil)
	}
}
