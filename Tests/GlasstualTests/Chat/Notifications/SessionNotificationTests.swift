// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

/// The connection's notification path against a recorded presenter: the seam is
/// what makes it checkable at all, because nothing here asks the system for
/// permission to post or bounces a Dock icon.
@MainActor
@Suite("Session notifications")
struct SessionNotificationTests {
	private func fixture(notifiesAboutMentions: Bool = true, soundIsMuted: Bool = false)
		-> ChatEnvironmentFixture
	{
		var settings = ChatSettings()
		settings.notifyAboutMentions = notifiesAboutMentions
		settings.soundIsMuted = soundIsMuted

		return ChatEnvironmentFixture(settings: settings)
	}

	@Test("A highlight posts through the port, claims the alert and asks for attention")
	func highlightPostsThroughThePort() throws {
		let fixture = fixture()
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		let channel = try #require(session.findConversationOrCreate("#glasstual"))

		session.notifyEvent(.highlight, lineType: .privateMessage, target: channel, nickname: "alice", text: "hi")

		let posted = try #require(fixture.notifications.posted.first)
		#expect(fixture.notifications.posted.count == 1)
		/* The theme is not installed, so the nickname is formatted with
		 `NicknameFormat.default` rather than by reaching for a theme controller. */
		#expect(posted.title == "alice:")
		#expect(posted.subtitle == channel.name)
		#expect(posted.body == "hi")
		#expect(posted.alerts)
		#expect(posted.playsSound)
		#expect(fixture.notifications.attentionRequests == 1)
		#expect(fixture.notifications.claimedThreads == [posted.payload.threadIdentifier])
	}

	@Test("A quiet notification neither alerts nor asks for attention")
	func quietNotificationDoesNotAskForAttention() throws {
		let fixture = fixture()
		fixture.notifications.claimsAlert = false
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		let channel = try #require(session.findConversationOrCreate("#glasstual"))

		session.notifyEvent(.highlight, lineType: .privateMessage, target: channel, nickname: "alice", text: "hi")

		let posted = try #require(fixture.notifications.posted.first)
		#expect(posted.alerts == false)
		#expect(posted.playsSound == false)
		#expect(fixture.notifications.attentionRequests == 0)
	}

	/// The muted setting travels in the snapshot the session was handed, not
	/// as a second live read of the defaults store.
	@Test("The snapshot's muted switch takes the sound off the notification")
	func mutedSoundComesFromTheSnapshot() throws {
		let fixture = fixture(soundIsMuted: true)
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		let channel = try #require(session.findConversationOrCreate("#glasstual"))

		session.notifyEvent(.highlight, lineType: .privateMessage, target: channel, nickname: "alice", text: "hi")

		let posted = try #require(fixture.notifications.posted.first)
		#expect(posted.alerts)
		#expect(posted.playsSound == false)
	}

	/// The conversation the person is reading in the key window needs no banner,
	/// and both facts now come from the window port rather than the app delegate.
	@Test("A selected conversation in the key window posts nothing")
	func selectedConversationInKeyWindowPostsNothing() throws {
		let fixture = fixture()
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		let channel = try #require(session.findConversationOrCreate("#glasstual"))
		fixture.output.isKeyWindow = true
		fixture.output.select(channel)

		session.notifyEvent(.highlight, lineType: .privateMessage, target: channel, nickname: "alice", text: "hi")

		#expect(fixture.notifications.posted.isEmpty)
	}

	@Test("Mentions switched off refuse a highlight")
	func mentionsSwitchedOffRefuseAHighlight() throws {
		let fixture = fixture(notifiesAboutMentions: false)
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		let channel = try #require(session.findConversationOrCreate("#glasstual"))

		session.notifyEvent(.highlight, lineType: .privateMessage, target: channel, nickname: "alice", text: "hi")

		#expect(fixture.notifications.posted.isEmpty)
	}

	@Test("/notifysound names its sound through the notification port")
	func notifySoundPlaysThroughThePort() {
		let fixture = fixture()
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)

		session.sendCommand("/notifysound Beep")

		#expect(fixture.notifications.playedSounds == ["Beep"])
	}

	@Test("/notifybubble posts a bubble with the channel it names in its payload")
	func notifyBubblePostsThroughThePort() throws {
		let fixture = fixture()
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		let channel = try #require(session.findConversationOrCreate("#glasstual"))

		session.sendCommand("/notifybubble #glasstual something happened")

		let posted = try #require(fixture.notifications.posted.first)
		#expect(posted.body == "something happened")
		#expect(posted.payload.conversationIdentifier == channel.uniqueIdentifier)
		#expect(posted.playsSound == false)
	}
}
