/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import GlasstualPluginKit
import Synchronization

@objc(IRCChannelUser)
/* ISOLATION-EXCEPTION: the renderer collects members off the main actor while it
 marks up nicknames. The field that changes under it is behind `userLock`. */
public final nonisolated class ChannelUser: NSObject, @unchecked Sendable {
	private let userLock = NSLock()
	private var userStorage: User

	/// Editable through `duplicate()`; the member list replaces stored members
	/// rather than editing them in place.
	public internal(set) var modes = ChannelModeSymbolSet()
	private var incomingWeightStorage = 0.0
	private var outgoingWeightStorage = 0.0
	private var lastWeightFade = CFAbsoluteTimeGetCurrent()
	private var creationTimeStorage = Date().timeIntervalSince1970

	@objc public var user: User {
		userLock.withLock { userStorage }
	}

	private var client: IRCClient? {
		user.client
	}

	/** Ranking and marks come from the client's published ISUPPORT values rather
	 than its live support table: members are ranked and rendered off the main
	 actor. Absent a client the IRC defaults apply. */
	private var prefixes: IRCUserPrefixTable {
		client?.userPrefixes.withLock { $0 } ?? IRCUserPrefixTable()
	}

	@objc public var mark: String {
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

	/// Objective-C compatibility for the legacy `IRCUserRank` return type.
	@objc(rank)
	public var objectiveCRankRawValue: UInt {
		rank.rawValue
	}

	/// Objective-C compatibility for the legacy `IRCUserRank` bit mask.
	@objc(ranks)
	public var objectiveCRanksRawValue: UInt {
		ranks.rawValue
	}

	@objc public var isOp: Bool {
		hasRank(of: "o", orHigher: nil)
	}

	@objc public var isHalfOp: Bool {
		hasRank(of: "h", orHigher: "o")
	}

	/** Pure by design. Decaying from a getter mutated the values a sort was ordering
	 by, which breaks the strict weak ordering `sort` requires; call
	 `decayConversation()` once before sorting instead. */
	@objc public var totalWeight: Double {
		incomingWeightStorage + outgoingWeightStorage
	}

	@objc public var incomingWeight: Double {
		incomingWeightStorage
	}

	@objc public var outgoingWeight: Double {
		outgoingWeightStorage
	}

	@objc public var creationTime: TimeInterval {
		creationTimeStorage
	}

	public init(user: User) {
		userStorage = user
		super.init()
	}

	private init(copying other: ChannelUser) {
		userStorage = other.user
		modes = other.modes
		creationTimeStorage = other.creationTimeStorage
		incomingWeightStorage = other.incomingWeightStorage
		outgoingWeightStorage = other.outgoingWeightStorage
		lastWeightFade = other.lastWeightFade

		super.init()
	}

	/// An editable copy. Membership changes replace a stored member with a
	/// duplicate rather than editing the one the list already holds.
	public func duplicate() -> ChannelUser {
		ChannelUser(copying: self)
	}

	public func changeUser(to user: User) {
		userLock.withLock {
			userStorage = user
		}
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
		let prefixes = prefixes
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

	@objc
	public func outgoingConversation() {
		outgoingWeightStorage += outgoingWeightStorage.rounded() == 0 ? 20 : 5
	}

	@objc
	public func incomingConversation() {
		incomingWeightStorage += incomingWeightStorage.rounded() == 0 ? 100 : 20
	}

	@objc
	public func conversation() {
		incomingWeightStorage += incomingWeightStorage.rounded() == 0 ? 4 : 1
	}

	/// Applies time decay to the conversation weights. Call once before ordering by
	/// `totalWeight`, never from inside a comparator.
	@objc
	public func decayConversation() {
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

	@objc(compareUsingWeights:)
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
		compareRank(to: other, favoringServerStaff: TextualPreferences.memberListSortFavorsServerStaff())
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

		let prefixes = prefixes
		let localNickname = prefixes.casefold(user.nickname)
		let remoteNickname = prefixes.casefold(other.user.nickname)

		return localNickname.compare(remoteNickname)
	}

	@objc public static var channelRankComparator: Comparator {
		let favorIRCop = TextualPreferences.memberListSortFavorsServerStaff()

		return { first, second in
			guard let first = first as? ChannelUser, let second = second as? ChannelUser else {
				return .orderedSame
			}

			return first.compareRank(to: second, favoringServerStaff: favorIRCop)
		}
	}

	override public var description: String {
		"<IRCChannelUser \(mark)\(user.nickname)>"
	}

	override public func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? ChannelUser else {
			return false
		}

		return self === other || user === other.user && modes == other.modes
	}

	/** `isEqual` compares values, so `hash` has to as well: inheriting the identity
	 hash makes equal-but-distinct members behave incorrectly in sets and dictionaries. */
	override public var hash: Int {
		var hasher = Hasher()
		hasher.combine(ObjectIdentifier(user))
		hasher.combine(modes)
		return hasher.finalize()
	}

	@MainActor
	public func associate(with channel: IRCChannel) {
		user.associate(self, with: channel)
	}

	@MainActor
	public func disassociate(with channel: IRCChannel) {
		user.disassociateUser(with: channel)
	}
}
