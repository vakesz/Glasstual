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

	@Test("A member is associated with a channel and dropped again by channel")
	func associatingAndDisassociatingChannelMember() {
		let channel = makeChannel(named: "#chat")
		let member = makeMember(named: "alice")

		relations.associate(member, with: channel)

		#expect(relations.numberOfRelations == 1)
		#expect(relations.relatedChannels == [channel])
		#expect(relations.relatedUsers == [member])
		#expect(relations.userAssociated(with: channel) === member)

		relations.disassociateUser(with: channel)

		#expect(relations.numberOfRelations == 0)
		#expect(relations.userAssociated(with: channel) == nil)
	}

	@Test("A second association for the same channel replaces the first")
	func replacingRelationForSameChannel() {
		let channel = makeChannel(named: "#chat")
		let first = makeMember(named: "alice")
		let second = makeMember(named: "bob")

		relations.associate(first, with: channel)
		relations.associate(second, with: channel)

		#expect(relations.numberOfRelations == 1)
		#expect(relations.userAssociated(with: channel) === second)
	}

	@Test("Enumeration walks a snapshot and stops when the visitor asks it to")
	func enumerationUsesSnapshotAndHonorsStop() {
		relations.associate(makeMember(named: "alice"), with: makeChannel(named: "#one"))
		relations.associate(makeMember(named: "bob"), with: makeChannel(named: "#two"))

		var visitedCount = 0

		relations.enumerateRelations { _, _, stop in
			visitedCount += 1
			stop.pointee = true
		}

		#expect(visitedCount == 1)
	}

	@Test("A private message is not a channel, so nothing is stored for it")
	func privateMessageChannelsAreNotStored() {
		let privateMessage = makeChannel(named: "alice", type: .privateMessage)
		let member = makeMember(named: "alice")

		relations.associate(member, with: privateMessage)

		#expect(relations.numberOfRelations == 0)
		#expect(relations.userAssociated(with: privateMessage) == nil)
	}

	@Test("A copied member shares its user but carries its own modes and weights")
	func channelUserCopiesPreserveIdentityModesAndConversationWeights() {
		let user = User(nickname: "alice", on: client)
		let member = ChannelUser(user: user)

		member.modes = "ov"
		member.incomingConversation()
		member.outgoingConversation()

		let copy = member.duplicate()

		#expect(copy !== member)
		#expect(copy.user === user)
		#expect(copy.modes == "ov")
		#expect(copy.ranks == [.normalOperator, .voiced])
		#expect(copy.incomingWeight == 100)
		#expect(copy.outgoingWeight == 20)
		#expect(copy.creationTime == member.creationTime)

		copy.modes = "o"

		#expect(member.modes == "ov")
	}

	@Test("A member list keeps itself sorted and clears the relation on removal")
	func channelMemberListAddsSortsAndRemovesMembers() {
		let channel = makeChannel(named: "#chat")
		let memberList = ChannelMemberList(channel: channel)
		let bob = makeMember(named: "bob")
		let alice = makeMember(named: "alice")

		memberList.addMember(bob)
		memberList.addMember(alice)

		#expect(memberList.numberOfMembers == 2)
		#expect(memberList.memberList.map(\.user.nickname) == ["alice", "bob"])

		memberList.removeMember(alice)

		#expect(memberList.numberOfMembers == 1)
		#expect(memberList.memberList == [bob])
		#expect(alice.user.userAssociated(with: channel) == nil)
	}

	@Test("Adding a duplicate member replaces the relation the first one held")
	func channelMemberListDuplicateCheckReplacesExistingRelation() {
		let channel = makeChannel(named: "#chat")
		let memberList = ChannelMemberList(channel: channel)
		let user = User(nickname: "alice", on: client)
		let original = ChannelUser(user: user)
		let replacement = ChannelUser(user: user)

		memberList.addMember(original)
		memberList.addMember(replacement, checkForDuplicates: true)

		#expect(memberList.numberOfMembers == 1)
		#expect(memberList.memberList.first === replacement)
		#expect(user.userAssociated(with: channel) === replacement)
	}

	private func makeChannel(named name: String, type: ChannelType = .channel) -> Channel {
		let channel = Channel(config: ChannelConfig(channelName: name, type: type))

		channel.setValue(client, forKey: "associatedClient")

		return channel
	}

	private func makeMember(named nickname: String) -> ChannelUser {
		ChannelUser(user: User(nickname: nickname, on: client))
	}
}
