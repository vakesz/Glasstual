// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Channel contracts")
struct ChannelContractsTests {
	@Test("Channel type and status raw values are the ones stored configs carry")
	func channelTypeAndStatusRawValuesRemainStable() {
		#expect(ChannelType.channel.rawValue == 0)
		#expect(ChannelType.privateMessage.rawValue == 1)
		#expect(ChannelType.utility.rawValue == 2)
		#expect(ChannelType.directChat.rawValue == 3)

		#expect(ChannelStatus.parted.rawValue == 0)
		#expect(ChannelStatus.joining.rawValue == 1)
		#expect(ChannelStatus.joined.rawValue == 2)
		#expect(ChannelStatus.terminated.rawValue == 3)
	}

	@Test("Ranks combine as a set, and no rank at all is the empty set")
	func userRankSetAlgebraRemainsStable() {
		#expect(UserRank.none.isEmpty)

		let operatorRanks: UserRank = [.channelOwner, .normalOperator, .voiced]

		#expect(operatorRanks.contains(.normalOperator))
		#expect(operatorRanks.contains(.halfOperator) == false)
		#expect(operatorRanks.isDisjoint(with: [.halfOperator, .irCopByMode]))
	}

	@Test("A member's rank comes from its modes, and the higher rank sorts first")
	func rankAdaptersAndComparisonPreserveNativeBehavior() {
		let client = TestClient()
		client.supportInfo.processConfigurationData("PREFIX=(ov)@+")
		let operatorMember = mutableMember(named: "zeta", modes: "o", on: client)
		let voicedMember = mutableMember(named: "alpha", modes: "v", on: client)

		#expect(operatorMember.rank == .normalOperator)
		#expect(operatorMember.ranks == .normalOperator)
		#expect(operatorMember.compareRank(to: voicedMember) == .orderedAscending)
		#expect(voicedMember.compareRank(to: operatorMember) == .orderedDescending)
	}

	@Test("A channel that was never joined has no members")
	func inactiveChannelHasNoMembers() {
		let channel = Channel(config: ChannelConfig(channelName: "#inactive"))

		#expect(channel.memberInfo == nil)
		#expect(channel.memberList.isEmpty)
		#expect(channel.findMember("nobody") == nil)
		#expect(channel.numberOfMembers == 0)
	}

	private func mutableMember(
		named nickname: String,
		modes: ChannelModeSymbolSet,
		on client: Client
	) -> ChannelUser {
		var member = ChannelUser(user: User(nickname: nickname), prefixes: client.currentUserPrefixes)
		member.modes = modes
		return member
	}
}
