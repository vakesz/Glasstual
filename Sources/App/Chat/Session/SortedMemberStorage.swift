// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// How members rank against each other, read once for a whole pass so the
/// comparisons cannot disagree halfway through it.
nonisolated struct MemberOrdering {
	let favorsServerStaff: Bool
	let prefixes: UserPrefixTable
}

/** A conversation's members in rank order, with the position of each person.

 A member is a value, so the list cannot be searched by object identity; a
 member's identity is the person's, and one conversation holds one member per
 person. Every lookup, replacement and removal goes through the index. */
nonisolated struct SortedMemberStorage {
	private(set) var members: [Member] = []
	/// Position in `members` by the member's identity.
	private var indexByUserID: [User.ID: Int] = [:]
	/** Positions in `members` of members removed inside an update batch.

	 Removing at a position shifts every later member, which costs a reindex per
	 removal; k departures in one batch (a netsplit's QUITs) would cost k of them.
	 Inside a batch a removal instead drops the identity from the index and
	 leaves its slot behind, so every other position stays valid. The slots are
	 compacted once by `compactRemoved()`, which every reader of the whole
	 list calls first. */
	private var removedPositions: Set<Int> = []

	/// The member for `id`, or `nil` when that person is not here.
	func member(withUserID id: User.ID) -> Member? {
		indexByUserID[id].map { members[$0] }
	}

	/// Drops the slots of members removed in this batch and renumbers the rest,
	/// once, whatever the number of removals.
	mutating func compactRemoved() {
		guard removedPositions.isEmpty == false else { return }
		let removed = removedPositions
		removedPositions = []
		var position = -1
		members.removeAll { _ in
			position += 1
			return removed.contains(position)
		}
		reindexAll()
	}

	mutating func sortedIndex(for member: Member, ordering: MemberOrdering) -> Int {
		compactRemoved()
		var lowerBound = 0
		var upperBound = members.count

		while lowerBound < upperBound {
			let index = lowerBound + (upperBound - lowerBound) / 2
			let comparison = members[index].compareRank(
				to: member,
				favoringServerStaff: ordering.favorsServerStaff,
				casefoldingWith: ordering.prefixes
			)

			if comparison == .orderedAscending {
				lowerBound = index + 1
			} else {
				upperBound = index
			}
		}

		return lowerBound
	}

	/// Inserts `member` at its rank.
	mutating func insert(_ member: Member, ordering: MemberOrdering) {
		let index = sortedIndex(for: member, ordering: ordering)
		members.insert(member, at: index)
		reindex(from: index)
	}

	/// Appends `member` out of order, for a batch to sort once it ends.
	mutating func append(_ member: Member) {
		indexByUserID[member.id] = members.count
		members.append(member)
	}

	/// `false` when no member here is `oldMember`'s person.
	@discardableResult
	mutating func replace(_ oldMember: Member, with newMember: Member) -> Bool {
		guard let index = indexByUserID[oldMember.id] else {
			return false
		}

		members[index] = newMember
		if oldMember.id != newMember.id {
			indexByUserID.removeValue(forKey: oldMember.id)
			indexByUserID[newMember.id] = index
		}
		return true
	}

	/// `false` when no member here is that person. Inside a batch the slot is
	/// left for `compactRemoved()`.
	@discardableResult
	mutating func remove(_ member: Member, deferringCompaction: Bool) -> Bool {
		guard let index = indexByUserID[member.id] else {
			return false
		}

		indexByUserID.removeValue(forKey: member.id)

		if deferringCompaction {
			removedPositions.insert(index)
			return true
		}

		compactRemoved()
		members.remove(at: index)
		reindex(from: index)
		return true
	}

	/// Points the identity index at the positions from `start` on, which an
	/// insert or a removal there has shifted by one.
	private mutating func reindex(from start: Int) {
		for index in start ..< members.count {
			indexByUserID[members[index].id] = index
		}
	}

	/** Rebuilds the identity index after a sort or a compaction.

	 A repeat is dropped rather than indexed away: a second entry for the same
	 person is a row no PART, QUIT or KICK could ever reach again. */
	private mutating func reindexAll() {
		assert(removedPositions.isEmpty, "Removed members must be compacted before a full reindex")
		var indexes: [User.ID: Int] = [:]
		indexes.reserveCapacity(members.count)
		var uniqueMembers: [Member] = []
		uniqueMembers.reserveCapacity(members.count)

		for member in members {
			guard indexes[member.id] == nil else {
				assertionFailure("Conversation member \(member.user.nickname) is listed twice")
				continue
			}

			indexes[member.id] = uniqueMembers.count
			uniqueMembers.append(member)
		}

		members = uniqueMembers
		indexByUserID = indexes
	}

	mutating func sort(ordering: MemberOrdering) {
		compactRemoved()
		members.sort {
			$0.compareRank(
				to: $1,
				favoringServerStaff: ordering.favorsServerStaff,
				casefoldingWith: ordering.prefixes
			) == .orderedAscending
		}
		reindexAll()
	}

	/// Stamps every member with `prefixes`, which ranking reads from the member.
	mutating func restamp(_ prefixes: UserPrefixTable) {
		for index in members.indices {
			members[index].prefixes = prefixes
		}
	}

	mutating func decayConversations() {
		compactRemoved()
		for index in members.indices {
			members[index].decayConversation()
		}
	}

	mutating func removeAll() {
		members.removeAll()
		indexByUserID.removeAll()
		removedPositions.removeAll()
	}
}
