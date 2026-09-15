/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Bouncer playback and notification policy")
struct IRCClientBouncerPlaybackTests {
	/// The server folds nicknames, so `*Status` and `*status` are one module.
	@Test("A ZNC module is recognised under the server's case folding", arguments: ["*status", "*Status", "*STATUS"])
	func zncModuleNicknameIsCaseFolded(_ nickname: String) {
		let client = TestClient()
		client.isConnectedToZNC = true

		#expect(client.nickname(nickname, isZNCUser: "status"))
		#expect(client.nickname(nickname, isZNCUser: "playback") == false)
	}

	@Test("Playback starts from the beginning when no timestamp is eligible")
	func playbackStartsFromBeginningWithoutAnEligibleTimestamp() {
		#expect(
			PlaybackRequestPolicy.command(
				successfulConnects: 1,
				onlyLatestOnFirstConnect: false,
				lastMessageServerTime: 1_700_000_000
			) == "play * 0"
		)
		#expect(
			PlaybackRequestPolicy.command(
				successfulConnects: 2,
				onlyLatestOnFirstConnect: true,
				lastMessageServerTime: 0
			) == "play * 0"
		)
	}

	@Test("A reconnect resumes from the last server timestamp, rounded up to a second")
	func playbackUsesRoundedServerTimestampAfterReconnect() {
		#expect(
			PlaybackRequestPolicy.command(
				successfulConnects: 2,
				onlyLatestOnFirstConnect: false,
				lastMessageServerTime: 1_700_000_000.6
			) == "play * 1700000001"
		)
	}

	@Test("A first connect may resume from the timestamp when the client is configured to")
	func playbackCanUseTimestampOnConfiguredFirstConnect() {
		#expect(
			PlaybackRequestPolicy.command(
				successfulConnects: 1,
				onlyLatestOnFirstConnect: true,
				lastMessageServerTime: 42
			) == "play * 42"
		)
	}

	@Test("Chat history the client asked for never posts a notification")
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

	@Test("Without batch support the historic flag stands in for the playback batch")
	func historicFallbackDoesNotPostWithoutBatchSupport() throws {
		try #expect(notificationDecision(
			ignoresPlayback: true,
			supportsBatch: false,
			isHistoric: true
		) == false)
		try #expect(notificationDecision(
			ignoresPlayback: true,
			supportsBatch: false,
			isHistoric: false
		))
	}

	@Test("A query always counts on the dock badge; a channel only when asked to")
	func dockUnreadCountFollowsThePublicMessagePreference() throws {
		try #expect(dockUnreadCount(isChannel: false, displaysPublicMessageCount: false) == 1)
		try #expect(dockUnreadCount(isChannel: true, displaysPublicMessageCount: false) == 0)
		try #expect(dockUnreadCount(isChannel: true, displaysPublicMessageCount: true) == 1)
	}

	/// Asks a client for a channel's dock count after one unread line.
	private func dockUnreadCount(isChannel: Bool, displaysPublicMessageCount: Bool) throws -> Int {
		var preferences = ClientPreferences()

		preferences.displayPublicMessageCountOnDockBadge = displaysPublicMessageCount

		let client = TestClient(
			configDictionary: ["nickname": "me"],
			nicknamePassword: nil,
			fixture: ClientEnvironmentFixture(preferences: preferences)
		)
		let channel = try #require(
			client.findChannelOrCreate(isChannel ? "#channel" : "someone", isPrivateMessage: isChannel == false)
		)

		client.setUnreadState(for: channel)

		return channel.dockUnreadCount
	}

	/// Asks a configured client whether a message carrying `batchType` may post.
	private func notificationDecision(
		isConnectedToBouncer: Bool = true,
		ignoresBouncerUsers: Bool = false,
		channelIsBouncerUser: Bool = false,
		ignoresPlayback: Bool = false,
		supportsBatch: Bool = false,
		batchType: String? = nil,
		isHistoric: Bool = false
	) throws -> Bool {
		let client = TestClient(configDictionary: [
			"nickname": "me",
			"zncIgnoreUserNotifications": ignoresBouncerUsers,
			"zncIgnorePlaybackNotifications": ignoresPlayback,
		])

		client.isConnectedToZNC = isConnectedToBouncer

		if supportsBatch {
			client.enableCapability(.batch)
		}

		let message = try #require(Message(line: ":sender!u@h PRIVMSG #channel :hello", on: client))

		if isHistoric {
			message.isHistoric = true
		}

		if let batchType {
			let batch = MessageBatch()
			batch.batchToken = "b1"
			batch.batchType = batchType
			message.parentBatchMessage = batch
		}

		let channelName = channelIsBouncerUser
			? IRCServerQuirks.ZNC.nickname(forModuleNamed: "status") : "#channel"

		let channel = try #require(client.findChannelOrCreate(channelName))

		return client.isSafeToPostNotification(for: message, in: channel)
	}
}
