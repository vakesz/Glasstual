// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** QUIT, KILL and NICK reach the conversations a person shares with the
 reader, in the order the sidebar lists them, and nothing else. */
@Suite("Membership fan-out")
@MainActor
struct ServerSessionMembershipFanOutTests {
	private func session() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		var settings = session.environment.settings
		settings.showJoinLeave = true
		session.chatSession?.applySettings(settings)
		session.forwardsProcessedMessages = true
		return session
	}

	private func channel(_ name: String, on session: TestServerSession) throws -> Conversation {
		let channel = try #require(session.findConversationOrCreate(name))
		channel.activate()
		return channel
	}

	private func query(_ name: String, on session: TestServerSession) throws -> Conversation {
		try #require(session.findConversationOrCreate(name, isDirect: true))
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		try session.processIncomingMessage(#require(Message(line: line, on: session)))
	}

	private func join(_ nickname: String, _ channels: [String], on session: TestServerSession) throws {
		for name in channels {
			try receive(":\(nickname)!u@example.org JOIN \(name)", on: session)
		}
	}

	/// The conversations that were printed into for `kind`, in print order.
	private func printedNames(of kind: ChatLineKind, on session: TestServerSession) -> [String] {
		(session.printedLines as NSArray).compactMap { $0 as? [String: Any] }
			.filter { ($0["lineType"] as? NSNumber) == NSNumber(value: kind.rawValue) }
			.compactMap { ($0["channel"] as? Conversation)?.name }
	}

	@Test("A QUIT prints into the shared channels in list order and into the person's query only")
	func quitPrintsWhereThePersonIs() throws {
		let session = session()
		_ = try channel("#one", on: session)
		_ = try channel("#two", on: session)
		_ = try channel("#three", on: session)
		_ = try query("alice", on: session)
		_ = try query("carol", on: session)
		try join("alice", ["#three", "#one"], on: session)
		try join("bob", ["#two"], on: session)
		let before = session.printedLines.count

		try receive(":alice!u@example.org QUIT :bye", on: session)

		#expect(printedNames(of: .quit, on: session) == ["#one", "#three", "alice"])
		#expect(session.printedLines.count > before)
	}

	@Test("The order follows the conversation list, not the order the person joined")
	func quitFollowsTheListOrder() throws {
		let session = session()
		let one = try channel("#one", on: session)
		let two = try channel("#two", on: session)
		let three = try channel("#three", on: session)
		try join("alice", ["#one", "#three"], on: session)
		session.conversationList = [three, two, one]

		try receive(":alice!u@example.org QUIT :bye", on: session)

		#expect(printedNames(of: .quit, on: session) == ["#three", "#one"])
	}

	@Test("Your own QUIT is printed into every conversation, shared or not")
	func localQuitPrintsEverywhere() throws {
		let session = session()
		session.userNickname = "me"
		try join("me", ["#one"], on: session)
		_ = try channel("#two", on: session)
		_ = try query("alice", on: session)

		try receive(":me!me@example.org QUIT :bye", on: session)

		#expect(Set(printedNames(of: .quit, on: session)).isSuperset(of: ["#one", "#two", "alice"]))
	}

	@Test("A KILL removes the person from the channels they are in and leaves the others")
	func killRemovesFromSharedChannels() throws {
		let session = session()
		let one = try channel("#one", on: session)
		let two = try channel("#two", on: session)
		try join("alice", ["#one"], on: session)
		try join("bob", ["#one", "#two"], on: session)

		try receive(":irc.example.net KILL alice :bad", on: session)

		#expect(one.memberExists("alice") == false)
		#expect(one.memberExists("bob"))
		#expect(two.memberExists("bob"))
	}

	@Test("A NICK renames the member and the person's query, and prints only where they are")
	func nickReachesSharedChannelsAndTheQuery() throws {
		let session = session()
		let one = try channel("#one", on: session)
		_ = try channel("#two", on: session)
		let alice = try query("alice", on: session)
		let carol = try query("carol", on: session)
		try join("alice", ["#one"], on: session)
		try join("bob", ["#two"], on: session)

		try receive(":alice!u@example.org NICK :alice2", on: session)

		#expect(one.memberExists("alice2"))
		#expect(one.memberExists("alice") == false)
		#expect(alice.name == "alice2")
		#expect(carol.name == "carol")
		#expect(printedNames(of: .nick, on: session) == ["#one", "alice2"])
	}

	@Test("A channel that has been closed is not printed into")
	func closedChannelIsSkipped() throws {
		let session = session()
		let one = try channel("#one", on: session)
		_ = try channel("#two", on: session)
		try join("alice", ["#one", "#two"], on: session)

		session.chatSession?.destroyConversation(one, options: [])
		try receive(":alice!u@example.org QUIT :bye", on: session)

		#expect(printedNames(of: .quit, on: session) == ["#two"])
	}

	@Test("Closing a conversation forgets the read marker sent for it")
	func closingForgetsTheReadMarker() throws {
		let session = session()
		let one = try channel("#one", on: session)
		let two = try channel("#two", on: session)
		let date = Date(timeIntervalSince1970: 1000)
		session.readMarkers.sentDates[one.uniqueIdentifier] = date
		session.readMarkers.sentDates[two.uniqueIdentifier] = date
		session.readMarkers.pendingConversations[one.uniqueIdentifier] = date

		session.chatSession?.destroyConversation(one, options: [])

		#expect(session.readMarkers.sentDates[one.uniqueIdentifier] == nil)
		#expect(session.readMarkers.pendingConversations[one.uniqueIdentifier] == nil)
		#expect(session.readMarkers.sentDates[two.uniqueIdentifier] == date)
	}
}
