// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// `draft/channel-rename`: a server renames a channel instead of parting and
/// joining its members, and the conversation, members and history stay.
@MainActor
@Suite("Channel rename")
struct ServerSessionChannelRenameTests {
	private func session() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.setConnectionTransportForTesting(.connected)
		session.userNickname = "me"
		session.markAsLoggedIn()
		session.enableCapability([.channelRename])
		return session
	}

	private func joinedChannel(_ name: String, on session: TestServerSession) throws -> Conversation {
		let channel = try #require(session.findConversationOrCreate(name))
		channel.activate()
		return channel
	}

	private func rename(_ line: String, on session: TestServerSession, replayed: Bool = false) throws {
		var message = try #require(Message(line: line, on: session))
		message.isReplayed = replayed
		session.receiveRename(message)
	}

	@Test("The conversation keeps its identity, members and topic under the new name")
	func renameKeepsTheConversation() throws {
		let session = session()
		let channel = try joinedChannel("#old", on: session)
		channel.topic = "kept topic"
		let member = try #require(channel.memberInfo)
		member.addMember(Member(user: session.findUserOrCreate("alice"), prefixes: session.currentUserPrefixes))
		let identifier = channel.uniqueIdentifier

		try rename(":server RENAME #old #new :Better name", on: session)

		#expect(session.findConversation("#new") === channel)
		#expect(session.findConversation("#old") == nil)
		#expect(channel.name == "#new")
		#expect(channel.uniqueIdentifier == identifier)
		#expect(channel.topic == "kept topic")
		#expect(channel.status == .joined)
		#expect(channel.memberInfo?.memberList.map(\.user.nickname) == ["alice"])
		#expect(session.conversationList.count(where: { $0 === channel }) == 1)
	}

	@Test("History is keyed by the conversation identifier, which a rename does not change")
	func renameLeavesTheHistoryKeyAlone() throws {
		let session = session()
		let channel = try joinedChannel("#old", on: session)
		let key = channel.uniqueIdentifier

		try rename(":server RENAME #old #new", on: session)

		#expect(channel.uniqueIdentifier == key)
		#expect(channel.uniqueIdentifier == session.findConversation("#new")?.uniqueIdentifier)
	}

	@Test("The saved configuration follows the new name and keeps autojoin")
	func renameUpdatesTheStoredConfiguration() throws {
		let session = session()
		let channel = try joinedChannel("#old", on: session)
		channel.autoJoin = true
		session.updateStoredConversationList()

		try rename(":server RENAME #old #new", on: session)

		let stored = try #require(session.config.conversationList.first { $0.uniqueIdentifier == channel.uniqueIdentifier })
		#expect(stored.name == "#new")
		#expect(stored.autoJoin)
		#expect(session.config.conversationList.count(where: { $0.name == "#old" }) == 0)
	}

	@Test("A rename that only changes case is applied and is no collision")
	func caseOnlyRename() throws {
		let session = session()
		let channel = try joinedChannel("#chat", on: session)

		try rename(":server RENAME #chat #Chat", on: session)

		#expect(channel.name == "#Chat")
		#expect(session.conversationList.count(where: { $0.isChannel }) == 1)
	}

	@Test("A saved entry that already has the new name is kept under another name, with its history")
	func renameKeepsAnUnjoinedEntry() throws {
		let session = session()
		let live = try joinedChannel("#old", on: session)
		let saved = try #require(session.findConversationOrCreate("#new"))
		saved.autoJoin = true
		#expect(saved.status != .joined)
		let savedIdentifier = saved.uniqueIdentifier
		let liveIdentifier = live.uniqueIdentifier

		try rename(":server RENAME #old #new", on: session)

		#expect(session.findConversation("#new") === live)
		#expect(live.uniqueIdentifier == liveIdentifier)
		// Nothing is deleted: the saved entry is still listed, with its own history key.
		#expect(session.conversationList.contains { $0 === saved })
		#expect(saved.uniqueIdentifier == savedIdentifier)
		#expect(saved.name == String(localized: .IRC.channelRenamePreviousName("#new")))
		#expect(saved.autoJoin == false)
		// A space cannot occur in a channel name on the wire, so no RENAME can name this entry.
		#expect(saved.name.contains(" "))
		#expect(session.findConversation(saved.name) === saved)
		#expect(session.conversationList.count(where: { $0.isChannel }) == 2)
		let stored = try #require(session.config.conversationList.first { $0.uniqueIdentifier == savedIdentifier })
		#expect(stored.name == saved.name)
		#expect(stored.autoJoin == false)
	}

	@Test("A second collision on the same name gets a numbered label of its own")
	func repeatedCollisionsAreNumbered() throws {
		let session = session()
		let firstLive = try joinedChannel("#a", on: session)
		let firstSaved = try #require(session.findConversationOrCreate("#new"))
		try rename(":server RENAME #a #new", on: session)
		firstLive.status = .parted
		let secondLive = try joinedChannel("#b", on: session)

		try rename(":server RENAME #b #new", on: session)

		#expect(secondLive.name == "#new")
		#expect(firstLive.name != "#new")
		#expect(firstSaved.name == String(localized: .IRC.channelRenamePreviousName("#new")))
		#expect(firstLive.name == String(localized: .IRC.channelRenamePreviousNameNumbered("#new", 2)))
		#expect(firstLive.autoJoin == false)
		let names = session.conversationList.map(\.name)
		#expect(Set(names).count == names.count)
	}

	@Test("A joined channel that already has the new name blocks the rename and says so")
	func renameConflictWithAJoinedChannelIsReported() throws {
		let session = session()
		let first = try joinedChannel("#old", on: session)
		let second = try joinedChannel("#new", on: session)

		try rename(":server RENAME #old #new", on: session)

		#expect(first.name == "#old")
		#expect(second.name == "#new")
		#expect(session.conversationList.count(where: { $0.isChannel }) == 2)
	}

	@Test("Without the capability a RENAME is not evidence of anything")
	func renameIsIgnoredWithoutTheCapability() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.setConnectionTransportForTesting(.connected)
		session.userNickname = "me"
		session.markAsLoggedIn()
		let channel = try joinedChannel("#old", on: session)

		try rename(":server RENAME #old #new", on: session)

		#expect(channel.name == "#old")
	}

	@Test("A replayed RENAME describes a name the channel no longer has")
	func replayedRenameIsIgnored() throws {
		let session = session()
		let channel = try joinedChannel("#old", on: session)

		try rename(":server RENAME #old #new", on: session, replayed: true)

		#expect(channel.name == "#old")
	}

	@Test("A malformed or unrelated RENAME changes nothing", arguments: [
		":server RENAME #old",
		":server RENAME #unknown #new",
		":server RENAME notachannel #new",
		":server RENAME #old notachannel",
		":server RENAME #old #old",
	])
	func malformedRenameIsIgnored(line: String) throws {
		let session = session()
		let channel = try joinedChannel("#old", on: session)

		try rename(line, on: session)

		#expect(channel.name == "#old")
		#expect(session.conversationList.count(where: { $0.isChannel }) == 1)
	}

	@Test("A direct conversation is never renamed by a channel rename")
	func directConversationsAreNotRenamed() throws {
		let session = session()
		let direct = try #require(session.findConversationOrCreate("alice"))

		try rename(":server RENAME alice #new", on: session)

		#expect(direct.name == "alice")
	}

	@Test("RENAME reaches the handler through the inbound dispatcher")
	func dispatcherRoutesRename() throws {
		let session = session()
		let channel = try joinedChannel("#old", on: session)

		let message = try #require(Message(line: ":server RENAME #old #new :reason", on: session))
		session.dispatchIncomingMessage(message)

		#expect(channel.name == "#new")
	}
}
