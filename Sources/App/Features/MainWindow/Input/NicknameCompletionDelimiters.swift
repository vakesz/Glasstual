// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** What ends the word the caret sits in.

 A line break is one. Option-Return puts a newline in the field, and with only
 `whitespaces` the scan ran straight past it into the line above: a second line
 beginning with `/` was read as starting at the field's start and completed as
 a command, and a nickname on the previous line was offered as the word being
 typed. */
nonisolated enum NicknameCompletionDelimiters {
	/// U+002C COMMA, which separates nicknames the user is addressing.
	private static let comma: UniChar = 0x2C
	/// U+003A COLON, the customary suffix after an addressed nickname.
	private static let colon: UniChar = 0x3A

	static func isWordDelimiter(_ character: UniChar) -> Bool {
		(CharacterSet.whitespacesAndNewlines as NSCharacterSet).characterIsMember(character)
			|| character == comma
	}

	static func isSuffixDelimiter(_ character: UniChar) -> Bool {
		isWordDelimiter(character) || character == colon
	}
}
