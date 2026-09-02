/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

@MainActor
@Suite("User relations")
struct IRCUserRelationsTests {
	private let client: GLTTestClient
	private let relations: UserRelations

	init() {
		client = GLTTestClient()
		relations = UserRelations()
	}

	@Test("A channel is recorded and dropped again")
	func associatingAndDisassociatingChannel() {
		let channel = makeChannel(named: "#chat")

		relations.associate(with: channel)

		#expect(relations.numberOfRelations == 1)
		#expect(relations.relatedChannels == [channel])
		#expect(relations.isAssociated(with: channel))

		relations.disassociate(from: channel)

		#expect(relations.numberOfRelations == 0)
		#expect(relations.isAssociated(with: channel) == false)
	}

	@Test("A second association for the same channel records it once")
	func repeatedAssociationIsRecordedOnce() {
		let channel = makeChannel(named: "#chat")

		relations.associate(with: channel)
		relations.associate(with: channel)

		#expect(relations.numberOfRelations == 1)
	}

	@Test("A private message is not a channel, so nothing is stored for it")
	func privateMessageChannelsAreNotStored() {
		let privateMessage = makeChannel(named: "alice", type: .privateMessage)

		relations.associate(with: privateMessage)

		#expect(relations.numberOfRelations == 0)
		#expect(relations.isAssociated(with: privateMessage) == false)
	}

	/// Sorting the member list reads the ranks off the mode string, and the
	/// conversation weights are what put recent talkers at the top of tab
	/// completion.
	@Test("A member's modes become ranks, and talking moves its conversation weights")
	func channelUserDerivesRanksAndConversationWeights() {
		let user = User(nickname: "alice")
		var member = ChannelUser(user: user, prefixes: client.currentUserPrefixes)

		#expect(member.ranks == UserRank.none)
		#expect(member.incomingWeight == 0)
		#expect(member.outgoingWeight == 0)

		member.modes = "ov"
		member.incomingConversation()
		member.outgoingConversation()

		#expect(member.id == user.id)
		#expect(member.user == user)
		#expect(member.ranks == [UserRank.normalOperator, UserRank.voiced])
		#expect(member.incomingWeight == 100)
		#expect(member.outgoingWeight == 20)
	}

	@Test("A member list keeps itself sorted and clears the relation on removal")
	func channelMemberListAddsSortsAndRemovesMembers() throws {
		let channel = makeChannel(named: "#chat")
		channel.activate()
		let memberList = try #require(channel.memberInfo)
		let bob = makeMember(named: "bob")
		let alice = makeMember(named: "alice")

		memberList.addMember(bob)
		memberList.addMember(alice)

		#expect(memberList.numberOfMembers == 2)
		#expect(memberList.memberList.map(\.user.nickname) == ["alice", "bob"])

		memberList.removeMember(alice)

		#expect(memberList.numberOfMembers == 1)
		#expect(memberList.memberList == [bob])
		#expect(client.userAssociated(alice.user, with: channel) == nil)
	}

	@Test("Adding a duplicate member replaces the one the list already held")
	func channelMemberListDuplicateCheckReplacesExistingMember() throws {
		let channel = makeChannel(named: "#chat")
		channel.activate()
		let memberList = try #require(channel.memberInfo)
		let user = client.findUserOrCreate("alice")
		var original = ChannelUser(user: user, prefixes: client.currentUserPrefixes)
		var replacement = ChannelUser(user: user, prefixes: client.currentUserPrefixes)
		original.modes = "v"
		replacement.modes = "o"

		memberList.addMember(original)
		memberList.addMember(replacement)

		#expect(memberList.numberOfMembers == 1)
		#expect(memberList.memberList.first?.modes == "o")
		#expect(client.userAssociated(user, with: channel)?.modes == "o")
	}

	@Test("An edit to a member is written back through the list")
	func editingAMemberLandsInTheList() throws {
		let channel = makeChannel(named: "#chat")
		channel.activate()
		let memberList = try #require(channel.memberInfo)
		let member = makeMember(named: "alice")

		memberList.addMember(member)
		memberList.updateMember(withUserID: member.id) { $0.incomingConversation() }

		#expect(memberList.findMember(withUserID: member.id)?.incomingWeight == 100)
		// The caller's copy is untouched, which is what a value means.
		#expect(member.incomingWeight == 0)
	}

	private func makeChannel(named name: String, type: ChannelType = .channel) -> Channel {
		let channel = Channel(config: ChannelConfig(channelName: name, type: type))

		channel.associatedClient = client

		return channel
	}

	private func makeMember(named nickname: String) -> ChannelUser {
		ChannelUser(user: client.findUserOrCreate(nickname), prefixes: client.currentUserPrefixes)
	}
}

/** The direction is documented from the local user's point of view, so a
 channel line naming the local nickname is `.incoming` — they spoke to us. It
 was recorded as `.outgoing`, which swapped the `/weights` columns and left
 `.incoming` unreachable anywhere in the app. */
@MainActor
@Suite("Conversation weights")
struct IRCConversationWeightTests {
	private func channelWithMember(_ nickname: String, on client: GLTTestClient) throws -> Channel {
		let channel = try #require(client.findChannelOrCreate("#chat"))

		channel.activate()
		/* The member has to be a user the client knows: the list looks members
		 up by the identity the client's user table holds. */
		channel.addMember(
			ChannelUser(user: client.findUserOrCreate(nickname), prefixes: client.currentUserPrefixes)
		)

		return channel
	}

	private func testClient() -> GLTTestClient {
		GLTTestClient(configDictionary: ["nickname": "me", "username": "me"])
	}

	@Test("A channel line naming the local user credits the speaker's incoming weight")
	func lineNamingTheLocalUserIsIncoming() throws {
		let client = testClient()
		let channel = try channelWithMember("alice", on: client)
		let text = "hey me"

		try client.receiveText(
			#require(Message(line: ":alice!u@h PRIVMSG #chat :\(text)", on: client)),
			lineType: .privateMessage, text: text
		)

		let member = try #require(channel.findMember("alice"))

		#expect(member.incomingWeight == 100)
		#expect(member.outgoingWeight == 0)
	}

	@Test("A channel line naming nobody is a plain mention")
	func lineNamingNobodyIsAMention() throws {
		let client = testClient()
		let channel = try channelWithMember("alice", on: client)
		let text = "morning everyone"

		try client.receiveText(
			#require(Message(line: ":alice!u@h PRIVMSG #chat :\(text)", on: client)),
			lineType: .privateMessage, text: text
		)

		let member = try #require(channel.findMember("alice"))

		#expect(member.incomingWeight == 4)
		#expect(member.outgoingWeight == 0)
	}
}
