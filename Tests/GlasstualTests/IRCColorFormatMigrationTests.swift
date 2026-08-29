/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

@MainActor
@Suite("IRC colour and formatting")
struct IRCColorFormatMigrationTests {
	@Test("A boolean effect opens and closes with the same control character")
	func booleanEffectsUseMatchingOpenAndCloseCharacters() throws {
		let bold = try #require(TextFormatterEffect(effect: .bold))
		let italic = try #require(TextFormatterEffect(effect: .italic))
		let monospace = try #require(TextFormatterEffect(effect: .monospace))
		let strike = try #require(TextFormatterEffect(effect: .strikethrough))
		let underline = try #require(TextFormatterEffect(effect: .underline))

		#expect(bold.controlCharacter == unichar(IRCTextFormatterControlCharacter.bold))
		#expect(italic.controlCharacter == unichar(IRCTextFormatterControlCharacter.italic))
		#expect(monospace.controlCharacter == unichar(IRCTextFormatterControlCharacter.monospace))
		#expect(strike.controlCharacter == unichar(IRCTextFormatterControlCharacter.strikethrough))
		#expect(underline.controlCharacter == unichar(IRCTextFormatterControlCharacter.underline))
		#expect(bold.length == 2)
		#expect(bold.value == nil)

		var buffer = ""
		bold.appendToStart(of: &buffer)
		buffer.append("x")
		bold.appendToEnd(of: &buffer)

		#expect(buffer.count == 3)
		#expect(controlCharacter(at: 0, in: buffer) == unichar(IRCTextFormatterControlCharacter.bold))
		#expect(controlCharacter(at: 2, in: buffer) == unichar(IRCTextFormatterControlCharacter.bold))
	}

	@Test("Spoiler is an alias, so it never becomes an effect of its own")
	func spoilerIsAnAliasAndDoesNotCreateAnEffect() {
		#expect(TextFormatterEffect(effect: .spoiler) == nil)
		#expect(TextFormatterEffect(effect: .spoiler, withValue: true) == nil)
	}

