// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The view a conversation's member list is drawn into, as the protocol layer sees
 it.

 The list does not create it: the member-list feature owns the controller and
 installs itself here for the one conversation that is on screen. When nothing is
 drawing the list this is `nil`, and every update below is a no-op. */
@MainActor
protocol ConversationMembersPresenting: AnyObject {
	/** The conversation's members, in the order they are drawn in.

	 Always the whole ordering, never an edit at a position. A row's appearance
	 is a function of the member it holds, so there is nothing a single-row
	 edit saves; and handing over a removal followed by an insert — which is
	 what a resort is — takes the person out of the list for an instant and
	 drops a selection that was on them.

	 An empty ordering is also how a list that has gone away reports itself. */
	func membersDidChange(_ members: [Member])
}

final class ConversationMembers {
	/** Both are weak: a member list can outlive its owners during teardown, so
	 neither may be force-unwrapped. */
	private weak var session: ServerSession?
	private weak var conversation: Conversation?
	private var presentation: ConversationMembersPresenting?
	private var memberContainer: [Member] = []
	/// Position in `memberContainer` by the member's identity.
	private var indexByUserID: [User.ID: Int] = [:]
	private var presentationUpdateDepth = 0
	private var presentationUpdatePending = false
	/// Set while an update batch has appended members out of order; the batch
	/// sorts them once when it ends.
	private var orderingPending = false
	/// Changes only when membership, ordering, nicknames or prefix marks change.
	private(set) var renderRevision: UInt64 = 0

	/// The owning session's setting snapshot, or the declared defaults once
	/// that session has gone.
	private var settings: ChatSettings {
		session?.environment.settings ?? ChatSettings()
	}

	init(conversation: Conversation) {
		session = conversation.associatedSession
		self.conversation = conversation
	}

	isolated deinit {
		presentation?.membersDidChange([])
	}

	func assign(_ presentation: ConversationMembersPresenting?) {
		presentation?.membersDidChange(memberContainer)
		self.presentation = presentation
	}

	/** Scope these to one synchronous protocol message, not an entire NAMES/WHO exchange.

	 Directory and member lookups remain current while presentation is deferred,
	 but the ordering does not: a member added or resorted inside the batch is
	 appended, and the batch sorts once as it ends. A NAMES line carries dozens of
	 names, and a sorted insert for each one — a binary search, a shift and an
	 index update — made a large channel's join quadratic. */
	func beginPresentationUpdates() {
		presentationUpdateDepth += 1
	}

	func endPresentationUpdates() {
		precondition(presentationUpdateDepth > 0)
		presentationUpdateDepth -= 1
		guard presentationUpdateDepth == 0 else { return }
		if orderingPending {
			orderingPending = false
			sortStoredMembers()
		}
		if presentationUpdatePending {
			presentationUpdatePending = false
			publishMembers()
		}
	}

	/// Hands the ordering as it stands to whoever is drawing the list, unless a
	/// protocol message is still assembling one.
	private func publishMembers() {
		guard conversation?.isChannel == true else { return }
		guard presentationUpdateDepth == 0 else {
			presentationUpdatePending = true
			return
		}
		presentation?.membersDidChange(memberContainer)
	}

	private func sortedIndex(for member: Member) -> Int {
		var lowerBound = 0
		var upperBound = memberContainer.count
		/* Read once rather than on every comparison, and fold every nickname in
		 the search under one table so the binary search cannot walk past the
		 slot it is looking for. */
		let favorIRCop = settings.memberListSortFavorsServerStaff
		let prefixes = currentPrefixes

		while lowerBound < upperBound {
			let index = lowerBound + (upperBound - lowerBound) / 2
			let comparison = memberContainer[index].compareRank(
				to: member,
				favoringServerStaff: favorIRCop,
				casefoldingWith: prefixes
			)

			if comparison == .orderedAscending {
				lowerBound = index + 1
			} else {
				upperBound = index
			}
		}

		return lowerBound
	}

	/// Inserts `member` at its rank, or appends it for the enclosing update batch
	/// to sort.
	private func sortedInsert(_ member: Member) {
		guard presentationUpdateDepth == 0 else {
			indexByUserID[member.id] = memberContainer.count
			memberContainer.append(member)
			orderingPending = true
			return
		}

		let index = sortedIndex(for: member)
		memberContainer.insert(member, at: index)
		reindexMembers(from: index)
	}

	/// `false` when this conversation holds no member for `oldMember`'s person.
	@discardableResult
	private func replaceStoredMember(_ oldMember: Member, with newMember: Member) -> Bool {
		guard let index = indexByUserID[oldMember.id] else {
			return false
		}

		memberContainer[index] = newMember
		if oldMember.id != newMember.id {
			indexByUserID.removeValue(forKey: oldMember.id)
			indexByUserID[newMember.id] = index
		}
		return true
	}

