// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** The order the completion list and the member list share:
 `Member.compare(usingWeights:favoringServerStaff:)`, which is what
 `sortedByConversationWeight(_:)` sorts with. */
@Suite("Conversation weight ordering")
struct ConversationWeightOrderTests {
	private func member(_ nickname: String, conversations: Int = 0, isIRCop: Bool = false) -> Member {
		var user = User(nickname: nickname)
		user.isIRCop = isIRCop
		var member = Member(user: user)
		for _ in 0 ..< conversations {
			member.conversation()
		}
		return member
	}

	private func isOrderedBefore(
		_ left: Member,
		_ right: Member,
		favoringServerStaff favorIRCop: Bool
	) -> Bool {
		left.compare(usingWeights: right, favoringServerStaff: favorIRCop) == .orderedAscending
	}

	@Test("The heavier conversation comes first")
	func weightDecidesFirst() {
		let heavy = member("bob", conversations: 3)
		let light = member("alice")

		#expect(isOrderedBefore(heavy, light, favoringServerStaff: false))
		#expect(isOrderedBefore(light, heavy, favoringServerStaff: false) == false)
	}

	/** The staff setting is a parameter, so a sort reads it once. Passing it
	 explicitly is also what makes the tie-break testable: equal weights, and the
	 answer changes with the setting rather than with the defaults store. */
	@Test("Equal weights fall through to rank, which honours the staff preference")
	func rankBreaksTiesUsingTheSuppliedPreference() {
		let staff = member("zoe", isIRCop: true)
		let regular = member("alice")

		#expect(isOrderedBefore(staff, regular, favoringServerStaff: true))
		#expect(isOrderedBefore(staff, regular, favoringServerStaff: false) == false)
		#expect(isOrderedBefore(regular, staff, favoringServerStaff: false))
	}

	@Test("The order is a strict weak ordering over equal members")
	func equalMembersAreUnordered() {
		let left = member("alice")
		let right = member("alice")

		#expect(isOrderedBefore(left, right, favoringServerStaff: false) == false)
		#expect(isOrderedBefore(right, left, favoringServerStaff: false) == false)
	}
}