	@Test("Digit and hex colours encode their value, and a background needs a foreground")
	func digitAndHexColorsEncodeValuesAndBackgroundNeedsMatchingForeground() throws {
		let digitForeground = try #require(
			TextFormatterEffect(effect: .foregroundColor, withValue: 4)
		)
		let hexForeground = try #require(
			TextFormatterEffect(effect: .foregroundColor, withValue: NSColor.red)
		)
		let backgroundOnly = TextFormatterEffect(effect: .backgroundColor, withValue: 4)

		#expect(digitForeground.controlCharacter == unichar(IRCTextFormatterControlCharacter.colorDigit))
		#expect(digitForeground.value == "04")
		#expect(digitForeground.length == 4)
		#expect(hexForeground.controlCharacter == unichar(IRCTextFormatterControlCharacter.colorHex))
		#expect(hexForeground.value?.count == 6)
		#expect(backgroundOnly != nil)

		let digitPair: [String: Any] = [
			IRCTextFormatterAttributeName.foregroundColorAttributeName.rawValue: 4,
			IRCTextFormatterAttributeName.backgroundColorAttributeName.rawValue: 14,
		]
		let matching = TextFormatterEffects(attributes: digitPair)

		#expect(matching.effects.count == 2)
		#expect(matching.maximumLength == 7)

		let mismatched: [String: Any] = [
			IRCTextFormatterAttributeName.foregroundColorAttributeName.rawValue: 4,
			IRCTextFormatterAttributeName.backgroundColorAttributeName.rawValue: NSColor.blue,
		]
		let onlyForeground = TextFormatterEffects(attributes: mismatched)

		#expect(onlyForeground.effects.count == 1)

		let backgroundAlone: [String: Any] = [
			IRCTextFormatterAttributeName.backgroundColorAttributeName.rawValue: 4,
		]

		#expect(TextFormatterEffects(attributes: backgroundAlone).effects.isEmpty)
	}

	@Test("A formatted segment is wrapped in the control characters it was given")
	func stringFormattedForIRCWrapsSegmentsWithControlCharacters() {
		let string = NSMutableAttributedString(
			string: "hello",
			attributes: [.font: NSFont.systemFont(ofSize: 13)]
		)
		string.setIRCFormatterAttribute(.bold, value: true, range: NSRange(location: 0, length: string.length))
		string.setIRCFormatterAttribute(.italic, value: true, range: NSRange(location: 0, length: string.length))

		let formatted = string.stringFormattedForIRC

		#expect(string.ircFormatterAttributeSet(
			inRange: .bold,
			range: NSRange(location: 0, length: string.length)
		))
		#expect(string.ircFormatterAttributeSet(
			inRange: .italic,
			range: NSRange(location: 0, length: string.length)
		))
		#expect(controlCharacter(at: 0, in: formatted) == unichar(IRCTextFormatterControlCharacter.bold))
		#expect(controlCharacter(at: 1, in: formatted) == unichar(IRCTextFormatterControlCharacter.italic))
		#expect((formatted as NSString).substring(with: NSRange(location: 2, length: 5)) == "hello")
		#expect(controlCharacter(at: 7, in: formatted) == unichar(IRCTextFormatterControlCharacter.italic))
		#expect(controlCharacter(at: 8, in: formatted) == unichar(IRCTextFormatterControlCharacter.bold))
	}

	@Test("A colour attribute is only set for a valid code, and an NSColor is accepted")
	func colorAttributeSetRequiresValidCodesAndNSColorIsAccepted() {
		let string = NSMutableAttributedString(
			string: "hi",
			attributes: [.font: NSFont.systemFont(ofSize: 13)]
		)

		string.setIRCFormatterAttribute(.foregroundColor, value: 99, range: NSRange(location: 0, length: string.length))

		#expect(string.ircFormatterAttributeSet(
			inRange: .foregroundColor,
			range: NSRange(location: 0, length: string.length)
		) == false)

		string.setIRCFormatterAttribute(.foregroundColor, value: 12, range: NSRange(location: 0, length: string.length))

		#expect(string.ircFormatterAttributeSet(
			inRange: .foregroundColor,
			range: NSRange(location: 0, length: string.length)
		))

		string.setIRCFormatterAttribute(
			.backgroundColor,
			value: NSColor.black,
			range: NSRange(location: 0, length: string.length)
		)

		#expect(string.ircFormatterAttributeSet(
			inRange: .backgroundColor,
			range: NSRange(location: 0, length: string.length)
		))
	}

	@Test("Removing bold clears both the formatter attribute and the font trait")
	func removingBoldClearsFormatterAndTrait() {
		let string = NSMutableAttributedString(
			string: "bold",
			attributes: [.font: NSFont.systemFont(ofSize: 13)]
		)
		string.setIRCFormatterAttribute(.bold, value: true, range: NSRange(location: 0, length: string.length))

		#expect(string.ircFormatterAttributeSet(
			inRange: .bold,
			range: NSRange(location: 0, length: string.length)
		))

		string.removeIRCFormatterAttribute(.bold, range: NSRange(location: 0, length: string.length))

		#expect(string.ircFormatterAttributeSet(
			inRange: .bold,
			range: NSRange(location: 0, length: string.length)
		) == false)
	}

	@Test("Wrapping deletes back to the nearest whitespace inside the maximum distance")
	func wrapHelperDeletesBackToWhitespaceInsideMaxDistance() {
		var string = "aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii"
		let deleted = string.wrapIRCTextFormatterResult(with: 0, maxDistance: 25)

		#expect(deleted != UInt(bitPattern: NSNotFound))
		#expect(string.hasPrefix("aaaa bbbb cccc dddd eeee ffff gggg hhhh"))
		#expect(string.contains("iiii") == false)
		#expect(string.hasSuffix(" ") == false)
	}

	@Test("A long channel message is truncated and reports the range it consumed")
	func channelFormattingTruncatesLongMessagesAndReportsEffectiveRange() {
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

		#expect(formatted.isEmpty == false)
		#expect(formatted.utf16.count < payload.utf16.count)
		#expect(effectiveRange.location == 0)
		#expect(effectiveRange.length > 0)
		#expect(effectiveRange.length < payload.utf16.count)
	}

	@Test("The cursor drops the prefix each line consumed")
	func lineCursorDropsTheConsumedPrefix() {
		let client = GLTTestClient()
		let payload = String(String(repeating: "word ", count: 160).prefix(800))
		var cursor = IRCLineCursor(NSAttributedString(string: payload))

		let formatted = cursor.nextLine(forChannel: "#test", on: client, with: .notice)

		#expect(formatted?.isEmpty == false)
		#expect(cursor.isEmpty == false)

		var remaining = 0
		while cursor.nextLine(forChannel: "#test", on: client, with: .notice) != nil {
			remaining += 1
		}

		#expect(remaining > 0)
		#expect(cursor.isEmpty)
	}

	private func controlCharacter(at index: Int, in string: String) -> unichar {
		(string as NSString).character(at: index)
	}
}
