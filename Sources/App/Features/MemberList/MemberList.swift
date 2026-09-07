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
import GlasstualPluginKit
import Observation

public nonisolated struct MemberListSectionIdentifier: Hashable, Sendable { // nonisolated: value
	public let rank: UserRank
	public let ordinal: Int
}

public nonisolated struct MemberListSection: Hashable, Sendable { // nonisolated: value
	public let identifier: MemberListSectionIdentifier
	public let title: String

	public var rank: UserRank {
		identifier.rank
	}
}

public struct MemberListGroup: Identifiable {
	public let section: MemberListSection
	public let members: [ChannelUser]

	public var id: MemberListSectionIdentifier {
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
public final class MemberList: ChannelMemberListPresentation {
	public var isHiddenByUser = false
	public var selectedMemberIDs: Set<User.ID> = []
	public private(set) var groups: [MemberListGroup] = []
	public private(set) var presentationRevision = 0

	@ObservationIgnored private weak var memberList: ChannelMemberList?
	@ObservationIgnored private var members: [ChannelUser] = []
	@ObservationIgnored private var indexesByUserID: [User.ID: Int] = [:]
	private var updateDepth = 0
	private var updateIsPending = false
	private var lastInteractedMemberID: User.ID?

	public init() {}

	public func assign(to channel: IRCChannel?) {
		memberList?.assign(nil)
		memberList = channel?.memberInfo
		if let memberList {
			memberList.assign(self)
		} else {
			replaceContents([])
		}
	}

	public func memberListDidEnd() {
		memberList = nil
		replaceContents([])
	}

	public func replaceContents(_ contents: [ChannelUser]) {
		members = contents
		reindexMembers()
		membersChanged()
	}

	public func insert(_ member: ChannelUser, atArrangedObjectIndex index: Int) {
		guard index >= 0, index <= members.count else { return }
		members.insert(member, at: index)
		reindexMembers()
		membersChanged()
	}

	public func replace(_ member: ChannelUser, atArrangedObjectIndex index: Int) {
		guard members.indices.contains(index) else { return }
		if members[index].id != member.id {
			indexesByUserID.removeValue(forKey: members[index].id)
			indexesByUserID[member.id] = index
		}
		members[index] = member
		membersChanged()
	}

	public func remove(atArrangedObjectIndex index: Int) {
		guard members.indices.contains(index) else { return }
		members.remove(at: index)
		reindexMembers()
		membersChanged()
	}

	private func reindexMembers() {
		indexesByUserID = Dictionary(members.enumerated().map { ($0.element.id, $0.offset) },
		                             uniquingKeysWith: { _, latest in latest })
	}

	public var selectedMembers: [ChannelUser] {
		selectedMemberIDs.compactMap { indexesByUserID[$0] }.sorted().compactMap { index in
			let member = members[index]
			if let memberList {
				return memberList.findMember(withUserID: member.id)
			}
			return member
		}
	}

	public func beginUpdates() {
		updateDepth += 1
	}

	public func endUpdates() {
		guard updateDepth > 0 else { return }
		updateDepth -= 1

		if updateDepth == 0, updateIsPending {
			updateIsPending = false
			rebuildRows()
		}
	}

	public func membersChanged() {
		guard updateDepth == 0 else {
			updateIsPending = true
			return
		}

		rebuildRows()
	}

	private func rebuildRows() {
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
			let rank = Self.sectionRank(for: member)
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
		invalidatePresentation()
	}

	private static func sectionRank(for member: ChannelUser) -> UserRank {
		if member.user.isIRCop, Preferences.Appearance.memberListSortFavorsServerStaff.detachedValue {
			return .irCopByMode
		}

		return member.rank
	}

	public func deselectAll(_: Any?) {
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
		guard let index = indexesByUserID[identifier] else { return }
		let member = members[index]
		notePrimaryInteraction(with: member)
	}

	public var primaryInteractedMember: ChannelUser? {
		guard let lastInteractedMemberID else { return nil }
		if let memberList {
			return memberList.findMember(withUserID: lastInteractedMemberID)
		}
		return indexesByUserID[lastInteractedMemberID].map { members[$0] }
	}

	/** Tells the rows to draw themselves again.

	 The list is a value projection: a row's appearance is a function of the
	 member it holds and of preferences and appearance the row reads directly,
	 so there is nothing to redraw a single row with. One revision is what every
	 caller needs, whichever member prompted it. */
	public func invalidatePresentation() {
		presentationRevision &+= 1
	}

	public func refreshDrawing(forChangesToPreference preferenceKey: String) {
		guard UserListModeBadge.badge(forPreferenceKeyNamed: preferenceKey) != nil else { return }
		invalidatePresentation()
	}

	public func applicationAppearanceChanged() {
		invalidatePresentation()
	}

	public func systemAppearanceChanged() {
		invalidatePresentation()
	}
}
