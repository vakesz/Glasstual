/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
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
@testable import Glasstual
import GlasstualPluginKit
import Testing

@MainActor
@Suite("IRC bridge contract")
struct IRCBridgeContractTests {
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
		let client = GLTTestClient()
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
		on client: IRCClient
	) -> ChannelUser {
		var member = ChannelUser(user: User(nickname: nickname), prefixes: client.currentUserPrefixes)
		member.modes = modes
		return member
	}
}
