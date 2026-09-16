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

/// Which side of a conversation a member took part in.
nonisolated enum ChannelConversationDirection: Sendable { // nonisolated: value
	/// The local user spoke to them.
	case outgoing
	/// They spoke to the local user.
	case incoming
	/// They took part without addressing anyone in particular.
	case mention
}

/** Membership privileges advertised by IRC channel prefix modes.

 The raw values are persisted in stored member state and read back by the
 member list's sorting, so a bit keeps the position it was given. */
nonisolated struct UserRank: OptionSet, Hashable, Sendable { // nonisolated: value
	let rawValue: UInt

	/// No rank at all. An option set already spells that as the empty set, so
	/// `.none` no longer occupies a bit of its own and never has to be masked
	/// out of a union.
	static let none = UserRank([])
	static let irCopByMode = UserRank(rawValue: 1 << 1)
	static let channelOwner = UserRank(rawValue: 1 << 2)
	static let superOperator = UserRank(rawValue: 1 << 3)
	static let normalOperator = UserRank(rawValue: 1 << 4)
	static let halfOperator = UserRank(rawValue: 1 << 5)
	static let voiced = UserRank(rawValue: 1 << 6)
}

/** A member of a channel.

 A value, owned by the channel's member list. Its identity is the person's:
 one member per `User.ID` per channel, which is what a replacement looks itself
 up by.

 `prefixes` is the client's ISUPPORT `PREFIX` table as it stood when the list
 last stamped the member. Ranking and marks read it rather than the live client,
 because a member no longer knows one; `ChannelMemberList.sortMembers()`
 restamps, which is what picks up a `PREFIX` that arrived after the member did. */
nonisolated struct ChannelUser: Identifiable, Hashable, Sendable { // nonisolated: value
	/// The member is the person: one entry per user in a channel.
	var id: User.ID {
		user.id
	}

	var user: User
	var modes = ChannelModeSymbolSet()
	var prefixes: UserPrefixTable

	private var incomingWeightStorage = 0.0
	private var outgoingWeightStorage = 0.0
	private var lastWeightFade = CFAbsoluteTimeGetCurrent()
	private var creationTimeStorage = Date().timeIntervalSince1970

	init(user: User, prefixes: UserPrefixTable = UserPrefixTable()) {
		self.user = user
		self.prefixes = prefixes
	}

	/** Two members are the same when they are the same person with the same
	 modes. The conversation weights and the prefix stamp are derived state that
	 changes constantly; comparing them would make every member unequal to the
	 one the list held a moment ago, which is the comparison the member list and
	 its drawing actually ask for. */
	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.id == rhs.id && lhs.modes == rhs.modes
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
		hasher.combine(modes)
	}

	var mark: String {
		guard let highest = modes.highest else {
			return ""
		}

		return prefixes.userPrefix(forModeSymbol: String(highest.character)) ?? ""
	}

	var rank: UserRank {
		rank(forModeSymbol: modes.highest.map { String($0.character) })
	}

	var ranks: UserRank {
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

	var isOp: Bool {
		hasRank(of: "o", orHigher: nil)
	}

	var isHalfOp: Bool {
		hasRank(of: "h", orHigher: "o")
	}

	/** Pure by design. Decaying from a getter mutated the values a sort was ordering
	 by, which breaks the strict weak ordering `sort` requires; call
	 `decayConversation()` once before sorting instead. */
	var totalWeight: Double {
		incomingWeightStorage + outgoingWeightStorage
	}

	var incomingWeight: Double {
		incomingWeightStorage
	}

	var outgoingWeight: Double {
		outgoingWeightStorage
	}

	var creationTime: TimeInterval {
		creationTimeStorage
	}

	/// Points the member at `user`, which is the same person with edited values.
	mutating func changeUser(to user: User) {
		self.user = user
	}

	func userModesContains(_ mode: ChannelModeSymbol) -> Bool {
		modes.contains(mode)
	}

	/// Where the member sorts among the channel's ranks: the rank of the highest
	/// prefix mode they hold, under the table they were stamped with. What a
	/// sort orders on, and so what has to change for a re-sort to be worth it.
	var channelRank: UInt {
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

	mutating func outgoingConversation() {
		outgoingWeightStorage += outgoingWeightStorage.rounded() == 0 ? 20 : 5
	}

	mutating func incomingConversation() {
		incomingWeightStorage += incomingWeightStorage.rounded() == 0 ? 100 : 20
	}

	mutating func conversation() {
		incomingWeightStorage += incomingWeightStorage.rounded() == 0 ? 4 : 1
	}

	/// Applies time decay to the conversation weights. Call once before ordering by
	/// `totalWeight`, never from inside a comparator.
	mutating func decayConversation() {
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

	/// Main-actor because it reads the preference itself. The overload that
	/// takes the preference is the one a sort should call.
	@MainActor
	func compare(usingWeights other: ChannelUser) -> ComparisonResult {
		compare(
			usingWeights: other,
			favoringServerStaff: Preferences.Appearance.memberListSortFavorsServerStaff.value
		)
	}

	/// Pure comparator. The preference is passed in so that a sort reads it once
	/// rather than once per comparison.
	func compare(usingWeights other: ChannelUser, favoringServerStaff favorIRCop: Bool) -> ComparisonResult {
		let localWeight = totalWeight
		let remoteWeight = other.totalWeight

		if localWeight > remoteWeight {
			return .orderedAscending
		}

		if localWeight < remoteWeight {
			return .orderedDescending
		}

		return compareRank(to: other, favoringServerStaff: favorIRCop)
	}

	/** Orders `members` by how much has been said to and by each of them.

	 The one place a weight-ordered sort belongs, because a sort has to read the
	 preference once: asking for it inside the comparator made a completion in a
	 two-thousand-member channel read `UserDefaults` some twenty-two thousand
	 times, once per comparison. */
	@MainActor
	static func sortedByConversationWeight(_ members: [ChannelUser]) -> [ChannelUser] {
		let favorIRCop = Preferences.Appearance.memberListSortFavorsServerStaff.value

		return members.sorted { $0.compare(usingWeights: $1, favoringServerStaff: favorIRCop) == .orderedAscending }
	}

	@MainActor
	func compareRank(to other: ChannelUser) -> ComparisonResult {
		compareRank(
			to: other,
			favoringServerStaff: Preferences.Appearance.memberListSortFavorsServerStaff.value
		)
	}

	func compareRank(to other: ChannelUser, favoringServerStaff favorIRCop: Bool) -> ComparisonResult {
		compareRank(to: other, favoringServerStaff: favorIRCop, casefoldingWith: prefixes)
	}

	/** Pure comparator. Both the preference and the table the nicknames fold
	 under are passed in, so that a sort reads the preference once and orders
	 every pair under one casemapping.

	 Folding each side with the receiver's own table looks symmetric and is not:
	 a member stamped before a `CASEMAPPING` change carries the old mapping, and
	 a comparator that answers "a before b" and "b before a" for the same pair
	 is not the strict weak ordering `sort` requires. */
	func compareRank(
		to other: ChannelUser,
		favoringServerStaff favorIRCop: Bool,
		casefoldingWith table: UserPrefixTable
	) -> ComparisonResult {
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

		let localNickname = table.casefold(user.nickname)
		let remoteNickname = table.casefold(other.user.nickname)

		return localNickname.compare(remoteNickname)
	}
}

extension ChannelUser: CustomStringConvertible {
	var description: String {
		"<ChannelUser \(mark)\(user.nickname)>"
	}
}
