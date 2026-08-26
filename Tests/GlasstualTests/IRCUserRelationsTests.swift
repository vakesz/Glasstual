/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import XCTest

final class IRCUserRelationsTests: XCTestCase {
	private var client: GLTTestClient!
	private var relations: IRCUserRelations!

	override func setUp() {
		super.setUp()

		client = GLTTestClient()
		relations = IRCUserRelations()
	}

	override func tearDown() {
		relations = nil
		client = nil

		super.tearDown()
	}

	func testAssociatingAndDisassociatingChannelMember() {
		let channel = makeChannel(named: "#chat")
		let member = makeMember(named: "alice")

		relations.associateUser(member, with: channel)

		XCTAssertEqual(relations.numberOfRelations, 1)
		XCTAssertEqual(relations.relatedChannels, [channel])
		XCTAssertEqual(relations.relatedUsers, [member])
		XCTAssertTrue(relations.userAssociated(with: channel) === member)

		relations.disassociateUser(with: channel)

		XCTAssertEqual(relations.numberOfRelations, 0)
		XCTAssertNil(relations.userAssociated(with: channel))
	}

	func testReplacingRelationForSameChannel() {
		let channel = makeChannel(named: "#chat")
		let first = makeMember(named: "alice")
		let second = makeMember(named: "bob")

		relations.associateUser(first, with: channel)
		relations.associateUser(second, with: channel)

		XCTAssertEqual(relations.numberOfRelations, 1)
		XCTAssertTrue(relations.userAssociated(with: channel) === second)
	}

	func testEnumerationUsesSnapshotAndHonorsStop() {
		relations.associateUser(makeMember(named: "alice"), with: makeChannel(named: "#one"))
		relations.associateUser(makeMember(named: "bob"), with: makeChannel(named: "#two"))

		var visitedCount = 0

		relations.enumerateRelations { _, _, stop in
			visitedCount += 1
			stop.pointee = true
		}

		XCTAssertEqual(visitedCount, 1)
	}

	func testPrivateMessageChannelsAreNotStored() {
		let privateMessage = makeChannel(named: "alice", type: .privateMessage)
		let member = makeMember(named: "alice")

		relations.associateUser(member, with: privateMessage)

		XCTAssertEqual(relations.numberOfRelations, 0)
		XCTAssertNil(relations.userAssociated(with: privateMessage))
	}

	func testChannelUserCopiesPreserveIdentityModesAndConversationWeights() throws {
		let user = IRCUser(nickname: "alice", on: client)
		let member = IRCChannelUserMutable(user: user)

		member.modes = "ov"
		member.perform(NSSelectorFromString("incomingConversation"))
		member.perform(NSSelectorFromString("outgoingConversation"))

		let copy = try XCTUnwrap(member.copy() as? IRCChannelUser)
		let uniqueMutableCopy = try XCTUnwrap(member.uniqueCopyMutable() as? IRCChannelUserMutable)

		XCTAssertTrue(copy.user === user)
		XCTAssertEqual(copy.modes, "ov")
		XCTAssertEqual(copy.ranks, [.normalOperator, .voiced])
		XCTAssertEqual(copy.incomingWeight, 100)
		XCTAssertEqual(copy.outgoingWeight, 20)
		XCTAssertEqual(copy.creationTime, member.creationTime)
		XCTAssertTrue(uniqueMutableCopy.user === user)
		XCTAssertEqual(uniqueMutableCopy.modes, "ov")
		XCTAssertEqual(uniqueMutableCopy.incomingWeight, 100)
		XCTAssertEqual(uniqueMutableCopy.outgoingWeight, 20)
	}

	func testChannelMemberListAddsSortsAndRemovesMembers() {
		let channel = makeChannel(named: "#chat")
		let memberList = IRCChannelMemberList(channel: channel)
		let bob = makeMember(named: "bob")
		let alice = makeMember(named: "alice")

		memberList.addMember(bob)
		memberList.addMember(alice)

		XCTAssertEqual(memberList.numberOfMembers, 2)
		XCTAssertEqual(memberList.memberList?.map(\.user.nickname), ["alice", "bob"])

		memberList.removeMember(alice)

		XCTAssertEqual(memberList.numberOfMembers, 1)
		XCTAssertEqual(memberList.memberList, [bob])
		XCTAssertNil(alice.user.userAssociated(with: channel))
	}

	func testChannelMemberListDuplicateCheckReplacesExistingRelation() {
		let channel = makeChannel(named: "#chat")
		let memberList = IRCChannelMemberList(channel: channel)
		let user = IRCUser(nickname: "alice", on: client)
		let original = IRCChannelUser(user: user)
		let replacement = IRCChannelUser(user: user)

		memberList.addMember(original)
		memberList.addMember(replacement, checkForDuplicates: true)

		XCTAssertEqual(memberList.numberOfMembers, 1)
		XCTAssertTrue(memberList.memberList?.first === replacement)
		XCTAssertTrue(user.userAssociated(with: channel) === replacement)
	}

	private func makeChannel(named name: String, type: IRCChannelType = .channel) -> IRCChannel {
		let channel = IRCChannel(configDictionary: [
			"channelName": name,
			"channelType": type.rawValue,
		])

		channel.setValue(client, forKey: "associatedClient")

		return channel
	}

	private func makeMember(named nickname: String) -> IRCChannelUser {
		IRCChannelUser(user: IRCUser(nickname: nickname, on: client))
	}
}
