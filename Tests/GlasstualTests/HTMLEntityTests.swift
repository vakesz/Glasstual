/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// The log view writes messages through `escapingForHTML` and reads values back
/// from JavaScript through `unescapingFromHTML`.
@Suite("HTML entities")
struct HTMLEntityTests {
	@Test("The characters that could become markup are escaped")
	func markupCharactersAreEscaped() {
		#expect("<b>".escapingForHTML == "&lt;b&gt;")
		#expect("a & b".escapingForHTML == "a &amp; b")
		#expect(#""quoted""#.escapingForHTML == "&quot;quoted&quot;")
		#expect("it's".escapingForHTML == "it&apos;s")
	}

	@Test("Escaping is not applied twice")
	func escapingIsNotReapplied() {
		#expect("&lt;".escapingForHTML == "&amp;lt;")
		#expect("<script>alert(1)</script>".escapingForHTML.contains("<") == false)
	}

	@Test("Ordinary text and emoji pass through untouched")
	func ordinaryTextPassesThrough() {
		#expect("hello world".escapingForHTML == "hello world")
		#expect("😀 IRC".escapingForHTML == "😀 IRC")
		#expect("".escapingForHTML == "")
	}

	@Test("Named entities are resolved")
	func namedEntitiesAreResolved() {
		#expect("&lt;b&gt;".unescapingFromHTML == "<b>")
		#expect("a &amp; b".unescapingFromHTML == "a & b")
		#expect("&nbsp;".unescapingFromHTML == "\u{00A0}")
		#expect("&hearts;".unescapingFromHTML == "\u{2665}")
	}

	@Test("Decimal and hexadecimal character references are resolved")
	func numericReferencesAreResolved() {
		#expect("&#38;".unescapingFromHTML == "&")
		#expect("&#x26;".unescapingFromHTML == "&")
		#expect("&#X26;".unescapingFromHTML == "&")
		#expect("&#128512;".unescapingFromHTML == "😀")
		#expect("&#x1F600;".unescapingFromHTML == "😀")
	}

	@Test("Anything that is not an entity is left exactly as written")
	func nonEntitiesSurvive() {
		#expect("Tom & Jerry".unescapingFromHTML == "Tom & Jerry")
		#expect("&notanentity;".unescapingFromHTML == "&notanentity;")
		#expect("&".unescapingFromHTML == "&")
		#expect("&;".unescapingFromHTML == "&;")
		#expect("&#0;".unescapingFromHTML == "&#0;")
		/* A run longer than the longest entity is not searched. */
		#expect("&aaaaaaaaaaaaaaa;".unescapingFromHTML == "&aaaaaaaaaaaaaaa;")
	}

	@Test("Escaping and unescaping round-trip", arguments: [
		"<b>bold</b>",
		"a & b < c > d",
		#"say "hello" & 'goodbye'"#,
		"plain text with no markup",
		"😀 mixed \u{2665} content",
		"",
	])
	func roundTripIsLossless(_ source: String) {
		#expect(source.escapingForHTML.unescapingFromHTML == source)
	}

	@Test("Several entities in one string are all resolved")
	func multipleEntitiesAreResolved() {
		#expect("&lt;a&gt;&amp;&lt;b&gt;".unescapingFromHTML == "<a>&<b>")
		#expect("x&#38;y&#60;z".unescapingFromHTML == "x&y<z")
	}
}

@Suite("Unicode classification")
struct UnicodeClassificationTests {
	@Test("ASCII letters are alphabetic and everything else is not")
	func asciiIsClassified() {
		#expect(UnicodeHelper.isAlphabeticalCodePoint(Int(Unicode.Scalar("A").value)))
		#expect(UnicodeHelper.isAlphabeticalCodePoint(Int(Unicode.Scalar("z").value)))
		#expect(UnicodeHelper.isAlphabeticalCodePoint(Int(Unicode.Scalar("1").value)) == false)
		#expect(UnicodeHelper.isAlphabeticalCodePoint(Int(Unicode.Scalar(" ").value)) == false)
		#expect(UnicodeHelper.isAlphabeticalCodePoint(Int(Unicode.Scalar("#").value)) == false)
	}

	@Test("Scripts the old range tables covered still classify the same way", arguments: [
		0x00E9, // é      LATIN SMALL LETTER E WITH ACUTE
		0x03B1, // α      GREEK SMALL LETTER ALPHA
		0x0430, // а      CYRILLIC SMALL LETTER A
		0x05D0, // א      HEBREW LETTER ALEF
		0x0621, // ء      ARABIC LETTER HAMZA
		0x4E00, // 一     CJK UNIFIED IDEOGRAPH
	])
	func coveredScriptsAreStillAlphabetic(_ codePoint: Int) {
		#expect(UnicodeHelper.isAlphabeticalCodePoint(codePoint))
	}

	@Test("Scripts added after the old tables were generated now classify correctly", arguments: [
		0x1E900, // 𞤀    ADLAM CAPITAL LETTER ALIF
		0x104B0, // 𐒰    OSAGE CAPITAL LETTER A
		0x13A0, //  Ꭰ     CHEROKEE LETTER A
		0xAB70, //  ꭰ     CHEROKEE SMALL LETTER A
	])
	func newScriptsAreAlphabetic(_ codePoint: Int) {
		#expect(UnicodeHelper.isAlphabeticalCodePoint(codePoint))
	}

	@Test("Punctuation, symbols and invalid code points are not alphabetic", arguments: [
		0x2665, // ♥
		0x1F600, // 😀
		0xD800, // lone surrogate, not a scalar
		0x110000, // beyond the Unicode range
		-1,
	])
	func nonLettersAreRejected(_ codePoint: Int) {
		#expect(UnicodeHelper.isAlphabeticalCodePoint(codePoint) == false)
	}
}
