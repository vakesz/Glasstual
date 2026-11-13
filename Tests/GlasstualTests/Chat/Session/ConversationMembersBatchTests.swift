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

	/// Builds a channel holding `names`, then departs `leavers` and re-adds
	/// `returning`, either one call at a time or inside one batch.
	private func membership(
		names: [String], leavers: [String], returning: [String], batched: Bool
	) throws -> (order: [String], lookups: [String: String?]) {
		let session = TestServerSession()
		session.supportInfo.processConfigurationData("PREFIX=(ov)@+")
		let channel = Conversation(config: ConversationConfig(name: "#chat", type: .channel))
		channel.associatedSession = session
		channel.activate()
		let memberList = try #require(channel.memberInfo)
		for name in names {
			memberList.addMember(Member(user: session.findUserOrCreate(name), prefixes: session.currentUserPrefixes))
		}

		if batched {
			memberList.beginInboundPresentationUpdates()
		}
		for name in leavers {
			memberList.removeMember(withNickname: name)
			// A position-dependent read between removals must see current positions.
			if let user = session.findUser(names[0]) {
				_ = memberList.findMember(withUserID: user.id)
			}
		}
		for name in returning {
			memberList.addMember(Member(user: session.findUserOrCreate(name), prefixes: session.currentUserPrefixes))
		}
		if batched {
			memberList.endPresentationUpdates()
		}

		var lookups: [String: String?] = [:]
		for name in names {
			lookups[name] = session.findUser(name).flatMap { memberList.findMember(withUserID: $0.id)?.user.nickname }
		}
		return (memberList.memberList.map(\.user.nickname), lookups)
	}

	@Test("Removals in a batch leave the same list and lookups as one-at-a-time removals")
	func batchedRemovalsMatchSequentialRemovals() throws {
		let names = (0 ..< 40).map { "user\($0)" }
		let leavers = stride(from: 1, to: 40, by: 3).map { "user\($0)" }
		let returning = ["user4", "user13", "newcomer"]

		let sequential = try membership(names: names, leavers: leavers, returning: returning, batched: false)
		let batched = try membership(names: names, leavers: leavers, returning: returning, batched: true)

		#expect(batched.order == sequential.order)
		#expect(batched.lookups == sequential.lookups)
		#expect(batched.order.count == names.count - leavers.count + returning.count)
	}

	@Test("A member removed and re-added in one batch is kept")
	func removedThenReaddedMemberSurvivesCompaction() throws {
		let result = try membership(names: ["alice", "bob", "carol"], leavers: ["bob"], returning: ["bob"], batched: true)
		#expect(result.order == ["alice", "bob", "carol"])
		#expect(result.lookups["bob"] == .some("bob"))
	}
}
