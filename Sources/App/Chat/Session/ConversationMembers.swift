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
	private var storage = SortedMemberStorage()
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
		storage.compactRemoved()
		presentation?.membersDidChange(storage.members)
		self.presentation = presentation
	}

	/** A protocol handler may coalesce its own edits. The connection also keeps
	 changed lists open for one bounded, synchronous read turn. Directory and
	 member lookups stay current while ordering and presentation are deferred. */
	func beginPresentationUpdates() {
		deferInboundPresentationIfNeeded()
		presentationUpdateDepth += 1
	}

	/// Called once when this list first changes in the connection's read turn.
	func beginInboundPresentationUpdates() {
		presentationUpdateDepth += 1
	}

	func endPresentationUpdates() {
		precondition(presentationUpdateDepth > 0)
		presentationUpdateDepth -= 1
		guard presentationUpdateDepth == 0 else { return }
		storage.compactRemoved()
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
		deferInboundPresentationIfNeeded()
		guard presentationUpdateDepth == 0 else {
			presentationUpdatePending = true
			return
		}
		storage.compactRemoved()
		presentation?.membersDidChange(storage.members)
	}

	private func deferInboundPresentationIfNeeded() {
		guard conversation?.isChannel == true else { return }
		session?.deferMemberPresentation(self)
	}

	/** Read once per pass rather than on every comparison, and fold every
	 nickname under one table so a binary search cannot walk past the slot it
	 is looking for. */
	private var ordering: MemberOrdering {
		MemberOrdering(favorsServerStaff: settings.memberListSortFavorsServerStaff, prefixes: currentPrefixes)
	}

	/// Inserts `member` at its rank, or appends it for the enclosing update batch
	/// to sort.
	private func sortedInsert(_ member: Member) {
		deferInboundPresentationIfNeeded()
		guard presentationUpdateDepth == 0 else {
			storage.append(member)
			orderingPending = true
			return
		}

		storage.insert(member, ordering: ordering)
	}

	/// The member for `id`, or `nil` when that person is not in this conversation.
	func findMember(withUserID id: User.ID) -> Member? {
		storage.member(withUserID: id)
	}

	/** Edits the stored member for `id` in place.

	 A caller that read a member and mutated its copy would throw the change
	 away; this is where an edit to a member lands. */
	func updateMember(withUserID id: User.ID, _ block: (inout Member) -> Void) {
		guard let oldMember = storage.member(withUserID: id) else {
			return
		}

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
		storage.decayConversations()
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

		guard storage.remove(member, deferringCompaction: presentationUpdateDepth > 0) else {
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
			|| oldMember.user.profile != newMember.user.profile
		{
			renderRevision &+= 1
		}

		if oldMember.id != newMember.id {
			session?.disassociate(oldMember.user, from: conversation)
			session?.associate(newMember.user, with: conversation)
		}

		if needsResort {
			deferInboundPresentationIfNeeded()
			if presentationUpdateDepth > 0 {
				/* Moving a member is a removal and an insertion, each of which
				 shifts every index after it. Inside a batch the new value takes
				 the old slot and the batch's one sort puts it in place. */
				guard storage.replace(oldMember, with: newMember) else {
					return
				}
				orderingPending = true
			} else {
				storage.remove(oldMember, deferringCompaction: false)
				sortedInsert(newMember)
			}
		} else if storage.replace(oldMember, with: newMember) == false {
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
		storage.compactRemoved()
		let previousOrder = storage.members.map { ($0.id, $0.mark) }
		/* Snapshot the setting so the comparator stays pure for the whole sort. */
		let ordering = ordering

		/* Restamp first: ranking reads the prefix table the member carries, and
		 a PREFIX that arrived after the member did has to reach it. */
		storage.restamp(ordering.prefixes)

		sortStoredMembers(ordering)
		if zip(previousOrder, storage.members).contains(where: { $0.0 != $1.id || $0.1 != $1.mark }) {
			renderRevision &+= 1
		}
		publishMembers()
	}

	private func sortStoredMembers() {
		sortStoredMembers(ordering)
	}

	private func sortStoredMembers(_ ordering: MemberOrdering) {
		storage.sort(ordering: ordering)
		orderingPending = false
	}

	func clearMembers() {
		storage.compactRemoved()
		guard storage.members.isEmpty == false else { return }
		let conversation = conversation

		if let conversation {
			for member in storage.members {
				session?.disassociate(member.user, from: conversation)
			}
		}
		storage.removeAll()
		renderRevision &+= 1
		publishMembers()
	}

	var numberOfMembers: UInt {
		storage.compactRemoved()
		return UInt(storage.members.count)
	}

	var memberList: [Member] {
		storage.compactRemoved()
		return storage.members
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
