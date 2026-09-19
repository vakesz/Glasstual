// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Both types are Swift values with Swift equality: no `NSObject` `isEqual` or
/// `hash` override, and no object identity to fall back on.
@MainActor
struct UserHashEqualityTests {
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
		let first = Member(user: user)
		let second = Member(user: user)

		#expect(first == second)
		#expect(Set([first, second]).count == 1)
	}

	@Test("Channel members with different modes are distinct")
	func channelMembersWithDifferentModesAreDistinct() {
		let user = User(nickname: "Alice")
		let plain = Member(user: user)
		var operatorMember = Member(user: user)
		operatorMember.modes = "o"

		#expect(plain != operatorMember)
		#expect(Set([plain, operatorMember]).count == 2)
	}
}
