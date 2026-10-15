// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Control character disposition")
struct ControlCharacterDispositionTests {
	@Test("Each representative unit is kept, drawn as a space or removed", arguments: [
		(UniChar(0x41), ControlCharacterDisposition.keep),
		(0x09, .keep),
		(0x0A, .space),
		(0x0D, .space),
		(0x85, .space),
		(0x2028, .space),
		(0x2029, .space),
		(0x00, .remove),
		(0x07, .remove),
		(0x1B, .remove),
		(0x7F, .remove),
		(0x9F, .remove),
		(0x202E, .remove),
		(0x2066, .remove),
		(0x2069, .remove),
		(0x00E9, .keep),
	])
	func disposition(unit: UniChar, expected: ControlCharacterDisposition) {
		#expect(ControlCharacterDisposition(of: unit) == expected)
	}

	@Test("Single-line text replaces separators with spaces and drops other controls")
	func singleLine() {
		#expect(ControlCharacterDisposition.singleLine("a\nb\u{2028}c\u{07}d\u{202E}e\tf") == "a b cde\tf")
		#expect(ControlCharacterDisposition.singleLine("plain é 👍") == "plain é 👍")
	}

	@Test("Only text with a changed unit needs sanitizing")
	func needsSanitizing() {
		#expect(ControlCharacterDisposition.needsSanitizing("plain\ttext") == false)
		#expect(ControlCharacterDisposition.needsSanitizing("a\nb"))
		#expect(ControlCharacterDisposition.needsSanitizing("a\u{200F}b") == false)
	}

	@Test("Sanitizing attributed text keeps the attributes of what remains")
	func sanitizeKeepsAttributes() {
		let key = NSAttributedString.Key("test")
		let text = NSMutableAttributedString(string: "ab\ncd\u{07}e", attributes: [key: 1])
		ControlCharacterDisposition.sanitize(text)
		#expect(text.string == "ab cde")
		var range = NSRange()
		_ = text.attribute(key, at: 0, effectiveRange: &range)
		#expect(range == NSRange(location: 0, length: 6))
	}
}

@MainActor
@Suite("Formatting parser attributes")
struct FormattingParserAttributeTests {
	@Test("Bold toggles mark exactly the text between the codes and the codes are consumed")
	func bold() {
		let result = FormattingParser.parse("a\u{02}b\u{02}c")
		#expect(result.string == "abc")
		#expect(result.attribute(IRCFormattingAttribute.bold, at: 0, effectiveRange: nil) == nil)
		#expect(result.attribute(IRCFormattingAttribute.bold, at: 1, effectiveRange: nil) != nil)
		#expect(result.attribute(IRCFormattingAttribute.bold, at: 2, effectiveRange: nil) == nil)
	}

	@Test("A colour code sets the foreground and a reset clears it")
	func colour() {
		let result = FormattingParser.parse("\u{03}4red\u{0F}plain")
		#expect(result.string == "redplain")
		#expect(result.attribute(IRCFormattingAttribute.foregroundColor, at: 0, effectiveRange: nil) != nil)
		#expect(result.attribute(IRCFormattingAttribute.foregroundColor, at: 5, effectiveRange: nil) == nil)
	}

	@Test("Other control characters are settled during the parse")
	func controlCharacters() {
		#expect(FormattingParser.parse("a\nb\u{07}c").string == "a bc")
	}
}
