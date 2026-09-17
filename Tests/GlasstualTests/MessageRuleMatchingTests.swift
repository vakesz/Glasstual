// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// What a rule decides about one arriving line: which conversations it applies
/// to, which senders it exempts, and whether the line is still printed.
@MainActor
@Suite("Message rule matching")
struct MessageRuleMatchingTests {
	private func engine(_ rules: MessageRule...) -> MessageRuleEngine {
		MessageRuleEngine { rules }
	}

	private func rule(matching pattern: String) -> MessageRule {
		var rule = MessageRule()
		rule.title = "Test"
		rule.match = pattern
		rule.ignoresContent = true
		rule.ignoresOperators = false
		return rule
	}

	private func channel(_ name: String, on client: TestClient) throws -> Channel {
		let channel = try #require(client.findChannelOrCreate(name))
		channel.activate()
		return channel
	}

	private func receive(_ line: String, on client: TestClient) throws {
		let message = try #require(Message(line: line, on: client))
		client.receiveNumericReply(message)
	}

	private func shouldPrint(
		_ text: String,
		from sender: Prefix = Prefix(nickname: "alice", username: "user", address: "host",
		                             hostmask: "alice!user@host"),
		in destination: Channel?,
		on client: TestClient,
		using engine: MessageRuleEngine
	) -> Bool {
		engine.shouldPrintText(
			text,
			authoredBy: sender,
			destinedFor: destination,
			as: .privateMessage,
			onClient: client,
			receivedAt: Date(),
			wasEncrypted: false
		)
	}

	@Test("A matching rule that hides content stops the line, and anything else prints")
	func matchingRuleHidesTheLine() throws {
		let client = TestClient()
		let chat = try channel("#chat", on: client)
		let engine = engine(rule(matching: "spoiler"))

		#expect(shouldPrint("a spoiler here", in: chat, on: client, using: engine) == false)
		#expect(shouldPrint("nothing to hide", in: chat, on: client, using: engine))
	}

	@Test("A rule limited to channels leaves a private message alone")
	func ruleLimitedToChannelsIgnoresAQuery() throws {
		let client = TestClient()
		let chat = try channel("#chat", on: client)
		let query = try #require(client.findChannelOrCreate("alice", isPrivateMessage: true))
		var rule = rule(matching: "spoiler")
		rule.destination = .channels
		let engine = engine(rule)

		#expect(shouldPrint("a spoiler here", in: chat, on: client, using: engine) == false)
		#expect(shouldPrint("a spoiler here", in: query, on: client, using: engine))
	}

	@Test("A rule limited to named conversations matches only those")
	func ruleLimitedToNamedConversationsMatchesOnlyThose() throws {
		let client = TestClient()
		let chat = try channel("#chat", on: client)
		let other = try channel("#other", on: client)
		var rule = rule(matching: "spoiler")
		rule.destination = .specificItems
		rule.limitedChannelIDs = [chat.uniqueIdentifier]
		let engine = engine(rule)

		#expect(shouldPrint("a spoiler here", in: chat, on: client, using: engine) == false)
		#expect(shouldPrint("a spoiler here", in: other, on: client, using: engine))
	}

	@Test("A rule that ignores operators leaves an operator's line alone")
	func ruleThatIgnoresOperatorsExemptsThem() throws {
		let client = TestClient(configDictionary: ["nickname": "me", "username": "me"])
		client.supportInfo.processConfigurationData("PREFIX=(ov)@+")
		let chat = try channel("#chat", on: client)
		try receive(":irc.example.net 353 me = #chat :@alice bob", on: client)
		var rule = rule(matching: "spoiler")
		rule.ignoresOperators = true
		let engine = engine(rule)
		let bob = Prefix(nickname: "bob", username: "user", address: "host", hostmask: "bob!user@host")

		#expect(shouldPrint("a spoiler here", in: chat, on: client, using: engine))
		#expect(shouldPrint("a spoiler here", from: bob, in: chat, on: client, using: engine) == false)
	}

	@Test("A rule that matches on the sender reads the sender's hostmask")
	func ruleMatchesOnTheSenderHostmask() throws {
		let client = TestClient()
		let chat = try channel("#chat", on: client)
		var rule = rule(matching: "")
		rule.senderMatch = "@host"
		let engine = engine(rule)
		let elsewhere = Prefix(nickname: "bob", username: "user", address: "other",
		                       hostmask: "bob!user@other")

		#expect(shouldPrint("anything", in: chat, on: client, using: engine) == false)
		#expect(shouldPrint("anything", from: elsewhere, in: chat, on: client, using: engine))
	}

	/// A rule may act on a line without hiding it, which is what the flood
	/// control and the action log are for.
	@Test("A matching rule that keeps content still prints the line")
	func matchingRuleThatKeepsContentStillPrints() throws {
		let client = TestClient()
		let chat = try channel("#chat", on: client)
		var rule = rule(matching: "spoiler")
		rule.ignoresContent = false
		let engine = engine(rule)

		#expect(shouldPrint("a spoiler here", in: chat, on: client, using: engine))
	}

	@Test("A command rule reads the events it was told to watch")
	func commandRuleReadsItsEvents() throws {
		let client = TestClient()
		let chat = try channel("#chat", on: client)
		var rule = MessageRule()
		rule.title = "Quiet joins"
		rule.events = [.userJoinedChannel]
		rule.ignoresContent = true
		rule.ignoresOperators = false
		let engine = engine(rule)

		#expect(engine.shouldPrintCommand(
			"JOIN", text: nil, authoredBy: Prefix(nickname: "alice", hostmask: "alice!user@host"),
			destinedFor: chat, onClient: client, receivedAt: Date(), messageParameters: []
		) == false)
		#expect(engine.shouldPrintCommand(
			"PART", text: nil, authoredBy: Prefix(nickname: "alice", hostmask: "alice!user@host"),
			destinedFor: chat, onClient: client, receivedAt: Date(), messageParameters: []
		))
	}

	/// The rules are stored under the name they had when they belonged to a
	/// bundled extension, so a user's rules survive that extension going away.
	@Test("The rule list keeps the defaults name it was stored under")
	func ruleListKeepsItsStoredName() {
		#expect(Preferences.Rules.messageRules.name == "Glasstual Chat Filter Extension -> Filters")
	}
}
