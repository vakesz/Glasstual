/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
@testable import Glasstual
import XCTest

@MainActor
final class IRCColorFormatMigrationTests: XCTestCase {
	func testBooleanEffectsUseMatchingOpenAndCloseCharacters() throws {
		let bold = try XCTUnwrap(TextFormatterEffect(effect: .bold))
		let italic = try XCTUnwrap(TextFormatterEffect(effect: .italic))
		let monospace = try XCTUnwrap(TextFormatterEffect(effect: .monospace))
		let strike = try XCTUnwrap(TextFormatterEffect(effect: .strikethrough))
		let underline = try XCTUnwrap(TextFormatterEffect(effect: .underline))

		XCTAssertEqual(bold.controlCharacter, unichar(IRCTextFormatterControlCharacter.bold))
		XCTAssertEqual(italic.controlCharacter, unichar(IRCTextFormatterControlCharacter.italic))
		XCTAssertEqual(monospace.controlCharacter, unichar(IRCTextFormatterControlCharacter.monospace))
		XCTAssertEqual(strike.controlCharacter, unichar(IRCTextFormatterControlCharacter.strikethrough))
		XCTAssertEqual(underline.controlCharacter, unichar(IRCTextFormatterControlCharacter.underline))
		XCTAssertEqual(bold.length, 2)
		XCTAssertNil(bold.value)

		let buffer = NSMutableString()
		bold.appendToStart(of: buffer)
		buffer.append("x")
		bold.appendToEnd(of: buffer)

		XCTAssertEqual(buffer.length, 3)
		XCTAssertEqual(controlCharacter(at: 0, in: buffer as String), unichar(IRCTextFormatterControlCharacter.bold))
		XCTAssertEqual(controlCharacter(at: 2, in: buffer as String), unichar(IRCTextFormatterControlCharacter.bold))
	}

	func testSpoilerIsAnAliasAndDoesNotCreateAnEffect() {
		XCTAssertNil(TextFormatterEffect(effect: .spoiler))
		XCTAssertNil(TextFormatterEffect(effect: .spoiler, withValue: true))
	}

	func testDigitAndHexColorsEncodeValuesAndBackgroundNeedsMatchingForeground() throws {
		let digitForeground = try XCTUnwrap(
			TextFormatterEffect(effect: .foregroundColor, withValue: 4)
		)
		let hexForeground = try XCTUnwrap(
			TextFormatterEffect(effect: .foregroundColor, withValue: NSColor.red)
		)
		let backgroundOnly = TextFormatterEffect(effect: .backgroundColor, withValue: 4)

		XCTAssertEqual(digitForeground.controlCharacter, unichar(IRCTextFormatterControlCharacter.colorDigit))
		XCTAssertEqual(digitForeground.value, "04")
		XCTAssertEqual(digitForeground.length, 4)
		XCTAssertEqual(hexForeground.controlCharacter, unichar(IRCTextFormatterControlCharacter.colorHex))
		XCTAssertEqual(hexForeground.value?.count, 6)
		XCTAssertNotNil(backgroundOnly)

		let digitPair: [String: Any] = [
			IRCTextFormatterAttributeName.foregroundColorAttributeName.rawValue: 4,
			IRCTextFormatterAttributeName.backgroundColorAttributeName.rawValue: 14,
		]
		let matching = TextFormatterEffects(attributes: digitPair)

		XCTAssertEqual(matching.effects.count, 2)
		XCTAssertEqual(matching.maximumLength, 7)

		let mismatched: [String: Any] = [
			IRCTextFormatterAttributeName.foregroundColorAttributeName.rawValue: 4,
			IRCTextFormatterAttributeName.backgroundColorAttributeName.rawValue: NSColor.blue,
		]
		let onlyForeground = TextFormatterEffects(attributes: mismatched)

		XCTAssertEqual(onlyForeground.effects.count, 1)

		let backgroundAlone: [String: Any] = [
			IRCTextFormatterAttributeName.backgroundColorAttributeName.rawValue: 4,
		]

		XCTAssertTrue(TextFormatterEffects(attributes: backgroundAlone).effects.isEmpty)
	}

	func testStringFormattedForIRCWrapsSegmentsWithControlCharacters() {
		let string = NSMutableAttributedString(
			string: "hello",
			attributes: [.font: NSFont.systemFont(ofSize: 13)]
		)
		string.setIRCFormatterAttribute(.bold, value: true, range: NSRange(location: 0, length: string.length))
		string.setIRCFormatterAttribute(.italic, value: true, range: NSRange(location: 0, length: string.length))

		let formatted = string.stringFormattedForIRC

		XCTAssertTrue(string.ircFormatterAttributeSet(
			inRange: .bold,
			range: NSRange(location: 0, length: string.length)
		))
		XCTAssertTrue(string.ircFormatterAttributeSet(
			inRange: .italic,
			range: NSRange(location: 0, length: string.length)
		))
		XCTAssertEqual(controlCharacter(at: 0, in: formatted), unichar(IRCTextFormatterControlCharacter.bold))
		XCTAssertEqual(controlCharacter(at: 1, in: formatted), unichar(IRCTextFormatterControlCharacter.italic))
		XCTAssertEqual((formatted as NSString).substring(with: NSRange(location: 2, length: 5)), "hello")
		XCTAssertEqual(controlCharacter(at: 7, in: formatted), unichar(IRCTextFormatterControlCharacter.italic))
		XCTAssertEqual(controlCharacter(at: 8, in: formatted), unichar(IRCTextFormatterControlCharacter.bold))
	}

	func testColorAttributeSetRequiresValidCodesAndNSColorIsAccepted() {
		let string = NSMutableAttributedString(
			string: "hi",
			attributes: [.font: NSFont.systemFont(ofSize: 13)]
		)

		string.setIRCFormatterAttribute(.foregroundColor, value: 99, range: NSRange(location: 0, length: string.length))
		XCTAssertFalse(string.ircFormatterAttributeSet(
			inRange: .foregroundColor,
			range: NSRange(location: 0, length: string.length)
		))

		string.setIRCFormatterAttribute(.foregroundColor, value: 12, range: NSRange(location: 0, length: string.length))
		XCTAssertTrue(string.ircFormatterAttributeSet(
			inRange: .foregroundColor,
			range: NSRange(location: 0, length: string.length)
		))

		string.setIRCFormatterAttribute(
			.backgroundColor,
			value: NSColor.black,
			range: NSRange(location: 0, length: string.length)
		)
		XCTAssertTrue(string.ircFormatterAttributeSet(
			inRange: .backgroundColor,
			range: NSRange(location: 0, length: string.length)
		))
	}

	func testRemovingBoldClearsFormatterAndTrait() {
		let string = NSMutableAttributedString(
			string: "bold",
			attributes: [.font: NSFont.systemFont(ofSize: 13)]
		)
		string.setIRCFormatterAttribute(.bold, value: true, range: NSRange(location: 0, length: string.length))
		XCTAssertTrue(string.ircFormatterAttributeSet(
			inRange: .bold,
			range: NSRange(location: 0, length: string.length)
		))

		string.removeIRCFormatterAttribute(.bold, range: NSRange(location: 0, length: string.length))

		XCTAssertFalse(string.ircFormatterAttributeSet(
			inRange: .bold,
			range: NSRange(location: 0, length: string.length)
		))
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
