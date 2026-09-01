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
 *********************************************************************** */

import CocoaExtensions
import Foundation
import GlasstualPluginKit

/// Which side of a conversation a member took part in.
public nonisolated enum ChannelConversationDirection: Sendable { // nonisolated: value
	/// The local user spoke to them.
	case outgoing
	/// They spoke to the local user.
	case incoming
	/// They took part without addressing anyone in particular.
	case mention
}

/** A member of a channel.

 A value, owned by the channel's member list. Its identity is the person's:
 one member per `User.ID` per channel, which is what a replacement looks itself
 up by.

 `prefixes` is the client's ISUPPORT `PREFIX` table as it stood when the list
 last stamped the member. Ranking and marks read it rather than the live client,
 because a member no longer knows one; `ChannelMemberList.sortMembers()`
 restamps, which is what picks up a `PREFIX` that arrived after the member did. */
public nonisolated struct ChannelUser: Identifiable, Hashable, Sendable { // nonisolated: value
	/// The member is the person: one entry per user in a channel.
	public var id: User.ID {
		user.id
	}

	public internal(set) var user: User
	public internal(set) var modes = ChannelModeSymbolSet()
	var prefixes: IRCUserPrefixTable

	private var incomingWeightStorage = 0.0
	private var outgoingWeightStorage = 0.0
	private var lastWeightFade = CFAbsoluteTimeGetCurrent()
	private var creationTimeStorage = Date().timeIntervalSince1970

	init(user: User, prefixes: IRCUserPrefixTable = IRCUserPrefixTable()) {
		self.user = user
		self.prefixes = prefixes
	}

	/** Two members are the same when they are the same person with the same
	 modes. The conversation weights and the prefix stamp are derived state that
	 changes constantly; comparing them would make every member unequal to the
	 one the list held a moment ago, which is the comparison the member list and
	 its drawing actually ask for. */
	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.id == rhs.id && lhs.modes == rhs.modes
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(id)
		hasher.combine(modes)
	}

	public var mark: String {
		guard let highest = modes.highest else {
			return ""
		}

		return prefixes.userPrefix(forModeSymbol: String(highest.character)) ?? ""
	}

	public var rank: UserRank {
		rank(forModeSymbol: modes.highest.map { String($0.character) })
	}

	public var ranks: UserRank {
		var result: UserRank = []

		for mode in modes {
			let rank = rank(forModeSymbol: String(mode.character))
			if rank != .none {
				result.insert(rank)
			}
		}

		if result.isEmpty {
			result.insert(.none)
		}

		return result
	}

	public var isOp: Bool {
		hasRank(of: "o", orHigher: nil)
	}

	public var isHalfOp: Bool {
		hasRank(of: "h", orHigher: "o")
	}

	/** Pure by design. Decaying from a getter mutated the values a sort was ordering
	 by, which breaks the strict weak ordering `sort` requires; call
	 `decayConversation()` once before sorting instead. */
	public var totalWeight: Double {
		incomingWeightStorage + outgoingWeightStorage
	}

	public var incomingWeight: Double {
		incomingWeightStorage
	}

	public var outgoingWeight: Double {
		outgoingWeightStorage
	}

	public var creationTime: TimeInterval {
		creationTimeStorage
	}

	/// Points the member at `user`, which is the same person with edited values.
	public mutating func changeUser(to user: User) {
		self.user = user
	}

	public func userModesContains(_ mode: ChannelModeSymbol) -> Bool {
		modes.contains(mode)
	}

	private var channelRank: UInt {
		guard let highest = modes.highest else {
			return 0
		}

		return prefixes.rank(forModeSymbol: String(highest.character))
	}

	private func hasRank(of modeSymbol: String, orHigher fallbackModeSymbol: String?) -> Bool {
		var threshold = prefixes.rank(forModeSymbol: modeSymbol)

		if threshold == 0, let fallbackModeSymbol {
			threshold = prefixes.rank(forModeSymbol: fallbackModeSymbol)
		}

		return threshold > 0 && channelRank >= threshold
	}

	private func rank(forModeSymbol modeSymbol: String?) -> UserRank {
		switch modeSymbol {
		case "y", "Y":
			.irCopByMode
		case "q", "O":
			.channelOwner
		case "a":
			.superOperator
		case "o":
			.normalOperator
		case "h":
			.halfOperator
		case "v":
			.voiced
		default:
			.none
		}
	}

	public mutating func outgoingConversation() {
		outgoingWeightStorage += outgoingWeightStorage.rounded() == 0 ? 20 : 5
	}

	public mutating func incomingConversation() {
		incomingWeightStorage += incomingWeightStorage.rounded() == 0 ? 100 : 20
	}

	public mutating func conversation() {
		incomingWeightStorage += incomingWeightStorage.rounded() == 0 ? 4 : 1
	}

	/// Applies time decay to the conversation weights. Call once before ordering by
	/// `totalWeight`, never from inside a comparator.
	public mutating func decayConversation() {
		let now = CFAbsoluteTimeGetCurrent()
		let minutes = (now - lastWeightFade) / 60

		guard minutes > 1 else {
			return
		}

		lastWeightFade = now

		if incomingWeightStorage > 0 {
			incomingWeightStorage /= pow(2, minutes)
		}

		if outgoingWeightStorage > 0 {
			outgoingWeightStorage /= pow(2, minutes)
		}
	}

	public func compare(usingWeights other: ChannelUser) -> ComparisonResult {
		let localWeight = totalWeight
		let remoteWeight = other.totalWeight

		if localWeight > remoteWeight {
			return .orderedAscending
		}

		if localWeight < remoteWeight {
			return .orderedDescending
		}

		return compareRank(to: other)
	}

	func compareRank(to other: ChannelUser) -> ComparisonResult {
		compareRank(
			to: other,
			favoringServerStaff: Preferences.Appearance.memberListSortFavorsServerStaff.detachedValue
		)
	}

	/// Pure comparator. The preference is passed in so that a sort reads it once
	/// rather than once per comparison.
	func compareRank(to other: ChannelUser, favoringServerStaff favorIRCop: Bool) -> ComparisonResult {
		if favorIRCop, user.isIRCop, other.user.isIRCop == false {
			return .orderedAscending
		}

		if favorIRCop, user.isIRCop == false, other.user.isIRCop {
			return .orderedDescending
		}

		if channelRank > other.channelRank {
			return .orderedAscending
		}

		if channelRank < other.channelRank {
			return .orderedDescending
		}

		let localNickname = prefixes.casefold(user.nickname)
		let remoteNickname = prefixes.casefold(other.user.nickname)

		return localNickname.compare(remoteNickname)
	}
}

extension ChannelUser: CustomStringConvertible {
	public var description: String {
		"<ChannelUser \(mark)\(user.nickname)>"
	}
}
