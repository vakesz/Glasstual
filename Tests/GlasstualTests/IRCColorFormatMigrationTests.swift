/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import XCTest

@MainActor
final class IRCColorFormatMigrationTests: XCTestCase {
	func testBooleanEffectsUseMatchingOpenAndCloseCharacters() throws {
		let bold = try XCTUnwrap(IRCTextFormatterEffect(type: .bold))
		let italic = try XCTUnwrap(IRCTextFormatterEffect(type: .italic))
		let monospace = try XCTUnwrap(IRCTextFormatterEffect(type: .monospace))
		let strike = try XCTUnwrap(IRCTextFormatterEffect(type: .strikethrough))
		let underline = try XCTUnwrap(IRCTextFormatterEffect(type: .underline))

		XCTAssertEqual(bold.controlCharacter, unichar(IRCTextFormatterEffectBoldCharacter))
		XCTAssertEqual(italic.controlCharacter, unichar(IRCTextFormatterEffectItalicCharacter))
		XCTAssertEqual(monospace.controlCharacter, unichar(IRCTextFormatterEffectMonospaceCharacter))
		XCTAssertEqual(strike.controlCharacter, unichar(IRCTextFormatterEffectStrikethroughCharacter))
		XCTAssertEqual(underline.controlCharacter, unichar(IRCTextFormatterEffectUnderlineCharacter))
		XCTAssertEqual(bold.length, 2)
		XCTAssertNil(bold.value)

		let buffer = NSMutableString()
		bold.append(toStartOf: buffer)
		buffer.append("x")
		bold.append(toEndOf: buffer)

		XCTAssertEqual(buffer.length, 3)
		XCTAssertEqual(controlCharacter(at: 0, in: buffer as String), unichar(IRCTextFormatterEffectBoldCharacter))
		XCTAssertEqual(controlCharacter(at: 2, in: buffer as String), unichar(IRCTextFormatterEffectBoldCharacter))
	}

	func testSpoilerIsAnAliasAndDoesNotCreateAnEffect() {
		XCTAssertNil(IRCTextFormatterEffect(type: .spoiler))
		XCTAssertNil(IRCTextFormatterEffect(type: .spoiler, withValue: true))
	}

	func testDigitAndHexColorsEncodeValuesAndBackgroundNeedsMatchingForeground() throws {
		let digitForeground = try XCTUnwrap(
			IRCTextFormatterEffect(type: .foregroundColor, withValue: 4)
		)
		let hexForeground = try XCTUnwrap(
			IRCTextFormatterEffect(type: .foregroundColor, withValue: NSColor.red)
		)
		let backgroundOnly = IRCTextFormatterEffect(type: .backgroundColor, withValue: 4)

		XCTAssertEqual(digitForeground.controlCharacter, unichar(IRCTextFormatterEffectColorAsDigitCharacter))
		XCTAssertEqual(digitForeground.value, "04")
		XCTAssertEqual(digitForeground.length, 4)
		XCTAssertEqual(hexForeground.controlCharacter, unichar(IRCTextFormatterEffectColorAsHexCharacter))
		XCTAssertEqual(hexForeground.value?.count, 6)
		XCTAssertNotNil(backgroundOnly)

		let digitPair: [String: Any] = [
			IRCTextFormatterAttributeName.foregroundColorAttributeName.rawValue: 4,
			IRCTextFormatterAttributeName.backgroundColorAttributeName.rawValue: 14,
		]
		let matching = IRCTextFormatterEffects(inAttributes: digitPair)

		XCTAssertEqual(matching.effects.count, 2)
		XCTAssertEqual(matching.maximumLength, 7)

		let mismatched: [String: Any] = [
			IRCTextFormatterAttributeName.foregroundColorAttributeName.rawValue: 4,
			IRCTextFormatterAttributeName.backgroundColorAttributeName.rawValue: NSColor.blue,
		]
		let onlyForeground = IRCTextFormatterEffects(inAttributes: mismatched)

		XCTAssertEqual(onlyForeground.effects.count, 1)

		let backgroundAlone: [String: Any] = [
			IRCTextFormatterAttributeName.backgroundColorAttributeName.rawValue: 4,
		]

		XCTAssertTrue(IRCTextFormatterEffects(inAttributes: backgroundAlone).effects.isEmpty)
	}

