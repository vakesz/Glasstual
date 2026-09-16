/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
import Observation

nonisolated struct MemberListSectionIdentifier: Hashable, Sendable { // nonisolated: value
	let rank: UserRank
	let ordinal: Int
}

nonisolated struct MemberListSection: Hashable, Sendable { // nonisolated: value
	let identifier: MemberListSectionIdentifier
	let title: String

	var rank: UserRank {
		identifier.rank
	}
}

struct MemberListGroup: Identifiable {
	let section: MemberListSection
	let members: [ChannelUser]

	var id: MemberListSectionIdentifier {
		section.identifier
	}
}

/// Observable state for the SwiftUI member list.
///
/// Rows are derived from the channel's ordered members. Selection is held
/// by stable user identity rather than row number, so joins, parts and rank
/// changes cannot move the selection onto a different person.
@MainActor
@Observable
final class MemberList: ChannelMemberListPresentation {
	var selectedMemberIDs: Set<User.ID> = []
	private(set) var groups: [MemberListGroup] = []
	/** The badge colours and rank preferences every row draws from.

	 Read once per invalidation and handed down. A row used to ask the defaults
	 store three times over — once for its glyph, once for the tooltip and once
	 for the accessibility label — and each ask builds its own handle on the
	 suite, on every row, on each rebuild a busy channel provokes. */
	private(set) var presentationStyle = MemberListPresentationStyle.current()
	/// How many times the list has told its rows to draw themselves again. The
	/// rows do not read it; it is what says that a burst of changes published
	/// once rather than once per change.
	private(set) var presentationRevision = 0
	/** The pinned nickname colours the rows draw their avatars from.

	 One read per invalidation, handed to every avatar in the list. Each avatar
	 used to resolve its own fill straight out of the defaults store, which
	 builds a handle on the suite per row -- and a busy channel rebuilds its
	 rows on every join, part and mode change. */
	private(set) var nicknameColorOverrides = NicknameColors.overridesSnapshot()
	/** Whose profile popover is open, if anyone's.

	 The list owns it rather than the row: a popover is modal to the pointer,
	 so a second one would have to replace the first, and a row that kept its
	 own flag could not know that. */
	private(set) var memberShowingProfile: User.ID?

	@ObservationIgnored private weak var memberList: ChannelMemberList?
	/// The channel's ordering as the protocol layer last published it. The rows
	/// come from ``groups``; this is what the next rebuild reads.
	@ObservationIgnored private var members: [ChannelUser] = []
	private var lastInteractedMemberID: User.ID?

	init() {}

	func assign(to channel: Channel?) {
		memberList?.assign(nil)
		memberList = channel?.memberInfo
		if let memberList {
			memberList.assign(self)
		} else {
			membersDidChange([])
		}
	}

	func membersDidChange(_ members: [ChannelUser]) {
		self.members = members
		rebuildRows()
	}

	/** The members the reader has selected, in the order the list draws them.

	 Each one is read back out of the channel rather than returned from the
	 published ordering: a protocol message still assembling an ordering has
	 already left, renamed or re-ranked people the list is still drawing, and
	 the caller acts on who they are now. */
	var selectedMembers: [ChannelUser] {
		members.compactMap { member in
			guard selectedMemberIDs.contains(member.id) else {
				return nil
			}

			guard let memberList else {
				return member
			}

			return memberList.findMember(withUserID: member.id)
		}
	}

	private func rebuildRows() {
		/* One read for the whole rebuild, and the same one the rows draw from.
		 Asking inside the loop built a handle on the defaults suite for every
		 member, and a busy channel rebuilds on each join, part and mode change. */
		invalidatePresentation()
		let style = presentationStyle

		var ordinalsByRank: [UserRank: Int] = [:]
		var builtGroups: [MemberListGroup] = []
		var admitted: Set<User.ID> = []
		var currentRank: UserRank?
		var currentMembers: [ChannelUser] = []

		func appendCurrentGroup() {
			guard let rank = currentRank else { return }
			let ordinal = ordinalsByRank[rank, default: 0]
			ordinalsByRank[rank] = ordinal + 1
			let identifier = MemberListSectionIdentifier(rank: rank, ordinal: ordinal)
			let section = MemberListSection(
				identifier: identifier,
				title: MemberListStrings.sectionTitle(for: rank)
			)
			builtGroups.append(MemberListGroup(section: section, members: currentMembers))
		}

		for member in members where admitted.insert(member.id).inserted {
			let rank = style.displayRank(isIRCOperator: member.user.isIRCop, channelRank: member.rank)
			if currentRank != rank {
				appendCurrentGroup()
				currentRank = rank
				currentMembers = []
			}
			currentMembers.append(member)
		}
		appendCurrentGroup()

		groups = builtGroups
		selectedMemberIDs.formIntersection(admitted)
		if let lastInteractedMemberID, admitted.contains(lastInteractedMemberID) == false {
			self.lastInteractedMemberID = nil
		}
		dismissProfileIfMemberLeft(admitted)
	}

	func deselectAll(_: Any?) {
		selectedMemberIDs.removeAll()
		lastInteractedMemberID = nil
	}

	func notePrimaryInteraction(with member: ChannelUser) {
		lastInteractedMemberID = member.id
		if selectedMemberIDs.contains(member.id) == false {
			selectedMemberIDs = [member.id]
		}
	}

	func notePrimaryInteraction(withID identifier: User.ID) {
		guard let member = members.first(where: { $0.id == identifier }) else { return }
		notePrimaryInteraction(with: member)
	}

	var primaryInteractedMember: ChannelUser? {
		guard let lastInteractedMemberID else { return nil }
		if let memberList {
			return memberList.findMember(withUserID: lastInteractedMemberID)
		}
		return members.first { $0.id == lastInteractedMemberID }
	}

	// MARK: - Profile popover

	/** Opens `member`'s profile at once. The list owns the one popover, so a
	 click on another row replaces it rather than stacking a second one. */
	func showProfile(for member: User.ID) {
		memberShowingProfile = member
	}

	/// Takes the open profile down: the double click that opens a conversation
	/// must not leave the first click's popover behind.
	func hideProfile() {
		memberShowingProfile = nil
	}

	/// Drops whatever `member`'s row was showing, and leaves another row's
	/// popover alone.
	func endProfileInteraction(with member: User.ID) {
		if memberShowingProfile == member {
			memberShowingProfile = nil
		}
	}

	private func dismissProfileIfMemberLeft(_ admitted: Set<User.ID>) {
		if let memberShowingProfile, admitted.contains(memberShowingProfile) == false {
			self.memberShowingProfile = nil
		}
	}

	/** Tells the rows to draw themselves again.

	 The list is a value projection: a row's appearance is a function of the
	 member it holds and of the style and pinned colours the list hands it, so
	 there is nothing to redraw a single row with. One snapshot is what every
	 caller needs, whichever member prompted it. */
	func invalidatePresentation() {
		nicknameColorOverrides = NicknameColors.overridesSnapshot()
		presentationStyle = .current()
		presentationRevision &+= 1
	}

	func refreshDrawing(forChangesToPreference preferenceKey: String) {
		guard UserListModeBadge.badge(forPreferenceKeyNamed: preferenceKey) != nil else { return }
		invalidatePresentation()
	}

	func applicationAppearanceChanged() {
		invalidatePresentation()
	}

	func systemAppearanceChanged() {
		invalidatePresentation()
	}
}
