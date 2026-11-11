// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Metadata subscription")
struct MetadataSubscriptionTests {
	private let subscribe = "METADATA * SUB display-name avatar color"

	@Test("The profile keys are subscribed after the welcome, before joining")
	func subscribedAfterWelcome() throws {
		let session = try makeMetadataSession(joined: false)

		#expect(session.wireLines.contains(subscribe))
		#expect(session.capabilityLines.contains("REQ draft/metadata-2"))
	}

	@Test("With before-connect, SUB goes out before CAP END")
	func subscribedBeforeConnect() throws {
		let session = makeRegistrationSession()

		try session.negotiate("batch draft/metadata-2=before-connect")

		#expect(session.wireLines.contains(subscribe))
		#expect(session.isLoggedIn == false)
	}

	@Test("max-subs limits the keys, in order of preference")
	func maximumSubscriptions() throws {
		let session = try makeMetadataSession(offer: "batch draft/metadata-2=max-subs=2", joined: false)

		#expect(session.wireLines.contains("METADATA * SUB display-name avatar"))
	}

	@Test("Nothing is subscribed with Show Server Profiles off")
	func settingOff() throws {
		let session = try makeMetadataSession(showsServerProfiles: false, joined: false)

		#expect(session.wireLines.contains { $0.hasPrefix("METADATA") } == false)
	}

	@Test("770 subscribes, duplicates are fine, and TOO_MANY_SUBS drops the rest")
	func subscriptionReplies() throws {
		let session = try makeMetadataSession(joined: false)

		try session.receive(":irc.example.net FAIL METADATA TOO_MANY_SUBS avatar :Too many")
		#expect(session.metadata.requestedSubscription == ["display-name"])

		try session.receive(":irc.example.net 770 ada display-name display-name")
		#expect(session.metadata.subscribed == ["display-name"])

		try session.receive(":irc.example.net 771 ada :display-name")
		#expect(session.metadata.subscribed.isEmpty)
	}

	@Test("KEY_INVALID drops a key, and KEY_NO_PERMISSION leaves it subscribed")
	func keyRefusals() throws {
		let session = try makeMetadataSession(joined: false)

		try session.receive(":irc.example.net FAIL METADATA KEY_INVALID color :Invalid")
		try session.receive(":irc.example.net FAIL METADATA KEY_NO_PERMISSION * avatar :No permission")

		#expect(session.metadata.requestedSubscription == ["display-name", "avatar"])
	}

	@Test("Turning the setting off unsubscribes and forgets other people's profiles")
	func unsubscribeOnToggle() throws {
		let session = try makeMetadataSession()
		try session.receive(":irc.example.net 770 ada display-name avatar color")
		try session.receive(":irc.example.net METADATA peer display-name * :Peer")

		session.environment.settings.showsServerProfiles = false
		session.serverProfilesSettingDidChange()

		#expect(session.wireLines.last == "METADATA * UNSUB display-name avatar color")
		#expect(session.findUser("peer")?.profile.isEmpty == true)
	}

	@Test("CAP DEL forgets every profile")
	func capabilityWithdrawn() throws {
		let session = try makeMetadataSession()
		try session.receive(":irc.example.net METADATA peer display-name * :Peer")
		let log = ProfileChangeLog(session)

		try session.receive(":irc.example.net CAP ada DEL :draft/metadata-2")

		#expect(session.findUser("peer")?.profile.isEmpty == true)
		#expect(log.messages.last?.isReset == true)
	}
}
