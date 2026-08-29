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

	@Test("A copied member is the same person and carries its own modes and weights")
	func channelUserCopiesPreserveIdentityModesAndConversationWeights() {
		let user = User(nickname: "alice")
		var member = ChannelUser(user: user, prefixes: client.currentUserPrefixes)

		member.modes = "ov"
		member.incomingConversation()
		member.outgoingConversation()

		var copy = member

		#expect(copy.id == member.id)
		#expect(copy.user == user)
		#expect(copy.modes == "ov")
		#expect(copy.ranks == [UserRank.normalOperator, UserRank.voiced])
		#expect(copy.incomingWeight == 100)
		#expect(copy.outgoingWeight == 20)
		#expect(copy.creationTime == member.creationTime)

		copy.modes = "o"

		#expect(member.modes == "ov")
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
		memberList.addMember(replacement, checkForDuplicates: true)

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

		channel.setValue(client, forKey: "associatedClient")

		return channel
	}

	private func makeMember(named nickname: String) -> ChannelUser {
		ChannelUser(user: client.findUserOrCreate(nickname), prefixes: client.currentUserPrefixes)
	}
}
