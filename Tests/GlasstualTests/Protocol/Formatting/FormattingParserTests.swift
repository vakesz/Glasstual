// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
@testable import Glasstual
import Testing

@Suite("Formatting parser")
struct FormattingParserTests {
	private func has(_ key: NSAttributedString.Key, in parsed: NSAttributedString, at index: Int) -> Bool {
		parsed.attribute(key, at: index, effectiveRange: nil) != nil
	}

	@Test("0x16 reverses colours and is not italic")
	func reverseIsNotItalic() {
		let parsed = FormattingParser.parse("a\u{16}b\u{16}c")

		#expect(parsed.string == "abc")
		#expect(has(IRCFormattingAttribute.reverse, in: parsed, at: 0) == false)
		#expect(has(IRCFormattingAttribute.reverse, in: parsed, at: 1))
		#expect(has(IRCFormattingAttribute.reverse, in: parsed, at: 2) == false)
		for index in 0 ..< parsed.length {
			#expect(has(IRCFormattingAttribute.italic, in: parsed, at: index) == false)
		}
	}

	@Test("0x1D still toggles italic and not reverse")
	func italicIsNotReverse() {
		let parsed = FormattingParser.parse("\u{1D}it")

		#expect(has(IRCFormattingAttribute.italic, in: parsed, at: 0))
		#expect(has(IRCFormattingAttribute.reverse, in: parsed, at: 0) == false)
	}

	@Test("The terminator clears reverse")
	func terminatorClearsReverse() {
		let parsed = FormattingParser.parse("\u{16}a\u{0F}b")

		#expect(parsed.string == "ab")
		#expect(has(IRCFormattingAttribute.reverse, in: parsed, at: 0))
		#expect(has(IRCFormattingAttribute.reverse, in: parsed, at: 1) == false)
	}

	@Test("Stripping control codes still removes 0x16")
	func strippingRemovesReverse() {
		#expect(TextFormatting.removingControlCodes(from: "a\u{16}b") == "ab")
	}

	@Test("Colour codes after removed controls are read where they were written")
	func colourAfterRemovedControls() {
		let parsed = FormattingParser.parse("\u{02}\u{1F}\u{03}04,02red\u{0F}\u{03}99x")

		#expect(parsed.string == "redx")
		#expect(has(IRCFormattingAttribute.bold, in: parsed, at: 0))
		#expect(has(IRCFormattingAttribute.underline, in: parsed, at: 0))
		#expect((parsed.attribute(IRCFormattingAttribute.foregroundColor, at: 0, effectiveRange: nil) as? NSNumber)?.intValue == 4)
		#expect((parsed.attribute(IRCFormattingAttribute.backgroundColor, at: 0, effectiveRange: nil) as? NSNumber)?.intValue == 2)
		#expect(has(IRCFormattingAttribute.foregroundColor, in: parsed, at: 3) == false)
		#expect(has(IRCFormattingAttribute.backgroundColor, in: parsed, at: 3) == false)
		#expect(has(IRCFormattingAttribute.bold, in: parsed, at: 3) == false)
	}

	@Test("A hexadecimal colour after removed controls is read at its source position")
	func hexColourAfterRemovedControls() throws {
		let parsed = FormattingParser.parse("\u{07}\u{02}\u{04}FF0000,0000FFtext")

		#expect(parsed.string == "text")
		let foreground = try #require(
			parsed.attribute(IRCFormattingAttribute.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
		)
		let background = try #require(
			parsed.attribute(IRCFormattingAttribute.backgroundColor, at: 0, effectiveRange: nil) as? NSColor
		)
		#expect(foreground == MircColorChannels(red: 1, green: 0, blue: 0).color)
		#expect(background == MircColorChannels(red: 0, green: 0, blue: 1).color)
	}

	@Test("A bare colour code clears both halves after removed controls")
	func bareColourCodeResets() {
		let parsed = FormattingParser.parse("\u{07}\u{03}04,02a\u{07}\u{03}b")

		#expect(parsed.string == "ab")
		#expect(has(IRCFormattingAttribute.foregroundColor, in: parsed, at: 0))
		#expect(has(IRCFormattingAttribute.foregroundColor, in: parsed, at: 1) == false)
		#expect(has(IRCFormattingAttribute.backgroundColor, in: parsed, at: 1) == false)
	}

	@Test("Colour codes read from a line with astral characters ahead of them")
	func colourAfterAstralCharacters() {
		let parsed = FormattingParser.parse("😀\u{03}05x")

		#expect(parsed.string == "😀x")
		#expect((parsed.attribute(IRCFormattingAttribute.foregroundColor, at: 2, effectiveRange: nil) as? NSNumber)?.intValue == 5)
	}
}
