// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Member list batching")
struct ConversationMembersBatchTests {
	@Test("Rank changes inside a batch settle into one ordering when it ends")
	func rankChangesInsideBatchSortOnce() throws {
		let session = TestServerSession()
		session.supportInfo.processConfigurationData("PREFIX=(ov)@+")
		let channel = Conversation(config: ConversationConfig(name: "#chat", type: .channel))
		channel.associatedSession = session
		channel.activate()
		let memberList = try #require(channel.memberInfo)

		var members: [Member] = []
		for name in ["alice", "bob", "carol", "dave"] {
			let member = Member(user: session.findUserOrCreate(name), prefixes: session.currentUserPrefixes)
			memberList.addMember(member)
			members.append(member)
		}

		memberList.beginInboundPresentationUpdates()
		var carol = members[2]
		carol.modes = "o"
		memberList.replaceMember(members[2], with: carol)
		var dave = members[3]
		dave.modes = "v"
		memberList.replaceMember(members[3], with: dave)
		memberList.endPresentationUpdates()

		#expect(memberList.memberList.map(\.user.nickname) == ["carol", "dave", "alice", "bob"])
		for member in memberList.memberList {
			#expect(memberList.findMember(withUserID: member.id)?.user.nickname == member.user.nickname)
		}
	}

	@Test("A rank change outside a batch still moves the member at once")
	func rankChangeOutsideBatchMovesImmediately() throws {
		let session = TestServerSession()
		session.supportInfo.processConfigurationData("PREFIX=(ov)@+")
		let channel = Conversation(config: ConversationConfig(name: "#chat", type: .channel))
		channel.associatedSession = session
		channel.activate()
		let memberList = try #require(channel.memberInfo)
		let alice = Member(user: session.findUserOrCreate("alice"), prefixes: session.currentUserPrefixes)
		let bob = Member(user: session.findUserOrCreate("bob"), prefixes: session.currentUserPrefixes)
		memberList.addMember(alice)
		memberList.addMember(bob)

		var promoted = bob
		promoted.modes = "o"
		memberList.replaceMember(bob, with: promoted)

		#expect(memberList.memberList.map(\.user.nickname) == ["bob", "alice"])
	}
}
