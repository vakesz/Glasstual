/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

/// The member-list operations shared by channels and their backing store.
///
/// Objective-C plug-ins continue to see the historic protocol name and
/// selectors while native code uses this domain name.
@objc(IRCChannelMemberListPrototype)
public protocol ChannelMemberListing: AnyObject {
	@objc(addUser:)
	func addUser(_ user: User)

	@objc(addMember:)
	func addMember(_ member: ChannelUser)

	@objc(removeMember:)
	func removeMember(_ member: ChannelUser)

	@objc(removeMemberWithNickname:)
	func removeMember(withNickname nickname: String)

	@objc(memberExists:)
	func memberExists(_ nickname: String) -> Bool

	@objc(findMember:)
	func findMember(_ nickname: String) -> ChannelUser?

	@objc var numberOfMembers: UInt { get }
	@objc var memberList: [ChannelUser] { get }

	@objc(sortMembers)
	func sortMembers()
}

@objc(IRCChannelMemberListPrivatePrototype)
public protocol ChannelMemberListPrivateProtocol: AnyObject {
	@objc(addMember:checkForDuplicates:)
	func addMember(_ member: ChannelUser, checkForDuplicates: Bool)

	@objc(replaceMember:withMember:)
	func replaceMember(_ oldMember: ChannelUser, with newMember: ChannelUser)

	@objc(replaceMember:withMember:resort:)
	func replaceMember(_ oldMember: ChannelUser, with newMember: ChannelUser, resort: Bool)

	@objc(replaceMember:withMember:resort:replaceInAllChannels:)
	func replaceMember(
		_ oldMember: ChannelUser,
		with newMember: ChannelUser,
		resort: Bool,
		replaceInAllChannels: Bool
	)

	@objc(resortMember:)
	func resortMember(_ member: ChannelUser)

	@objc(clearMembers)
	func clearMembers()

	@objc(pasteboardDataForMembers:)
	func pasteboardData(for members: [ChannelUser]) -> Data

	@objc(readNicknamesFromPasteboardData:withBlock:)
	static func readNicknames(
		from pasteboardData: Data,
		with callback: (IRCChannel, [String]) -> Void
	) -> Bool

	@objc(readMembersFromPasteboardData:withBlock:)
	static func readMembers(
		from pasteboardData: Data,
		with callback: (IRCChannel, [ChannelUser]) -> Void
	) -> Bool
}

@objc(IRCChannelMemberList)
public final class ChannelMemberList: NSObject, ChannelMemberListing, ChannelMemberListPrivateProtocol {
	private weak var clientStorage: IRCClient?
	private weak var channelStorage: IRCChannel?
	private var controller: IRCChannelMemberListController?
	private var memberContainer: [ChannelUser] = []

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

	@objc(initWithChannel:)
	public init(channel: IRCChannel) {
		clientStorage = channel.associatedClient
		channelStorage = channel
		super.init()
	}

	isolated deinit {
		controller?.assign(to: nil)
	}

	@objc(assignController:)
	public func assign(_ controller: IRCChannelMemberListController?) {
		controller?.replaceContents(memberList)
		self.controller = controller
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
		return index
	}

	private func replaceStoredMember(_ oldMember: ChannelUser, with newMember: ChannelUser) -> Int? {
		guard let index = memberContainer.firstIndex(where: { $0 === oldMember }) else {
			return nil
		}

		memberContainer[index] = newMember
		return index
	}

	private func removeStoredMember(_ member: ChannelUser) -> Int? {
		guard let index = memberContainer.firstIndex(where: { $0 === member }) else {
			return nil
		}

		memberContainer.remove(at: index)
		return index
	}

	@objc(addUser:)
	public func addUser(_ user: User) {
		addMember(ChannelUser(user: user))
	}

	@objc(addMember:)
	public func addMember(_ member: ChannelUser) {
		addMember(member, checkForDuplicates: false)
	}

	@objc(addMember:checkForDuplicates:)
	public func addMember(_ member: ChannelUser, checkForDuplicates: Bool) {
		guard let channel else {
			return
		}

		if checkForDuplicates, let oldMember = member.user.userAssociated(with: channel) {
			replaceMember(oldMember, with: member)
			return
		}

		member.associate(with: channel)
		willChangeValue(forKey: "numberOfMembers")
		willChangeValue(forKey: "memberList")
		let sortedIndex = sortedInsert(member)
		didChangeValue(forKey: "numberOfMembers")
		didChangeValue(forKey: "memberList")

		guard channel.isChannel else {
			return
		}

		controller?.insert(member, atArrangedObjectIndex: sortedIndex)
		client?.postEvent(toViewController: "channelMemberAdded", for: channel)
	}

	@objc(removeMemberWithNickname:)
	public func removeMember(withNickname nickname: String) {
		if let member = findMember(nickname) {
			removeMember(member)
		}
	}

	@objc(removeMember:)
	public func removeMember(_ member: ChannelUser) {
		guard let channel else {
			return
		}

		member.disassociate(with: channel)
		let sortedIndex = removeStoredMember(member)

		guard let sortedIndex, channel.isChannel else {
			return
		}

		controller?.remove(atArrangedObjectIndex: sortedIndex)
		client?.postEvent(toViewController: "channelMemberRemoved", for: channel)
	}

	@objc(resortMember:)
	public func resortMember(_ member: ChannelUser) {
		replaceMember(member, with: member, resort: true)
	}