	func testStringFormattedForIRCWrapsSegmentsWithControlCharacters() {
		let string = NSMutableAttributedString(
			string: "hello",
			attributes: [.font: NSFont.systemFont(ofSize: 13)]
		)
		string.setIRCFormatterAttribute(.bold, value: true, range: string.range)
		string.setIRCFormatterAttribute(.italic, value: true, range: string.range)

		let formatted = string.stringFormattedForIRC

		XCTAssertTrue(string.ircFormatterAttributeSet(inRange: .bold, range: string.range))
		XCTAssertTrue(string.ircFormatterAttributeSet(inRange: .italic, range: string.range))
		XCTAssertEqual(controlCharacter(at: 0, in: formatted), unichar(IRCTextFormatterEffectBoldCharacter))
		XCTAssertEqual(controlCharacter(at: 1, in: formatted), unichar(IRCTextFormatterEffectItalicCharacter))
		XCTAssertEqual((formatted as NSString).substring(with: NSRange(location: 2, length: 5)), "hello")
		XCTAssertEqual(controlCharacter(at: 7, in: formatted), unichar(IRCTextFormatterEffectItalicCharacter))
		XCTAssertEqual(controlCharacter(at: 8, in: formatted), unichar(IRCTextFormatterEffectBoldCharacter))
	}

	func testColorAttributeSetRequiresValidCodesAndNSColorIsAccepted() {
		let string = NSMutableAttributedString(
			string: "hi",
			attributes: [.font: NSFont.systemFont(ofSize: 13)]
		)

		string.setIRCFormatterAttribute(.foregroundColor, value: 99, range: string.range)
		XCTAssertFalse(string.ircFormatterAttributeSet(inRange: .foregroundColor, range: string.range))

		string.setIRCFormatterAttribute(.foregroundColor, value: 12, range: string.range)
		XCTAssertTrue(string.ircFormatterAttributeSet(inRange: .foregroundColor, range: string.range))

		string.setIRCFormatterAttribute(.backgroundColor, value: NSColor.black, range: string.range)
		XCTAssertTrue(string.ircFormatterAttributeSet(inRange: .backgroundColor, range: string.range))
	}

	func testRemovingBoldClearsFormatterAndTrait() {
		let string = NSMutableAttributedString(
			string: "bold",
			attributes: [.font: NSFont.systemFont(ofSize: 13)]
		)
		string.setIRCFormatterAttribute(.bold, value: true, range: string.range)
		XCTAssertTrue(string.ircFormatterAttributeSet(inRange: .bold, range: string.range))

		string.removeIRCFormatterAttribute(.bold, range: string.range)

		XCTAssertFalse(string.ircFormatterAttributeSet(inRange: .bold, range: string.range))
	}

	func testWrapHelperDeletesBackToWhitespaceInsideMaxDistance() {
		let string = NSMutableString(string: "aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii")
		let deleted = string.wrapIRCTextFormatterResult(with: 0, maxDistance: 25)

		XCTAssertNotEqual(deleted, UInt(bitPattern: NSNotFound))
		XCTAssertTrue(string.hasPrefix("aaaa bbbb cccc dddd eeee ffff gggg hhhh"))
		XCTAssertEqual(string.range(of: "iiii").location, NSNotFound)
		XCTAssertFalse(string.hasSuffix(" "))
	}

	func testChannelFormattingTruncatesLongMessagesAndReportsEffectiveRange() {
		let client = GLTTestClient()
		let payload = String(repeating: "abcdefghij ", count: 73).prefix(800)
		let string = NSAttributedString(string: String(payload))
		var effectiveRange = NSRange(location: NSNotFound, length: 0)

		let formatted = string.stringFormatted(
			forChannel: "#test",
			on: client,
			with: .privateMessage,
			effectiveRange: &effectiveRange
		)

		XCTAssertFalse(formatted.isEmpty)
		XCTAssertLessThan(formatted.utf16.count, payload.utf16.count)
		XCTAssertEqual(effectiveRange.location, 0)
		XCTAssertGreaterThan(effectiveRange.length, 0)
		XCTAssertLessThan(effectiveRange.length, payload.utf16.count)
	}

	func testMutableChannelFormattingDeletesConsumedPrefix() {
		let client = GLTTestClient()
		let payload = String(String(repeating: "word ", count: 160).prefix(800))
		let string = NSMutableAttributedString(string: payload)
		let originalLength = string.length

		let formatted = string.stringFormatted(forChannel: "#test", on: client, with: .notice)

		XCTAssertFalse(formatted.isEmpty)
		XCTAssertLessThan(string.length, originalLength)
		XCTAssertEqual(string.length + formatted.utf16.count, originalLength)
	}

	private func controlCharacter(at index: Int, in string: String) -> unichar {
		(string as NSString).character(at: index)
	}
}
