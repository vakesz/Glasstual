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

@testable import Glasstual
import GlasstualPluginKit
import XCTest

@MainActor
final class IRCBridgeContractMigrationTests: XCTestCase {
	func testChannelTypeAndStatusRawValuesRemainStable() {
		XCTAssertEqual(ChannelType.channel.rawValue, 0)
		XCTAssertEqual(ChannelType.privateMessage.rawValue, 1)
		XCTAssertEqual(ChannelType.utility.rawValue, 2)
		XCTAssertEqual(ChannelType.directChat.rawValue, 3)

		XCTAssertEqual(ChannelStatus.parted.rawValue, 0)
		XCTAssertEqual(ChannelStatus.joining.rawValue, 1)
		XCTAssertEqual(ChannelStatus.joined.rawValue, 2)
		XCTAssertEqual(ChannelStatus.terminated.rawValue, 3)
	}

	func testUserRankBitsAndSetAlgebraRemainStable() {
		XCTAssertEqual(UserRank.none.rawValue, 0)
		XCTAssertEqual(UserRank.irCopByMode.rawValue, 1 << 1)
		XCTAssertEqual(UserRank.channelOwner.rawValue, 1 << 2)
		XCTAssertEqual(UserRank.superOperator.rawValue, 1 << 3)
		XCTAssertEqual(UserRank.normalOperator.rawValue, 1 << 4)
		XCTAssertEqual(UserRank.halfOperator.rawValue, 1 << 5)
		XCTAssertEqual(UserRank.voiced.rawValue, 1 << 6)

		let operatorRanks: UserRank = [.channelOwner, .normalOperator, .voiced]
		XCTAssertEqual(operatorRanks.rawValue, (1 << 2) | (1 << 4) | (1 << 6))
		XCTAssertTrue(operatorRanks.contains(.normalOperator))
		XCTAssertTrue(operatorRanks.isDisjoint(with: [.halfOperator, .irCopByMode]))
	}

	@MainActor
	func testRankAdaptersAndComparisonPreserveNativeBehavior() {
		let client = GLTTestClient()
		client.supportInfo.processConfigurationData("PREFIX=(ov)@+")
		let operatorMember = mutableMember(named: "zeta", modes: "o", on: client)
		let voicedMember = mutableMember(named: "alpha", modes: "v", on: client)

		XCTAssertEqual(operatorMember.rank, .normalOperator)
		XCTAssertEqual(operatorMember.ranks, .normalOperator)
		XCTAssertEqual(operatorMember.compareRank(to: voicedMember), .orderedAscending)
		XCTAssertEqual(voicedMember.compareRank(to: operatorMember), .orderedDescending)
	}

	func testInactiveChannelHasNoMembers() {
		let channel = Channel(config: ChannelConfig(channelName: "#inactive"))

		XCTAssertNil(channel.memberInfo)
		XCTAssertTrue(channel.memberList.isEmpty)
		XCTAssertNil(channel.findMember("nobody"))
		XCTAssertEqual(channel.numberOfMembers, 0)
	}

	private func mutableMember(
		named nickname: String,
		modes: ChannelModeSymbolSet,
		on client: IRCClient
	) -> ChannelUser {
		let member = ChannelUser(user: User(nickname: nickname, on: client))
		member.modes = modes
		return member
	}
}