	private func performReplacement(_ oldMember: ChannelUser, with newMember: ChannelUser, resort: Bool) {
		guard let channel else {
			return
		}

		if oldMember !== newMember {
			oldMember.disassociate(with: channel)
			newMember.associate(with: channel)
		}

		var oldIndex: Int?
		let newIndex: Int? = if resort {
			{
				oldIndex = removeStoredMember(oldMember)
				return sortedInsert(newMember)
			}()
		} else {
			replaceStoredMember(oldMember, with: newMember)
		}

		guard let newIndex, channel.isChannel else {
			return
		}

		guard let controller, let output = clientStorage?.output, output.beginMemberListUpdates()
		else {
			return
		}

		if resort {
			if let oldIndex {
				controller.remove(atArrangedObjectIndex: oldIndex)
			}
			controller.insert(newMember, atArrangedObjectIndex: newIndex)
		} else {
			output.refreshMemberListDrawing(forMemberAt: newIndex)
		}

		output.endMemberListUpdates()
	}

	@objc(replaceMember:withMember:)
	public func replaceMember(_ oldMember: ChannelUser, with newMember: ChannelUser) {
		replaceMember(oldMember, with: newMember, resort: true, replaceInAllChannels: false)
	}

	@objc(replaceMember:withMember:resort:)
	public func replaceMember(_ oldMember: ChannelUser, with newMember: ChannelUser, resort: Bool) {
		replaceMember(oldMember, with: newMember, resort: resort, replaceInAllChannels: false)
	}

	@objc(replaceMember:withMember:resort:replaceInAllChannels:)
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
		for (targetChannel, member) in newMember.user.relations where targetChannel !== thisChannel {
			guard let memberList = (targetChannel.memberInfo as AnyObject) as? ChannelMemberList else {
				continue
			}
			memberList.performReplacement(member, with: member, resort: resort)
		}
	}

	public func changeMember(_ nickname: String, mode: ChannelModeSymbol, value: Bool) {
		guard let client, let member = findMember(nickname) else {
			return
		}

		let editedMember = member.duplicate()
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

		var replaceInAllChannels = false
		if value, mode == ChannelModeSymbol("Y"), member.user.isIRCop == false {
			client.modify(member.user) { user in
				user.isIRCop = true
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

	@objc
	public func sortMembers() {
		/* Snapshot the preference so the comparator stays pure for the whole sort. */
		let favorIRCop = preferences.memberListSortFavorsServerStaff

		memberContainer.sort {
			$0.compareRank(to: $1, favoringServerStaff: favorIRCop) == .orderedAscending
		}

		controller?.replaceContents(memberList)
	}

	@objc
	public func clearMembers() {
		let channel = channel

		willChangeValue(forKey: "numberOfMembers")
		willChangeValue(forKey: "memberList")
		if let channel {
			memberContainer.forEach { $0.disassociate(with: channel) }
		}
		memberContainer.removeAll()
		didChangeValue(forKey: "numberOfMembers")
		didChangeValue(forKey: "memberList")

		controller?.replaceContents([])
	}

	@objc public var numberOfMembers: UInt {
		UInt(memberContainer.count)
	}

	@objc public var memberList: [ChannelUser] {
		memberContainer
	}

	@objc(pasteboardDataForMembers:)
	public func pasteboardData(for members: [ChannelUser]) -> Data {
		let payload: [String: Any] = [
			"channelId": channel?.uniqueIdentifier ?? "",
			"nicknames": members.map(\.user.nickname),
		]

		do {
			return try NSKeyedArchiver.archivedData(withRootObject: payload, requiringSecureCoding: true)
		} catch {
			assertionFailure("Failed to archive channel member pasteboard data: \(error)")
			return Data()
		}
	}

	@objc(readNicknamesFromPasteboardData:withBlock:)
	public static func readNicknames(
		from pasteboardData: Data,
		with callback: (IRCChannel, [String]) -> Void
	) -> Bool {
		let allowedClasses: [AnyClass] = [NSDictionary.self, NSString.self, NSArray.self]
		guard let payload = try? NSKeyedUnarchiver.unarchivedObject(
			ofClasses: allowedClasses,
			from: pasteboardData
		) as? [String: Any],
			let channelID = payload["channelId"] as? String,
			let nicknames = payload["nicknames"] as? [String]
		else {
			return false
		}

		let world = ClientEnvironment.shared.world
		let channel = (world?.findItem(withId: channelID) as AnyObject?) as? IRCChannel

		guard let channel else {
			return false
		}

		callback(channel, nicknames)
		return true
	}

	@objc(readMembersFromPasteboardData:withBlock:)
	public static func readMembers(
		from pasteboardData: Data,
		with callback: (IRCChannel, [ChannelUser]) -> Void
	) -> Bool {
		readNicknames(from: pasteboardData) { channel, nicknames in
			let members = nicknames.compactMap { nickname -> ChannelUser? in
				guard let member = channel.findMember(nickname) else {
					return nil
				}
				return (member as AnyObject) as? ChannelUser
			}
			callback(channel, members)
		}
	}

	@objc(memberExists:)
	public func memberExists(_ nickname: String) -> Bool {
		findMember(nickname) != nil
	}

	@objc(findMember:)
	public func findMember(_ nickname: String) -> ChannelUser? {
		guard let client,
		      let channel,
		      let legacyUser = client.findUser(nickname),
		      let user = (legacyUser as AnyObject) as? User,
		      let member = user.userAssociated(with: channel)
		else {
			return nil
		}

		return member
	}
}
