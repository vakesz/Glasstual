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

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct IRCUserHashEqualityTests {
	@Test("Equal users hash equally, so they behave in sets and dictionaries")
	func equalUsersHashEqually() {
		let client = GLTTestClient()
		let first = User(nickname: "Alice", on: client)
		let second = User(nickname: "Alice", on: client)

		#expect(first.isEqual(second))
		#expect(first.hash == second.hash)
		#expect(NSSet(array: [first, second]).count == 1)
	}

	@Test("Users that differ do not compare equal")
	func differentUsersAreNotEqual() {
		let client = GLTTestClient()
		let first = User(nickname: "Alice", on: client)
		let second = User(nickname: "Bob", on: client)

		#expect(first.isEqual(second) == false)
		#expect(NSSet(array: [first, second]).count == 2)
	}

	@Test("Equal channel members hash equally")
	func equalChannelMembersHashEqually() {
		let client = GLTTestClient()
		let user = User(nickname: "Alice", on: client)
		let first = ChannelUser(user: user)
		let second = ChannelUser(user: user)

		#expect(first.isEqual(second))
		#expect(first.hash == second.hash)
		#expect(NSSet(array: [first, second]).count == 1)
	}

	@Test("Channel members with different modes are distinct")
	func channelMembersWithDifferentModesAreDistinct() {
		let client = GLTTestClient()
		let user = User(nickname: "Alice", on: client)
		let plain = ChannelUser(user: user)
		let operatorMember = ChannelUser(user: user)
		operatorMember.modes = "o"

		#expect(plain.isEqual(operatorMember) == false)
		#expect(NSSet(array: [plain, operatorMember]).count == 2)
	}
}
