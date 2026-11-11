// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Metadata notifications", .timeLimit(.minutes(1)))
struct MetadataInboundTests {
	@Test("A member's, the user's and a channel's values are stored; strangers' are not")
	func targets() throws {
		let session = try makeMetadataSession()

		try session.receive(":irc.example.net METADATA peer display-name * :Peer Display")
		try session.receive(":irc.example.net METADATA ada color * :#112233")
		try session.receive(":irc.example.net METADATA #c display-name * :The Channel")
		try session.receive(":irc.example.net METADATA stranger display-name * :Nobody")

		#expect(session.findUser("peer")?.profile.displayName?.text == "Peer Display")
		#expect(session.myself?.profile.color?.hexString == "#112233")
		#expect(session.metadata.ownWireValues["color"] == "#112233")
		#expect(session.findConversation("#c")?.channelProfile.displayName?.text == "The Channel")
		#expect(session.findUser("stranger") == nil)
	}

	@Test("Keys other than the profile keys are not stored")
	func unknownKeys() throws {
		let session = try makeMetadataSession()

		try session.receive(":irc.example.net METADATA peer im.xmpp * :peer@example.org")

		#expect(session.findUser("peer")?.profile.isEmpty == true)
	}

	@Test("A value with restricted visibility is still used, and a missing value removes the key")
	func visibilityAndRemoval() throws {
		let session = try makeMetadataSession()

		try session.receive(":irc.example.net METADATA peer display-name staff :Secret Name")
		#expect(session.findUser("peer")?.profile.displayName?.text == "Secret Name")

		try session.receive(":irc.example.net METADATA peer display-name *")
		#expect(session.findUser("peer")?.profile.displayName == nil)
	}

	@Test("A metadata batch is processed as it arrives and refreshes views once when it closes")
	func batchIsLiveWithOneRefresh() throws {
		let session = try makeMetadataSession()
		let log = ProfileChangeLog(session)

		try session.receive(":irc.example.net BATCH +m metadata #c")
		try session.receive("@batch=m :irc.example.net METADATA peer display-name * :Peer")
		#expect(session.findUser("peer")?.profile.displayName?.text == "Peer")
		try session.receive("@batch=m :irc.example.net METADATA spoof color * :#800040")
		#expect(log.messages.isEmpty)

		try session.receive(":irc.example.net BATCH -m")

		#expect(log.messages.count == 1)
		#expect(log.messages.first?.nicknames == ["peer", "spoof"])
	}

	@Test("A sync batch may carry users and the channel")
	func syncBatchMixesTargets() throws {
		let session = try makeMetadataSession()

		try session.receive(":irc.example.net BATCH +s metadata #c")
		try session.receive("@batch=s :irc.example.net METADATA #c avatar * :https://example.org/c.png")
		try session.receive("@batch=s :irc.example.net METADATA peer avatar * :https://example.org/p.png")
		try session.receive(":irc.example.net BATCH -s")

		#expect(session.findConversation("#c")?.channelProfile.avatar != nil)
		#expect(session.findUser("peer")?.profile.avatar != nil)
	}

	@Test("A nick change keeps the profile")
	func nickChangeKeepsProfile() throws {
		let session = try makeMetadataSession()
		try session.receive(":irc.example.net METADATA peer display-name * :Peer")

		try session.receive(":peer!p@host NICK peer2")

		#expect(session.findUser("peer2")?.profile.displayName?.text == "Peer")
	}

	@Test("A disconnect clears profiles and the channel's")
	func disconnectClears() throws {
		let session = try makeMetadataSession()
		try session.receive(":irc.example.net METADATA #c display-name * :Chan")
		try session.receive(":irc.example.net METADATA ada display-name * :Me")

		session.resetAllPropertyValues()

		#expect(session.findConversation("#c")?.channelProfile.isEmpty == true)
		#expect(session.metadata.ownWireValues.isEmpty)
	}

	@Test("A user's change outside a batch is refreshed after a short pause")
	func debouncedRefresh() async throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = try makeMetadataSession()
		session.metadata.clock = clock.timerClock
		let log = ProfileChangeLog(session)

		try session.receive(":irc.example.net METADATA peer display-name * :Peer")
		try session.receive(":irc.example.net METADATA spoof display-name * :Spoof")
		#expect(log.messages.isEmpty)

		await clock.advance(by: 0.2)
		#expect(log.messages.count == 1)
	}

	@Test("A member's profile change redraws the member list")
	func profileChangeBumpsRevision() throws {
		let session = try makeMetadataSession()
		let members = try #require(session.findConversation("#c")?.memberInfo)
		let before = members.renderRevision

		try session.receive(":irc.example.net METADATA peer color * :#123456")

		#expect(members.renderRevision != before)
	}

	@Test("A notification title reads \"Display Name (nick)\", and a colliding name is left out")
	func notificationTitle() throws {
		let session = try makeMetadataSession()
		let channel = session.findConversation("#c")
		try session.receive(":irc.example.net METADATA peer display-name * :Peer Display")
		try session.receive(":irc.example.net METADATA spoof display-name * :peer")

		let title = session.notificationSenderTitle("peer", in: channel)
		#expect(title == String(localized: .ChatNotifications.titleDisplayNameNickname(
			"Peer Display", session.formatNickname("peer", in: channel)
		)))
		#expect(session.notificationSenderTitle("spoof", in: channel) == session.formatNickname("spoof", in: channel))
	}
}
