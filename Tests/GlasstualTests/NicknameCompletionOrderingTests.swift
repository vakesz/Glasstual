/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@Suite("Nickname completion word boundaries")
struct NicknameCompletionDelimiterTests {
	private static let lineFeed: UniChar = 0x0A
	private static let carriageReturn: UniChar = 0x0D
	private static let space: UniChar = 0x20
	private static let comma: UniChar = 0x2C
	private static let colon: UniChar = 0x3A
	private static let letterA: UniChar = 0x61

	/** The regression. Option-Return puts a newline in the field; with only
	 `CharacterSet.whitespaces` the scan for the start of the word ran straight
	 through it into the line above, so a second line beginning with `/` was
	 read as starting at the field's start and completed as a command. */
	@Test("A line break ends the word the caret is in")
	func lineBreaksAreWordDelimiters() {
		#expect(NicknameCompletionDelimiters.isWordDelimiter(Self.lineFeed))
		#expect(NicknameCompletionDelimiters.isWordDelimiter(Self.carriageReturn))
	}

	@Test("Spaces and commas still end a word, letters do not")
	func establishedDelimitersAreUnchanged() {
		#expect(NicknameCompletionDelimiters.isWordDelimiter(Self.space))
		#expect(NicknameCompletionDelimiters.isWordDelimiter(Self.comma))
		#expect(NicknameCompletionDelimiters.isWordDelimiter(Self.letterA) == false)
	}

	@Test("The suffix boundary is the word boundary plus the colon")
	func suffixDelimitersExtendWordDelimiters() {
		#expect(NicknameCompletionDelimiters.isSuffixDelimiter(Self.colon))
		#expect(NicknameCompletionDelimiters.isSuffixDelimiter(Self.lineFeed))
		#expect(NicknameCompletionDelimiters.isSuffixDelimiter(Self.space))
		#expect(NicknameCompletionDelimiters.isSuffixDelimiter(Self.letterA) == false)
	}
}

/** The order the completion list and the member list share:
 `ChannelUser.compare(usingWeights:favoringServerStaff:)`, which is what
 `sortedByConversationWeight(_:)` sorts with. */
@Suite("Conversation weight ordering")
struct ConversationWeightOrderTests {
	private func member(_ nickname: String, conversations: Int = 0, isIRCop: Bool = false) -> ChannelUser {
		var user = User(nickname: nickname)
		user.isIRCop = isIRCop
		var member = ChannelUser(user: user)
		for _ in 0 ..< conversations {
			member.conversation()
		}
		return member
	}

	private func isOrderedBefore(
		_ left: ChannelUser,
		_ right: ChannelUser,
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

	/** The staff preference is a parameter, so a sort reads it once. Passing it
	 explicitly is also what makes the tie-break testable: equal weights, and the
	 answer changes with the preference rather than with the defaults store. */
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
