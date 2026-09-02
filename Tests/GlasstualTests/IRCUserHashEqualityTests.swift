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

/// Both types are Swift values with Swift equality: no `NSObject` `isEqual` or
/// `hash` override, and no object identity to fall back on.
@MainActor
struct IRCUserHashEqualityTests {
	@Test("Two users with the same nickname are two people")
	func separatelyCreatedUsersAreDistinct() {
		let first = User(nickname: "Alice")
		let second = User(nickname: "Alice")

		#expect(first != second)
		#expect(Set([first, second]).count == 2)
	}

	@Test("An edited user is not equal to the one it was copied from")
	func editedUsersAreNotEqual() {
		let user = User(nickname: "Alice")
		var edited = user
		edited.nickname = "Bob"

		#expect(edited != user)
		#expect(edited.id == user.id)
	}

	@Test("Members of the same person with the same modes are equal")
	func equalChannelMembersHashEqually() {
		let user = User(nickname: "Alice")
		let first = ChannelUser(user: user)
		let second = ChannelUser(user: user)

		#expect(first == second)
		#expect(Set([first, second]).count == 1)
	}

	@Test("Channel members with different modes are distinct")
	func channelMembersWithDifferentModesAreDistinct() {
		let user = User(nickname: "Alice")
		let plain = ChannelUser(user: user)
		var operatorMember = ChannelUser(user: user)
		operatorMember.modes = "o"

		#expect(plain != operatorMember)
		#expect(Set([plain, operatorMember]).count == 2)
	}
}
