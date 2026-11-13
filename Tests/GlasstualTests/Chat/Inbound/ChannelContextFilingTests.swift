// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// A private message tagged with a channel is drawn in that channel, as long
/// as the channel is joined, the other party is in it, and the setting allows.
@MainActor
@Suite("channel-context filing")
struct ChannelContextFilingTests {
	private func session(
		members: [String] = ["bot"],
		showsInChannel: Bool = true
	) throws -> (TestServerSession, Conversation) {
		var settings = ChatSettings.current()
		settings.showChannelContextMessagesInChannel = showsInChannel
		let session = TestServerSession(
			configDictionary: ["nickname": "me", "username": "me"],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
		session.userNickname = "me"
		session.markAsLoggedIn()
		session.enableCapability(.messageTags)
		session.enableCapability(.batch)
		session.forwardsProcessedMessages = true
		let channel = try #require(session.findConversationOrCreate("#chan"))
		channel.activate()
		for member in members {
			channel.addUser(session.findUserOrCreate(member))
		}
		return (session, channel)
	}

	private func feed(_ lines: [String], to session: TestServerSession) throws {
		for line in lines {
			let message = try #require(Message(line: line, on: session))
			if session.filterBatchCommandIncomingData(message) {
				continue
			}
			if message.command == "BATCH" {
				session.receiveBatch(message)
			} else {
				session.processIncomingMessage(message)
			}
		}
	}

	private func lastPrinted(by session: TestServerSession) throws -> [String: Any] {
		try #require((session.printedLines as NSArray).lastObject as? [String: Any])
	}

	@Test("A tagged notice from a member lands in the channel as a private line", arguments: [
		"+draft/channel-context", "+channel-context",
	])
	func landsInChannel(_ tag: String) throws {
		let (session, channel) = try session()

		try feed(["@\(tag)=#chan :bot!b@h NOTICE me :hi"], to: session)

		let line = try lastPrinted(by: session)
		#expect((line["channel"] as? Conversation) === channel)
		#expect(line["channelContext"] as? String == "#chan")
		#expect((line["lineType"] as? NSNumber)?.intValue == Int(ChatLineKind.notice.rawValue))
		#expect(session.findConversation("bot") == nil)
	}

	@Test("A tagged private message lands in the channel and opens no query")
	func privmsgLandsInChannel() throws {
		let (session, channel) = try session()

		try feed(["@+draft/channel-context=#chan :bot!b@h PRIVMSG me :result"], to: session)

		let line = try lastPrinted(by: session)
		#expect((line["channel"] as? Conversation) === channel)
		#expect(session.findConversation("bot") == nil)
	}

	@Test("A sender who is not in the channel, an unjoined channel and the setting off all stay in the query")
	func guardsKeepTheQuery() throws {
		let (session, _) = try session(members: [])
		try feed(["@+draft/channel-context=#chan :bot!b@h PRIVMSG me :not a member"], to: session)
		var line = try lastPrinted(by: session)
		#expect((line["channel"] as? Conversation)?.name == "bot")
		#expect(line["channelContext"] as? String == "#chan")

		try feed(["@+draft/channel-context=#elsewhere :bot!b@h PRIVMSG me :unjoined"], to: session)
		line = try lastPrinted(by: session)
		#expect((line["channel"] as? Conversation)?.name == "bot")
		#expect(line["channelContext"] as? String == "#elsewhere")

		let (other, _) = try self.session(showsInChannel: false)
		try feed(["@+draft/channel-context=#chan :bot!b@h PRIVMSG me :setting off"], to: other)
		line = try lastPrinted(by: other)
		#expect((line["channel"] as? Conversation)?.name == "bot")
	}

	@Test("The tag on a channel message and an invalid channel name are ignored")
	func ignoredWhereItDoesNotApply() throws {
		let (session, channel) = try session()

		try feed(["@+draft/channel-context=#other :bot!b@h PRIVMSG #chan :public"], to: session)
		var line = try lastPrinted(by: session)
		#expect((line["channel"] as? Conversation) === channel)
		#expect(line["channelContext"] == nil)

		try feed(["@+draft/channel-context=notachannel :bot!b@h PRIVMSG me :odd"], to: session)
		line = try lastPrinted(by: session)
		#expect((line["channel"] as? Conversation)?.name == "bot")
		#expect(line["channelContext"] == nil)
	}

	@Test("Inside the query's own history page the line stays in the query")
	func queryHistoryPageStaysInQuery() throws {
		let (session, _) = try session()

		try feed([
			":irc.example.net BATCH +h chathistory bot",
			"@batch=h;+draft/channel-context=#chan :bot!b@h PRIVMSG me :old",
			":irc.example.net BATCH -h",
		], to: session)

		let line = try lastPrinted(by: session)
		#expect((line["channel"] as? Conversation)?.name == "bot")
		#expect(line["channelContext"] as? String == "#chan")
	}
}

/// Replying privately from a channel tags the message with the channel.
@MainActor
@Suite("Private replies from a channel")
struct PrivateReplySendingTests {
	private func session(messageTags: Bool = true, isupport: String? = nil) throws -> (TestServerSession, Conversation) {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.userNickname = "me"
		session.markAsLoggedIn()
		session.setConnectionTransportForTesting(.connected)
		if messageTags {
			session.enableCapability(.messageTags)
		}
		if let isupport {
			session.supportInfo.processConfigurationData(isupport)
		}
		let channel = try #require(session.findConversationOrCreate("#chan"))
		channel.activate()
		return (session, channel)
	}