	/// `false` when this conversation holds no member for that person.
	@discardableResult
	private func removeStoredMember(_ member: Member) -> Bool {
		guard let index = indexByUserID[member.id] else {
			return false
		}

		memberContainer.remove(at: index)
		indexByUserID.removeValue(forKey: member.id)
		reindexMembers(from: index)
		return true
	}

	/// Points the identity index at the positions from `start` on, which an
	/// insert or a removal there has shifted by one.
	private func reindexMembers(from start: Int) {
		for index in start ..< memberContainer.count {
			indexByUserID[memberContainer[index].id] = index
		}
	}

	/** Rebuilds the identity index after a sort.

	 A member is a value now, so the list cannot be searched by object identity;
	 a member's identity is the person's, and one conversation holds one member per
	 person. An insert or a removal patches the positions it shifted instead.

	 A repeat is dropped rather than indexed away: every lookup, replacement and
	 removal goes through this index, so a second entry for the same person is a
	 row no PART, QUIT or KICK could ever reach again. */
	private func reindexMembers() {
		var indexes: [User.ID: Int] = [:]
		indexes.reserveCapacity(memberContainer.count)
		var uniqueMembers: [Member] = []
		uniqueMembers.reserveCapacity(memberContainer.count)

		for member in memberContainer {
			guard indexes[member.id] == nil else {
				assertionFailure("Conversation member \(member.user.nickname) is listed twice")
				continue
			}

			indexes[member.id] = uniqueMembers.count
			uniqueMembers.append(member)
		}

		memberContainer = uniqueMembers
		indexByUserID = indexes
	}

	/// The member for `id`, or `nil` when that person is not in this conversation.
	func findMember(withUserID id: User.ID) -> Member? {
		indexByUserID[id].map { memberContainer[$0] }
	}

	/** Edits the stored member for `id` in place.

	 A caller that read a member and mutated its copy would throw the change
	 away; this is where an edit to a member lands. */
	func updateMember(withUserID id: User.ID, _ block: (inout Member) -> Void) {
		guard let index = indexByUserID[id] else {
			return
		}

		let oldMember = memberContainer[index]
		var editedMember = oldMember
		block(&editedMember)
		performReplacement(oldMember, with: editedMember, resort: true)
	}

	/// Edits the stored member for `nickname` in place, if the conversation has one.
	func updateMember(withNickname nickname: String, _ block: (inout Member) -> Void) {
		guard let user = session?.findUser(nickname) else {
			return
		}

		updateMember(withUserID: user.id, block)
	}

	func decayConversations() {
		// No array snapshot or presentation copy on this completion hot path.
		for index in memberContainer.indices {
			memberContainer[index].decayConversation()
		}
	}

	/// The session's ISUPPORT `PREFIX` table as it stands now. Members are
	/// stamped with it because a member no longer holds a session to ask.
	private var currentPrefixes: UserPrefixTable {
		session?.currentUserPrefixes ?? UserPrefixTable()
	}

	func addUser(_ user: User) {
		addMember(Member(user: user, prefixes: currentPrefixes))
	}

	/** Adds `member`, or replaces the entry this conversation already holds for that
	 person.

	 The duplicate check is not optional. A second entry for one person is only
	 reachable through the identity index, which holds one position per person,
	 so the entry that lost the race becomes a row nothing can find, replace or
	 remove until the conversation is joined again. */
	func addMember(_ member: Member) {
		guard let conversation else {
			return
		}

		/* Asked of this list rather than of the conversation's relations: the list is
		 what holds the members, and the answer has to be the one this call is
		 about to replace. */
		if let oldMember = findMember(withUserID: member.id) {
			replaceMember(oldMember, with: member)
			return
		}

		session?.associate(member.user, with: conversation)
		sortedInsert(member)
		renderRevision &+= 1
		publishMembers()
	}

	func removeMember(withNickname nickname: String) {
		if let member = findMember(nickname) {
			removeMember(member)
		}
	}

	func removeMember(_ member: Member) {
		guard let conversation else {
			return
		}

		session?.disassociate(member.user, from: conversation)

		guard removeStoredMember(member) else {
			return
		}

		renderRevision &+= 1
		publishMembers()
	}

	func resortMember(_ member: Member) {
		replaceMember(member, with: member, resort: true, replaceInAllChannels: false)
	}

