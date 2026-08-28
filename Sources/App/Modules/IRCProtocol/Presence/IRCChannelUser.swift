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

@objc(IRCChannelUser)
open class ChannelUser: PortablePropertyObject, @unchecked Sendable {
	private let userLock = NSLock()
	private var userStorage: User?

	fileprivate var modesStorage = ""
	private var incomingWeightStorage = 0.0
	private var outgoingWeightStorage = 0.0
	private var lastWeightFade = CFAbsoluteTimeGetCurrent()
	private var creationTimeStorage = Date().timeIntervalSince1970

	@objc public var user: User {
		userLock.withLock { userStorage! }
	}

	private var client: IRCClient? {
		user.client
	}

	@objc open var modes: String {
		modesStorage
	}

	@objc public var mark: String {
		let mode = highestRankedUserMode
		return client?.supportInfo.userPrefix(forModeSymbol: mode) ?? ""
	}

	public var rank: UserRank {
		rank(forModeSymbol: highestRankedUserMode)
	}

	public var ranks: UserRank {
		var result: UserRank = []

		for mode in modesStorage {
			let rank = rank(forModeSymbol: String(mode))
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

	@objc public var totalWeight: Double {
		decayConversation()
		return incomingWeightStorage + outgoingWeightStorage
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

	private var highestRankedUserMode: String {
		modesStorage.first.map(String.init) ?? ""
	}

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable; use init(user:)")
	}

	@objc(initWithUser:)
	public init(user: User) {
		userStorage = user
		super.init()
	}

	public required init?(coder _: NSCoder) {
		nil
	}

	@objc(changeUserToUser:)
	public func changeUser(to user: User) {
		userLock.withLock {
			userStorage = user
		}
	}

	@objc(userModesContainsMode:)
	public func userModesContains(_ mode: String) -> Bool {
		modesStorage.contains(mode)
	}

	private var channelRank: UInt {
		client?.supportInfo.rankForUserPrefix(withMode: highestRankedUserMode) ?? 0
	}

	private func hasRank(of modeSymbol: String, orHigher fallbackModeSymbol: String?) -> Bool {
		guard let supportInfo = client?.supportInfo else {
			return false
		}

		var threshold = supportInfo.rankForUserPrefix(withMode: modeSymbol)

		if threshold == 0, let fallbackModeSymbol {
			threshold = supportInfo.rankForUserPrefix(withMode: fallbackModeSymbol)
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

	private func decayConversation() {
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
		let favorIRCop = TextualPreferences.memberListSortFavorsServerStaff()

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

		guard let supportInfo = client?.supportInfo else {
			return user.nickname.compare(other.user.nickname)
		}

		let localNickname = supportInfo.casefoldString(user.nickname)
		let remoteNickname = supportInfo.casefoldString(other.user.nickname)

		return localNickname.compare(remoteNickname)
	}

	@objc public class var channelRankComparator: Comparator {
		{ first, second in
			guard let first = first as? ChannelUser, let second = second as? ChannelUser else {
				return .orderedSame
			}

			return first.compareRank(to: second)
		}
	}

	override public var description: String {
		"<IRCChannelUser \(mark)\(user.nickname)>"
	}

	override public func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? ChannelUser else {
			return false
		}

		return self === other || user === other.user && modesStorage == other.modesStorage
	}

	@objc(populateDuringCopy:mutableCopy:)
	override public func populateDuringCopy(_ newObject: PortablePropertyObject, mutableCopy _: Bool) {
		populateCopy(newObject)
	}

	@objc(populateDuringUniqueCopy:mutableCopy:)
	override public func populateDuringUniqueCopy(_ newObject: PortablePropertyObject, mutableCopy _: Bool) {
		populateCopy(newObject)
	}

	private func populateCopy(_ newObject: PortablePropertyObject) {
		guard let object = newObject as? ChannelUser else {
			return
		}

		object.userStorage = user
		object.modesStorage = modesStorage
		object.creationTimeStorage = creationTimeStorage
		object.incomingWeightStorage = incomingWeightStorage
		object.outgoingWeightStorage = outgoingWeightStorage
		object.lastWeightFade = lastWeightFade
	}

	override public var mutableClass: PortablePropertyObject {
		unsafeBitCast(ChannelUserMutable.self, to: PortablePropertyObject.self)
	}

	@objc(associateWithChannel:)
	public func associate(with channel: IRCChannel) {
		user.associate(self, with: channel)
	}

	@objc(disassociateWithChannel:)
	public func disassociate(with channel: IRCChannel) {
		user.disassociateUser(with: channel)
	}
}

@objc(IRCChannelUserMutable)
public final class ChannelUserMutable: ChannelUser, @unchecked Sendable {
	override public static var isMutable: Bool {
		true
	}

	override public var immutableClass: PortablePropertyObject {
		unsafeBitCast(ChannelUser.self, to: PortablePropertyObject.self)
	}

	@objc override public var modes: String {
		get { modesStorage }
		set { modesStorage = newValue }
	}
}
