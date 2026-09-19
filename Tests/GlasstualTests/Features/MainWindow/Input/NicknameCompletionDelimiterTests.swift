// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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
