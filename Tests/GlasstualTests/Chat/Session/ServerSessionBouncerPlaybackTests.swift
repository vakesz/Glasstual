// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Bouncer playback and notification policy")
struct ServerSessionBouncerPlaybackTests {
	/// The server folds nicknames, so `*Status` and `*status` are one module.
	@Test("A ZNC module is recognised under the server's case folding", arguments: ["*status", "*Status", "*STATUS"])
	func zncModuleNicknameIsCaseFolded(_ nickname: String) {
		let session = TestServerSession()
		session.znc.isConnected = true

		#expect(session.nickname(nickname, isZNCUser: "status"))
		#expect(session.nickname(nickname, isZNCUser: "playback") == false)
	}

	@Test("Playback starts from the beginning when no timestamp is eligible")
	func playbackStartsFromBeginningWithoutAnEligibleTimestamp() {
		#expect(
			zncPlaybackCommand(
				successfulConnects: 1,
				onlyLatestOnFirstConnect: false,
				lastMessageServerTime: 1_700_000_000
			) == "play * 0"
		)
		#expect(
			zncPlaybackCommand(
				successfulConnects: 2,
				onlyLatestOnFirstConnect: true,
				lastMessageServerTime: 0
			) == "play * 0"
		)
	}

	@Test("A reconnect resumes from the last server timestamp, rounded up to a second")
	func playbackUsesRoundedServerTimestampAfterReconnect() {
		#expect(
			zncPlaybackCommand(
				successfulConnects: 2,
				onlyLatestOnFirstConnect: false,
				lastMessageServerTime: 1_700_000_000.6
			) == "play * 1700000001"
		)
	}

	@Test("A first connect may resume from the timestamp when the session is configured to")
	func playbackCanUseTimestampOnConfiguredFirstConnect() {
		#expect(
			zncPlaybackCommand(
				successfulConnects: 1,
				onlyLatestOnFirstConnect: true,
				lastMessageServerTime: 42
			) == "play * 42"
		)
	}

	@Test("Chat history the session asked for never posts a notification")
	func requestedChatHistoryNeverPostsNotifications() throws {
		try #expect(notificationDecision(batchType: "chathistory") == false)
	}

	@Test("Ordinary server messages post when no bouncer is involved")
	func ordinaryServerMessagesPostWithoutABouncer() throws {
		try #expect(notificationDecision(isConnectedToBouncer: false))
	}

	@Test("A user the config marks as the bouncer does not post notifications")
	func configuredBouncerUsersDoNotPostNotifications() throws {
		try #expect(notificationDecision(
			ignoresBouncerUsers: true,
			channelIsBouncerUser: true
		) == false)
		try #expect(notificationDecision(ignoresBouncerUsers: true, channelIsBouncerUser: false))
	}

	@Test("Only the playback batch is silenced when playback is ignored")
	func playbackBatchDoesNotPostWhenPlaybackIsIgnored() throws {
		try #expect(notificationDecision(
			ignoresPlayback: true,
			supportsBatch: true,
			batchType: "znc.in/playback"
		) == false)
		try #expect(notificationDecision(
			ignoresPlayback: true,
			supportsBatch: true,
			batchType: "other"
		))
	}

	@Test("Without batch support the replay flag stands in for the playback batch")
	func replayFallbackDoesNotPostWithoutBatchSupport() throws {
		try #expect(notificationDecision(
			ignoresPlayback: true,
			supportsBatch: false,
			isReplayed: true
		) == false)
		try #expect(notificationDecision(
			ignoresPlayback: true,
			supportsBatch: false,
			isReplayed: false
		))
	}

	@Test("A query always counts on the dock badge; a channel only when asked to")
	func dockUnreadCountFollowsThePublicMessagePreference() throws {
		try #expect(dockUnreadCount(isChannel: false, displaysPublicMessageCount: false) == 1)
		try #expect(dockUnreadCount(isChannel: true, displaysPublicMessageCount: false) == 0)
		try #expect(dockUnreadCount(isChannel: true, displaysPublicMessageCount: true) == 1)
	}

	/// Asks a session for a channel's dock count after one unread line.
	private func dockUnreadCount(isChannel: Bool, displaysPublicMessageCount: Bool) throws -> Int {
		var settings = ChatSettings()

		settings.displayPublicMessageCountOnDockBadge = displaysPublicMessageCount

		let session = TestServerSession(
			configDictionary: ["nickname": "me"],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
		let channel = try #require(
			session.findConversationOrCreate(isChannel ? "#channel" : "someone", isDirect: isChannel == false)
		)

		session.setUnreadState(for: channel)

		return channel.dockUnreadCount
	}

	/// Asks a configured session whether a message carrying `batchType` may post.
	private func notificationDecision(
		isConnectedToBouncer: Bool = true,
		ignoresBouncerUsers: Bool = false,
		channelIsBouncerUser: Bool = false,
		ignoresPlayback: Bool = false,
		supportsBatch: Bool = false,
		batchType: String? = nil,
		isReplayed: Bool = false
	) throws -> Bool {
		let session = TestServerSession(configDictionary: [
			"nickname": "me",
			"zncIgnoreUserNotifications": ignoresBouncerUsers,
			"zncIgnorePlaybackNotifications": ignoresPlayback,
		])

		session.znc.isConnected = isConnectedToBouncer

		if supportsBatch {
			session.enableCapability(.batch)
		}

		var message = try #require(Message(line: ":sender!u@h PRIVMSG #channel :hello", on: session))

		if isReplayed {
			message.isReplayed = true
		}

		if let batchType {
			let batch = MessageBatch()
			batch.batchToken = "b1"
			batch.batchType = batchType
			message.parentBatchMessage = batch
		}

		let channelName = channelIsBouncerUser
			? ServerQuirks.ZNC.nickname(forModuleNamed: "status") : "#channel"

		let channel = try #require(session.findConversationOrCreate(channelName))

		return session.isSafeToPostNotification(for: message, in: channel)
	}
}
