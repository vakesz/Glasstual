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
	private func engine(_ rules: MessageRule...) -> MessageRuleMatcher {
		MessageRuleMatcher { rules }
	}

	private func rule(matching pattern: String) -> MessageRule {
		var rule = MessageRule()
		rule.title = "Test"
		rule.match = pattern
		rule.ignoresContent = true
		rule.ignoresOperators = false
		return rule
	}

	private func channel(_ name: String, on session: TestServerSession) throws -> Conversation {
		let channel = try #require(session.findConversationOrCreate(name))
		channel.activate()
		return channel
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		let message = try #require(Message(line: line, on: session))
		session.receiveNumericReply(message)
	}

	private func shouldPrint(
		_ text: String,
		from sender: Prefix = Prefix(nickname: "alice", username: "user", address: "host",
		                             hostmask: "alice!user@host"),
		in destination: Conversation?,
		on session: TestServerSession,
		using engine: MessageRuleMatcher
	) -> Bool {
		engine.shouldPrintText(
			text,
			authoredBy: sender,
			destinedFor: destination,
			as: .privateMessage,
			onSession: session,
			receivedAt: Date(),
			wasEncrypted: false
		)
	}

	@Test("A matching rule that hides content stops the line, and anything else prints")
	func matchingRuleHidesTheLine() throws {
		let session = TestServerSession()
		let chat = try channel("#chat", on: session)
		let engine = engine(rule(matching: "spoiler"))

		#expect(shouldPrint("a spoiler here", in: chat, on: session, using: engine) == false)
		#expect(shouldPrint("nothing to hide", in: chat, on: session, using: engine))
	}

	@Test("A rule limited to channels leaves a private message alone")
	func ruleLimitedToChannelsIgnoresAQuery() throws {
		let session = TestServerSession()
		let chat = try channel("#chat", on: session)
		let query = try #require(session.findConversationOrCreate("alice", isDirect: true))
		var rule = rule(matching: "spoiler")
		rule.destination = .channels
		let engine = engine(rule)

		#expect(shouldPrint("a spoiler here", in: chat, on: session, using: engine) == false)
		#expect(shouldPrint("a spoiler here", in: query, on: session, using: engine))
	}

	@Test("A rule limited to named conversations matches only those")
	func ruleLimitedToNamedConversationsMatchesOnlyThose() throws {
		let session = TestServerSession()
		let chat = try channel("#chat", on: session)
		let other = try channel("#other", on: session)
		var rule = rule(matching: "spoiler")
		rule.destination = .specificItems
		rule.limitedChannelIDs = [chat.uniqueIdentifier]
		let engine = engine(rule)

		#expect(shouldPrint("a spoiler here", in: chat, on: session, using: engine) == false)
		#expect(shouldPrint("a spoiler here", in: other, on: session, using: engine))
	}

	@Test("A rule that ignores operators leaves an operator's line alone")
	func ruleThatIgnoresOperatorsExemptsThem() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.supportInfo.processConfigurationData("PREFIX=(ov)@+")
		let chat = try channel("#chat", on: session)
		try receive(":irc.example.net 353 me = #chat :@alice bob", on: session)
		var rule = rule(matching: "spoiler")
		rule.ignoresOperators = true
		let engine = engine(rule)
		let bob = Prefix(nickname: "bob", username: "user", address: "host", hostmask: "bob!user@host")

		#expect(shouldPrint("a spoiler here", in: chat, on: session, using: engine))
		#expect(shouldPrint("a spoiler here", from: bob, in: chat, on: session, using: engine) == false)
	}

	@Test("A rule that matches on the sender reads the sender's hostmask")
	func ruleMatchesOnTheSenderHostmask() throws {
		let session = TestServerSession()
		let chat = try channel("#chat", on: session)
		var rule = rule(matching: "")
		rule.senderMatch = "@host"
		let engine = engine(rule)
		let elsewhere = Prefix(nickname: "bob", username: "user", address: "other",
		                       hostmask: "bob!user@other")

		#expect(shouldPrint("anything", in: chat, on: session, using: engine) == false)
		#expect(shouldPrint("anything", from: elsewhere, in: chat, on: session, using: engine))
	}

	/// A rule may act on a line without hiding it, which is what the flood
	/// control and the action log are for.
	@Test("A matching rule that keeps content still prints the line")
	func matchingRuleThatKeepsContentStillPrints() throws {
		let session = TestServerSession()
		let chat = try channel("#chat", on: session)
		var rule = rule(matching: "spoiler")
		rule.ignoresContent = false
		let engine = engine(rule)

		#expect(shouldPrint("a spoiler here", in: chat, on: session, using: engine))
	}

	@Test("A command rule reads the events it was told to watch")
	func commandRuleReadsItsEvents() throws {
		let session = TestServerSession()
		let chat = try channel("#chat", on: session)
		var rule = MessageRule()
		rule.title = "Quiet joins"
		rule.events = [.userJoinedChannel]
		rule.ignoresContent = true
		rule.ignoresOperators = false
		let engine = engine(rule)

		#expect(engine.shouldPrintCommand(
			"JOIN", text: nil, authoredBy: Prefix(nickname: "alice", hostmask: "alice!user@host"),
			destinedFor: chat, onSession: session, receivedAt: Date(), messageParameters: []
		) == false)
		#expect(engine.shouldPrintCommand(
			"PART", text: nil, authoredBy: Prefix(nickname: "alice", hostmask: "alice!user@host"),
			destinedFor: chat, onSession: session, receivedAt: Date(), messageParameters: []
		))
	}

	/// The rule list is the one payload a pane, the engine and the import
	/// repair all name, so the name is pinned here as well as declared once.
	@Test("The rule list is stored under its declared name")
	func ruleListIsStoredUnderItsDeclaredName() {
		#expect(SettingsKeys.Rules.messageRules.name == "Rules -> Message Rules")
	}
}