	private func performReplacement(_ oldMember: Member, with newMember: Member, resort: Bool) {
		guard let conversation, let storedMember = findMember(withUserID: oldMember.id) else {
			return
		}
		let oldMember = storedMember
		let visibleChange = oldMember.user != newMember.user || oldMember.modes != newMember.modes ||
			oldMember.mark != newMember.mark
		let needsResort = resort && visibleChange && oldMember.compareRank(
			to: newMember,
			favoringServerStaff: settings.memberListSortFavorsServerStaff,
			casefoldingWith: currentPrefixes
		) != .orderedSame
		if needsResort || oldMember.id != newMember.id ||
			oldMember.user.nickname != newMember.user.nickname || oldMember.mark != newMember.mark
		{
			renderRevision &+= 1
		}

		if oldMember.id != newMember.id {
			session?.disassociate(oldMember.user, from: conversation)
			session?.associate(newMember.user, with: conversation)
		}

		if needsResort {
			removeStoredMember(oldMember)
			sortedInsert(newMember)
		} else if replaceStoredMember(oldMember, with: newMember) == false {
			return
		}

		guard visibleChange || needsResort else {
			return
		}

		publishMembers()
	}

	func replaceMember(_ oldMember: Member, with newMember: Member) {
		replaceMember(oldMember, with: newMember, resort: true, replaceInAllChannels: false)
	}

	func replaceMember(
		_ oldMember: Member,
		with newMember: Member,
		resort: Bool,
		replaceInAllChannels: Bool
	) {
		performReplacement(oldMember, with: newMember, resort: resort)

		guard replaceInAllChannels else {
			return
		}

		let thisConversation = conversation
		for (targetChannel, member) in session?.relations(of: newMember.user) ?? []
			where targetChannel !== thisConversation
		{
			targetChannel.memberInfo?.performReplacement(member, with: member, resort: resort)
		}
	}

	func changeMember(_ nickname: String, mode: ChannelModeSymbol, value: Bool) {
		guard let session, let member = findMember(nickname) else {
			return
		}

		var editedMember = member
		var modes = editedMember.modes

		if value {
			guard modes.contains(mode) == false else {
				return
			}

			let supportInfo = session.supportInfo
			modes.insert(mode) { supportInfo.rankForUserPrefix(withMode: String($0.character)) }
		} else {
			guard modes.isEmpty == false else {
				return
			}

			modes.remove(mode)
		}

		editedMember.modes = modes
		editedMember.prefixes = currentPrefixes

		var replaceInAllChannels = false
		if value, mode == ChannelModeSymbol("Y"), member.user.isIRCop == false {
			session.modify(member.user) { user in
				user.isIRCop = true
			}
			/* `modify` relinked the member lists, so take the member the list
			 holds now rather than the one read before the edit. */
			if let relinked = findMember(withUserID: member.id) {
				editedMember.changeUser(to: relinked.user)
			}
			replaceInAllChannels = settings.memberListSortFavorsServerStaff
		}

		replaceMember(
			member,
			with: editedMember,
			resort: true,
			replaceInAllChannels: replaceInAllChannels
		)
	}

	func sortMembers() {
		let previousOrder = memberContainer.map { ($0.id, $0.mark) }
		/* Snapshot the setting so the comparator stays pure for the whole sort. */
		let favorIRCop = settings.memberListSortFavorsServerStaff

		/* Restamp first: ranking reads the prefix table the member carries, and
		 a PREFIX that arrived after the member did has to reach it. */
		let prefixes = currentPrefixes
		for index in memberContainer.indices {
			memberContainer[index].prefixes = prefixes
		}

		sortStoredMembers(favoringServerStaff: favorIRCop, casefoldingWith: prefixes)
		if zip(previousOrder, memberContainer).contains(where: { $0.0 != $1.id || $0.1 != $1.mark }) {
			renderRevision &+= 1
		}
		publishMembers()
	}

	private func sortStoredMembers() {
		sortStoredMembers(
			favoringServerStaff: settings.memberListSortFavorsServerStaff,
			casefoldingWith: currentPrefixes
		)
	}

	private func sortStoredMembers(favoringServerStaff favorIRCop: Bool, casefoldingWith prefixes: UserPrefixTable) {
		memberContainer.sort {
			$0.compareRank(
				to: $1,
				favoringServerStaff: favorIRCop,
				casefoldingWith: prefixes
			) == .orderedAscending
		}
		reindexMembers()
	}

	func clearMembers() {
		guard memberContainer.isEmpty == false else { return }
		let conversation = conversation

		if let conversation {
			for member in memberContainer {
				session?.disassociate(member.user, from: conversation)
			}
		}
		memberContainer.removeAll()
		indexByUserID.removeAll()
		renderRevision &+= 1
		publishMembers()
	}

	var numberOfMembers: UInt {
		UInt(memberContainer.count)
	}

	var memberList: [Member] {
		memberContainer
	}

	func memberExists(_ nickname: String) -> Bool {
		findMember(nickname) != nil
	}

	func findMember(_ nickname: String) -> Member? {
		guard let user = session?.findUser(nickname) else {
			return nil
		}

		return findMember(withUserID: user.id)
	}
}
