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
 *  * Neither the name of Textual and/or Codeux Software, nor the names of
 *    its contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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

import CocoaExtensions
import Foundation

/** The view a channel's member list is drawn into, as the protocol layer sees
 it.

 The list does not create it: the member-list feature owns the controller and
 installs itself here for the one channel that is on screen. When nothing is
 drawing the list this is `nil`, and every update below is a no-op. */
@MainActor
public protocol ChannelMemberListPresentation: AnyObject {
	/// Hands over a whole new ordering, rather than a removal and an insert.
	func replaceContents(_ contents: [ChannelUser])

	func insert(_ member: ChannelUser, atArrangedObjectIndex index: Int)

	func replace(_ member: ChannelUser, atArrangedObjectIndex index: Int)

	func remove(atArrangedObjectIndex index: Int)

	/// The list it was drawing is going away, so it has nothing left to draw.
	func memberListDidEnd()
}

public final class ChannelMemberList: NSObject {
	private weak var clientStorage: IRCClient?
	private weak var channelStorage: IRCChannel?
	private var presentation: ChannelMemberListPresentation?
	private var memberContainer: [ChannelUser] = []
	/// Position in `memberContainer` by the member's identity.
	private var indexByUserID: [User.ID: Int] = [:]

	/** Both are weak: a member list can outlive its owners during teardown, and
	 force-unwrapping them turned that into a crash. */
	private var client: IRCClient? {
		clientStorage
	}

	private var channel: IRCChannel? {
		channelStorage
	}

