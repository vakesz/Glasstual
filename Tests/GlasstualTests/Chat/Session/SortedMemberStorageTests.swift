// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("Sorted member storage")
struct SortedMemberStorageTests {
	private let ordering = MemberOrdering(favorsServerStaff: false, prefixes: UserPrefixTable())

	private func member(_ nickname: String, modes: ChannelModeSymbolSet = "") -> Member {
		var member = Member(user: User(nickname: nickname))
		member.modes = modes
		return member
	}

	private func nicknames(_ storage: SortedMemberStorage) -> [String] {
		storage.members.map(\.user.nickname)
	}

	@Test("Inserts keep rank order and the index finds every member")
	func insertKeepsRankOrder() {
		var storage = SortedMemberStorage()
		let members = ["carol", "alice", "dave", "bob"].map { member($0) } + [member("zoe", modes: "o")]

		for member in members {
			storage.insert(member, ordering: ordering)
		}

		#expect(nicknames(storage) == ["zoe", "alice", "bob", "carol", "dave"])
		for member in members {
			#expect(storage.member(withUserID: member.id)?.user.nickname == member.user.nickname)
		}
	}

	@Test("Replacing a member keeps its slot and follows a new identity")
	func replaceKeepsSlot() {
		var storage = SortedMemberStorage()
		let alice = member("alice")
		let bob = member("bob")
		storage.insert(alice, ordering: ordering)
		storage.insert(bob, ordering: ordering)
		let renamed = member("zed")

		let replaced = storage.replace(alice, with: renamed)
		let replacedAgain = storage.replace(alice, with: renamed)

		#expect(replaced)
		#expect(replacedAgain == false)

		#expect(nicknames(storage) == ["zed", "bob"])
		#expect(storage.member(withUserID: alice.id) == nil)
		#expect(storage.member(withUserID: renamed.id)?.user.nickname == "zed")

		storage.sort(ordering: ordering)
		#expect(nicknames(storage) == ["bob", "zed"])
		#expect(storage.member(withUserID: renamed.id)?.user.nickname == "zed")
	}

	@Test("Removals deferred in a batch compact once and keep the index consistent")
	func deferredRemovalsCompact() {
		var storage = SortedMemberStorage()
		let members = ["a", "b", "c", "d", "e"].map { member($0) }
		for member in members {
			storage.insert(member, ordering: ordering)
		}

		let removedB = storage.remove(members[1], deferringCompaction: true)
		let removedD = storage.remove(members[3], deferringCompaction: true)
		let removedDAgain = storage.remove(members[3], deferringCompaction: true)

		#expect(removedB)
		#expect(removedD)
		#expect(removedDAgain == false)
		#expect(storage.member(withUserID: members[4].id)?.user.nickname == "e")

		storage.compactRemoved()

		#expect(nicknames(storage) == ["a", "c", "e"])
		#expect(storage.member(withUserID: members[1].id) == nil)
		let removedC = storage.remove(members[2], deferringCompaction: false)
		#expect(removedC)
		#expect(nicknames(storage) == ["a", "e"])
		#expect(storage.member(withUserID: members[4].id)?.user.nickname == "e")
	}

	@Test("Appended members are put in rank order by the batch's sort")
	func appendedMembersSortOnce() {
		var storage = SortedMemberStorage()
		for nickname in ["c", "a", "b"] {
			storage.append(member(nickname))
		}

		storage.sort(ordering: ordering)

		#expect(nicknames(storage) == ["a", "b", "c"])
		storage.removeAll()
		#expect(storage.members.isEmpty)
	}
}
