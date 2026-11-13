// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Member ranks")
struct MemberRankTests {
	@Test("Ranks combine as a set, and no rank at all is the empty set")
	func userRankSetAlgebraRemainsStable() {
		#expect(UserRank.none.isEmpty)

		let operatorRanks: UserRank = [.channelOwner, .normalOperator, .voiced]

		#expect(operatorRanks.contains(.normalOperator))
		#expect(operatorRanks.contains(.halfOperator) == false)
		#expect(operatorRanks.isDisjoint(with: [.halfOperator, .irCopByMode]))
	}

	@Test("A member's rank comes from its modes, and the higher rank sorts first")
	func rankIsDerivedFromModesAndOrdersMembers() {
		let session = TestServerSession()
		session.supportInfo.processConfigurationData("PREFIX=(ov)@+")
		let operatorMember = mutableMember(named: "zeta", modes: "o", on: session)
		let voicedMember = mutableMember(named: "alpha", modes: "v", on: session)

		#expect(operatorMember.rank == .normalOperator)
		#expect(operatorMember.ranks == .normalOperator)
		#expect(operatorMember.compareRank(to: voicedMember, favoringServerStaff: false) == .orderedAscending)
		#expect(voicedMember.compareRank(to: operatorMember, favoringServerStaff: false) == .orderedDescending)
	}

	private func mutableMember(
		named nickname: String,
		modes: ChannelModeSymbolSet,
		on session: ServerSession
	) -> Member {
		var member = Member(user: User(nickname: nickname), prefixes: session.currentUserPrefixes)
		member.modes = modes
		return member
	}
}