	private func sent(by session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func printed(by session: TestServerSession) -> [[String: Any]] {
		(session.printedLines as NSArray).compactMap { $0 as? [String: Any] }
	}

	@Test("/whisper sends a tagged private message and shows it in the channel")
	func whisperSendsTagged() async throws {
		let (session, channel) = try session()

		session.sendCommand("whisper bot !help", completeTarget: true, target: "#chan")

		try await Eventually.until("the line to go out") { sent(by: session).isEmpty == false }
		#expect(sent(by: session) == ["@+draft/channel-context=#chan PRIVMSG bot :!help"])
		let line = try #require(printed(by: session).last)
		#expect((line["channel"] as? Conversation) === channel)
		#expect(line["privatePeer"] as? String == "bot")
		#expect(line["channelContext"] as? String == "#chan")
	}

	@Test("A reply identifier adds +draft/reply")
	func replyIdentifierIsTagged() async throws {
		let (session, channel) = try session()

		session.sendPrivateReply(NSAttributedString(string: "sure"), as: .privmsg, to: "bot", in: channel, replyIdentifier: "abc")

		try await Eventually.until("the line to go out") { sent(by: session).isEmpty == false }
		let line = try #require(sent(by: session).first)
		#expect(line.contains("+draft/channel-context=#chan"))
		#expect(line.contains("+draft/reply=abc"))
		#expect(line.hasSuffix("PRIVMSG bot :sure"))
	}

	@Test("Without message-tags, or with the tag denied, nothing is sent and the user is told", arguments: [
		(false, nil as String?), (true, "CLIENTTAGDENY=*"),
	])
	func refusedWithoutTheTag(_ messageTags: Bool, _ isupport: String?) throws {
		let (session, channel) = try session(messageTags: messageTags, isupport: isupport)

		#expect(session.sendPrivateReply(NSAttributedString(string: "hi"), as: .privmsg, to: "bot", in: channel) == false)

		#expect(sent(by: session).isEmpty)
		#expect(printed(by: session).last?["messageBody"] as? String == String(localized: .IRC.privateReplyNotSent))
	}

	@Test("/whisper outside a channel says where to use it")
	func whisperOutsideAChannel() throws {
		let (session, _) = try session()

		session.sendCommand("whisper bot hi", completeTarget: false)

		#expect(sent(by: session).isEmpty)
		#expect(printed(by: session).last?["messageBody"] as? String == String(localized: .IRC.whisperNeedsChannel))
	}
}
