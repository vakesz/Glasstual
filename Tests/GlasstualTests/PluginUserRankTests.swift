/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import GlasstualPluginKit
import Testing

/// `UserRank` is an `OptionSet` a plugin reads off a channel member, and
/// `.none` is the empty set rather than a bit of its own. A third-party plugin
/// written against `if ranks.contains(.none)` would otherwise read every member
/// as unranked.
@MainActor
@Suite("Plugin user rank")
struct PluginUserRankTests {
	@Test("No rank is the empty set, not a bit of its own")
	func userRankNoneIsEmpty() {
		#expect(UserRank.none.rawValue == 0)
		#expect(UserRank.none.isEmpty)
		#expect(UserRank.none == UserRank([]))
	}

	@Test(
		"Inserting no rank leaves a set unchanged",
		arguments: [
			UserRank([]),
			UserRank([.voiced]),
			UserRank([.channelOwner, .normalOperator]),
		]
	)
	func insertingNoRankIsANoOperation(_ ranks: UserRank) {
		var result = ranks
		result.insert(.none)

		#expect(result == ranks)
		#expect(result.contains(.none))
	}

	@Test("A ranked user is never reported as unranked")
	func rankedUsersDoNotCarryNone() {
		let ranked: UserRank = [.halfOperator]

		#expect(ranked.rawValue != 0)
		#expect(ranked.subtracting(.none) == ranked)
	}
}