	/// The owning client's preference snapshot, or the declared defaults once
	/// that client has gone.
	private var preferences: ClientPreferences {
		clientStorage?.environment.preferences ?? ClientPreferences()
	}

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable; use init(channel:)")
	}

	public init(channel: IRCChannel) {
		clientStorage = channel.associatedClient
		channelStorage = channel
		super.init()
	}

	isolated deinit {
		presentation?.memberListDidEnd()
	}

	public func assign(_ presentation: ChannelMemberListPresentation?) {
		presentation?.replaceContents(memberList)
		self.presentation = presentation
	}

	private func sortedIndex(for member: ChannelUser) -> Int {
		var lowerBound = 0
		var upperBound = memberContainer.count
		/* Read once rather than on every comparison. */
		let favorIRCop = preferences.memberListSortFavorsServerStaff

		while lowerBound < upperBound {
			let index = lowerBound + (upperBound - lowerBound) / 2
			let comparison = memberContainer[index].compareRank(to: member, favoringServerStaff: favorIRCop)

			if comparison == .orderedAscending {
				lowerBound = index + 1
			} else {
				upperBound = index
			}
		}

		return lowerBound
	}

	private func sortedInsert(_ member: ChannelUser) -> Int {
		let index = sortedIndex(for: member)
		memberContainer.insert(member, at: index)
		reindexMembers()
		return index
	}

	private func replaceStoredMember(_ oldMember: ChannelUser, with newMember: ChannelUser) -> Int? {
		guard let index = indexByUserID[oldMember.id] else {
			return nil
		}

		memberContainer[index] = newMember
		reindexMembers()
		return index
	}

	private func removeStoredMember(_ member: ChannelUser) -> Int? {
		guard let index = indexByUserID[member.id] else {
			return nil
		}

		memberContainer.remove(at: index)
		reindexMembers()
		return index
	}

	/** Rebuilds the identity index.

	 A member is a value now, so the list cannot be searched by object identity;
	 a member's identity is the person's, and one channel holds one member per
	 person. The index is rebuilt rather than patched because an insert or a
	 removal shifts every position after it anyway.

	 A repeat is dropped rather than indexed away: every lookup, replacement and
	 removal goes through this index, so a second entry for the same person is a
	 row no PART, QUIT or KICK could ever reach again. */
	private func reindexMembers() {
		var indexes: [User.ID: Int] = [:]
		indexes.reserveCapacity(memberContainer.count)
		var uniqueMembers: [ChannelUser] = []
		uniqueMembers.reserveCapacity(memberContainer.count)

		for member in memberContainer {
			guard indexes[member.id] == nil else {
				assertionFailure("Channel member \(member.user.nickname) is listed twice")
				continue
			}

			indexes[member.id] = uniqueMembers.count
			uniqueMembers.append(member)
		}

		memberContainer = uniqueMembers
		indexByUserID = indexes
	}

	/// The member for `id`, or `nil` when that person is not in this channel.
	func findMember(withUserID id: User.ID) -> ChannelUser? {
		indexByUserID[id].map { memberContainer[$0] }
	}

	/** Edits the stored member for `id` in place.

	 A caller that read a member and mutated its copy would throw the change
	 away; this is where an edit to a member lands. */
	func updateMember(withUserID id: User.ID, _ block: (inout ChannelUser) -> Void) {
		guard let index = indexByUserID[id] else {
			return
		}

		block(&memberContainer[index])
		presentation?.replace(memberContainer[index], atArrangedObjectIndex: index)
	}

	/// Edits the stored member for `nickname` in place, if the channel has one.
	func updateMember(withNickname nickname: String, _ block: (inout ChannelUser) -> Void) {
		guard let user = client?.findUser(nickname) else {
			return
		}

		updateMember(withUserID: user.id, block)
	}

	/// The client's ISUPPORT `PREFIX` table as it stands now. Members are
	/// stamped with it because a member no longer holds a client to ask.
	private var currentPrefixes: IRCUserPrefixTable {
		clientStorage?.currentUserPrefixes ?? IRCUserPrefixTable()
	}

	public func addUser(_ user: User) {
		addMember(ChannelUser(user: user, prefixes: currentPrefixes))
	}

	/** Adds `member`, or replaces the entry this channel already holds for that
	 person.

	 The duplicate check is not optional. A second entry for one person is only
	 reachable through the identity index, which holds one position per person,
	 so the entry that lost the race becomes a row nothing can find, replace or
	 remove until the channel is joined again. */
	public func addMember(_ member: ChannelUser) {
		guard let channel else {
			return
		}

		/* Asked of this list rather than of the channel's relations: the list is
		 what holds the members, and the answer has to be the one this call is
		 about to replace. */
		if let oldMember = findMember(withUserID: member.id) {
			replaceMember(oldMember, with: member)
			return
		}

		client?.associate(member.user, with: channel)
		let sortedIndex = sortedInsert(member)

		guard channel.isChannel else {
			return
		}

		presentation?.insert(member, atArrangedObjectIndex: sortedIndex)
	}

	public func removeMember(withNickname nickname: String) {
		if let member = findMember(nickname) {
			removeMember(member)
		}
	}

	public func removeMember(_ member: ChannelUser) {
		guard let channel else {
			return
		}

		client?.disassociate(member.user, from: channel)
		let sortedIndex = removeStoredMember(member)

		guard let sortedIndex, channel.isChannel else {
			return
		}

		presentation?.remove(atArrangedObjectIndex: sortedIndex)
	}

	public func resortMember(_ member: ChannelUser) {
		replaceMember(member, with: member, resort: true)
	}

	private func performReplacement(_ oldMember: ChannelUser, with newMember: ChannelUser, resort: Bool) {
		guard let channel else {
			return
		}

		if oldMember.id != newMember.id {
			client?.disassociate(oldMember.user, from: channel)
			client?.associate(newMember.user, with: channel)
		}

		let newIndex: Int? = if resort {
			{
				/* The old position is not needed any more: a resort is handed to
				 the table as one new ordering. */
				_ = removeStoredMember(oldMember)
				return sortedInsert(newMember)
			}()
		} else {
			replaceStoredMember(oldMember, with: newMember)
		}

		/* A presentation is only attached to the channel whose member list is on
		 screen, so this is also the test for "is anyone drawing this?". */
		guard let newIndex, let presentation, channel.isChannel else {
			return
		}

		if resort {
			/* Handed over as one ordering rather than a removal followed by an
			 insert: taking the person out of the list, even for an instant, is
			 what used to drop a selection that was on them. */
			presentation.replaceContents(memberList)
		} else {
			presentation.replace(newMember, atArrangedObjectIndex: newIndex)
		}
	}

	public func replaceMember(_ oldMember: ChannelUser, with newMember: ChannelUser) {
		replaceMember(oldMember, with: newMember, resort: true, replaceInAllChannels: false)
	}

	public func replaceMember(_ oldMember: ChannelUser, with newMember: ChannelUser, resort: Bool) {
		replaceMember(oldMember, with: newMember, resort: resort, replaceInAllChannels: false)
	}

	public func replaceMember(
		_ oldMember: ChannelUser,
		with newMember: ChannelUser,
		resort: Bool,
		replaceInAllChannels: Bool
	) {
		performReplacement(oldMember, with: newMember, resort: resort)

		guard replaceInAllChannels else {
			return
		}

		let thisChannel = channel
		for (targetChannel, member) in client?.relations(of: newMember.user) ?? []
			where targetChannel !== thisChannel
		{
			targetChannel.memberInfo?.performReplacement(member, with: member, resort: resort)
		}
	}

	public func changeMember(_ nickname: String, mode: ChannelModeSymbol, value: Bool) {
		guard let client, let member = findMember(nickname) else {
			return
		}

		var editedMember = member
		var modes = editedMember.modes

		if value {
			guard modes.contains(mode) == false else {
				return
			}

			let supportInfo = client.supportInfo
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
			client.modify(member.user) { user in
				user.isIRCop = true
			}
			/* `modify` relinked the member lists, so take the member the list
			 holds now rather than the one read before the edit. */
			if let relinked = findMember(withUserID: member.id) {
				editedMember.changeUser(to: relinked.user)
			}
			replaceInAllChannels = preferences.memberListSortFavorsServerStaff
		}

		replaceMember(
			member,
			with: editedMember,
			resort: true,
			replaceInAllChannels: replaceInAllChannels
		)
	}

	public func sortMembers() {
		/* Snapshot the preference so the comparator stays pure for the whole sort. */
		let favorIRCop = preferences.memberListSortFavorsServerStaff

		/* Restamp first: ranking reads the prefix table the member carries, and
		 a PREFIX that arrived after the member did has to reach it. */
		let prefixes = currentPrefixes
		for index in memberContainer.indices {
			memberContainer[index].prefixes = prefixes
		}

		memberContainer.sort {
			$0.compareRank(to: $1, favoringServerStaff: favorIRCop) == .orderedAscending
		}
		reindexMembers()

		presentation?.replaceContents(memberList)
	}

	public func clearMembers() {
		let channel = channel

		if let channel {
			for member in memberContainer {
				client?.disassociate(member.user, from: channel)
			}
		}
		memberContainer.removeAll()
		indexByUserID.removeAll()

		presentation?.replaceContents([])
	}

	public var numberOfMembers: UInt {
		UInt(memberContainer.count)
	}

	public var memberList: [ChannelUser] {
		memberContainer
	}

	public func memberExists(_ nickname: String) -> Bool {
		findMember(nickname) != nil
	}

	public func findMember(_ nickname: String) -> ChannelUser? {
		guard let user = client?.findUser(nickname) else {
			return nil
		}

		return findMember(withUserID: user.id)
	}
}
