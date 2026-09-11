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
struct IRCColorFormatTests {
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

		let digitPair: [NSAttributedString.Key: Any] = [
			formatterKey(.foregroundColorAttributeName): 4,
			formatterKey(.backgroundColorAttributeName): 14,
		]
		let matching = TextFormatterEffects(attributes: digitPair)

		#expect(matching.effects.count == 2)
		#expect(matching.maximumLength == 7)

		let mismatched: [NSAttributedString.Key: Any] = [
			formatterKey(.foregroundColorAttributeName): 4,
			formatterKey(.backgroundColorAttributeName): NSColor.blue,
		]
		let onlyForeground = TextFormatterEffects(attributes: mismatched)

		#expect(onlyForeground.effects.count == 1)

		let backgroundAlone: [NSAttributedString.Key: Any] = [
			formatterKey(.backgroundColorAttributeName): 4,
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

	/// Clearing the foreground used to remove `.backgroundColor`, so the text
	/// stayed coloured on screen while the colour stopped going out on the wire
	/// and an unrelated background was wiped.
	@Test("Removing the foreground colour leaves the background colour alone")
	func removingForegroundColorKeepsBackgroundColor() {
		let range = NSRange(location: 0, length: 5)
		let string = NSMutableAttributedString(
			string: "color",
			attributes: [.font: NSFont.systemFont(ofSize: 13)]
		)
		string.setIRCFormatterAttribute(.foregroundColor, value: NSColor.red, range: range)
		string.setIRCFormatterAttribute(.backgroundColor, value: NSColor.blue, range: range)

		string.removeIRCFormatterAttribute(.foregroundColor, range: range)

		#expect(string.ircFormatterAttributeSet(inRange: .foregroundColor, range: range) == false)
		#expect(string.ircFormatterAttributeSet(inRange: .backgroundColor, range: range))
		#expect(string.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
		#expect(string.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor == .blue)
	}

	/// The whole run used to be skipped when it carried no font, so effects that
	/// do not need one were never removed.
	@Test("Effects that need no font are removed from a run that has none")
	func removingUnderlineWorksWithoutAFont() {
		let range = NSRange(location: 0, length: 4)
		let string = NSMutableAttributedString(string: "line")
		string.setIRCFormatterAttribute(.underline, value: true, range: range)

		#expect(string.ircFormatterAttributeSet(inRange: .underline, range: range))

		string.removeIRCFormatterAttribute(.underline, range: range)

		#expect(string.ircFormatterAttributeSet(inRange: .underline, range: range) == false)
		#expect(string.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
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

	/** What `nextLine` relies on to terminate: each line consumes a prefix, the
	 cursor never grows, and the lines together account for every character. A
	 pass that consumed nothing would loop forever. */
	@Test("The lines together consume every character exactly once")
	func linesConsumeEveryCharacterExactlyOnce() {
		let client = GLTTestClient()
		let payload = String(String(repeating: "word ", count: 160).prefix(800))
		var cursor = IRCLineCursor(NSAttributedString(string: payload))
		let payloadLength = cursor.length

		#expect(payloadLength == (payload as NSString).length)

		var consumed = 0
		while true {
			let before = cursor.length
			guard cursor.nextLine(forChannel: "#test", on: client, with: .notice) != nil else {
				break
			}
			let after = cursor.length

			#expect(after < before, "a line that consumes nothing never ends the message")
			consumed += before - after
		}

		#expect(consumed == payloadLength)
		#expect(cursor.isEmpty)
	}

	/** The same guarantee for a message that carries formatting.

	 A wrap is measured against the formatted result, which holds the control
	 codes the attributes injected, while the cursor advances through the plain
	 source. Mixing the two coordinate systems made a long formatted line
	 repeat a few words at the seam, or lose them. */
	@Test("A formatted message splits without duplicating or dropping text")
	func formattedLinesReassembleIntoTheSource() {
		let client = GLTTestClient()
		let words = (0 ..< 240).map { "word\($0)" }.joined(separator: " ")
		let text = NSMutableAttributedString(string: words)
		let bold = formatterKey(IRCTextFormatterAttributeName.boldAttributeName)
		let foreground = formatterKey(IRCTextFormatterAttributeName.foregroundColorAttributeName)

		/* Short alternating runs, so an attribute boundary — and the control
		 codes that come with it — falls inside every wrapped line. */
		var location = 0
		var runIndex = 0
		while location < text.length {
			let length = min(31, text.length - location)
			let range = NSRange(location: location, length: length)

			if runIndex.isMultiple(of: 2) {
				text.addAttribute(bold, value: true, range: range)
			} else {
				text.addAttribute(foreground, value: NSNumber(value: 4), range: range)
			}

			location += length
			runIndex += 1
		}

		var cursor = IRCLineCursor(text)
		var reassembled = ""

		while true {
			let before = cursor.length
			guard let line = cursor.nextLine(forChannel: "#test", on: client, with: .privateMessage) else {
				break
			}
			#expect(cursor.length < before, "a line that consumes nothing never ends the message")
			reassembled += stripControlCharacters(from: line)
		}

		#expect(cursor.isEmpty)
		/* A wrap hands the space it broke at back to the next line, so nothing
		 is lost and nothing is repeated: the lines are the source, in order. */
		#expect(reassembled == words)
	}

	// MARK: - Colour control codes

	/** mIRC's 99 is "no colour", not colour ninety-nine.

	 `\u{3}04,99` names a foreground and takes the background away. Reading 99
	 as an out-of-range palette index dropped it, and dropping it left whatever
	 background the previous code had set: red text kept the last line's yellow
	 behind it for the rest of the message. */
	@Test("A background of 99 clears the background rather than leaving it")
	func background99ClearsTheBackground() {
		let components = ("\u{3}04,99" as NSString).colorComponents(
			ofCharacter: unichar(IRCTextFormatterControlCharacter.colorDigit),
			startingAt: 0
		)

		#expect(components.foreground == .color(.palette(4)))
		#expect(components.background == .reset)
		#expect(components.charactersConsumed == 6)
	}

	@Test("A foreground of 99 clears the foreground and says nothing about the background")
	func foreground99ClearsOnlyTheForeground() {
		let components = ("\u{3}99" as NSString).colorComponents(
			ofCharacter: unichar(IRCTextFormatterControlCharacter.colorDigit),
			startingAt: 0
		)

		#expect(components.foreground == .reset)
		#expect(components.background == .unchanged)
		#expect(components.charactersConsumed == 3)
	}

	@Test("A foreground on its own leaves the background in force")
	func foregroundAloneLeavesTheBackgroundAlone() {
		let components = ("\u{3}04text" as NSString).colorComponents(
			ofCharacter: unichar(IRCTextFormatterControlCharacter.colorDigit),
			startingAt: 0
		)

		#expect(components.foreground == .color(.palette(4)))
		#expect(components.background == .unchanged)
		#expect(components.charactersConsumed == 3)
	}

	/// A control character with nothing readable behind it is mIRC's "colour
	/// off": both halves go. A comma with no digits in front of it is text.
	@Test("A colour code with no digits clears both halves and consumes only itself")
	func bareColourCodesClearBothHalves() {
		let bare = ("\u{3}" as NSString).colorComponents(
			ofCharacter: unichar(IRCTextFormatterControlCharacter.colorDigit),
			startingAt: 0
		)

		#expect(bare.foreground == .reset)
		#expect(bare.background == .reset)
		#expect(bare.charactersConsumed == 1)

		let comma = ("\u{3}," as NSString).colorComponents(
			ofCharacter: unichar(IRCTextFormatterControlCharacter.colorDigit),
			startingAt: 0
		)

		#expect(comma.foreground == .reset)
		#expect(comma.background == .reset)
		#expect(comma.charactersConsumed == 1)

		let shortHex = ("\u{4}0F" as NSString).colorComponents(
			ofCharacter: unichar(IRCTextFormatterControlCharacter.colorHex),
			startingAt: 0
		)

		#expect(shortHex.foreground == .reset)
		#expect(shortHex.background == .reset)
		#expect(shortHex.charactersConsumed == 1)
	}

	@Test("A hexadecimal code reads both halves as channels")
	func hexadecimalCodeReadsBothHalves() {
		let components = ("\u{4}FF8000,000102" as NSString).colorComponents(
			ofCharacter: unichar(IRCTextFormatterControlCharacter.colorHex),
			startingAt: 0
		)

		#expect(components.foreground == .color(.rgb(IRCColorChannels(
			red: 1, green: Double(0x80) / 0xFF, blue: 0
		))))
		#expect(components.background == .color(.rgb(IRCColorChannels(
			red: 0, green: Double(1) / 0xFF, blue: Double(2) / 0xFF
		))))
		#expect(components.charactersConsumed == 14)
	}

	/// A public entry point answers about a range it does not have. It used to
	/// carry a `precondition`, so a caller's arithmetic slip crashed the app.
	@Test("A start past the end of the string reads nothing instead of trapping")
	func startPastTheEndReadsNothing() {
		let components = ("\u{3}04" as NSString).colorComponents(
			ofCharacter: unichar(IRCTextFormatterControlCharacter.colorDigit),
			startingAt: 99
		)

		#expect(components.foreground == .unchanged)
		#expect(components.background == .unchanged)
		#expect(components.charactersConsumed == 0)
	}

	// MARK: - Wrapping

	/** A zero-width joiner sequence is one emoji and has to travel as one.

	 `rangeOfComposedCharacterSequence` stops at the joiner, so a wrap could
	 fall between the halves of a family and send two unrelated people. */
	@Test("A line never breaks inside a zero-width joiner sequence")
	func linesDoNotSplitJoinedEmoji() {
		let client = GLTTestClient()
		let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
		let payload = String(repeating: "\(family) ", count: 60)
		var cursor = IRCLineCursor(NSAttributedString(string: payload))
		var reassembled = ""

		while true {
			let before = cursor.length
			guard let line = cursor.nextLine(forChannel: "#test", on: client, with: .privateMessage) else {
				break
			}

			#expect(cursor.length < before, "a line that consumes nothing never ends the message")
			#expect(line.unicodeScalars.last != "\u{200D}")
			#expect(line.unicodeScalars.first != "\u{200D}")
			reassembled += line
		}

		#expect(cursor.isEmpty)
		#expect(reassembled == payload)
	}

	/** A colour code the person typed is one token too.

	 Split between the control character and its digits, the digits arrive on
	 the next line as text: the reader sees a stray "04" where a colour was. */
	@Test("A line never breaks between a colour code and its digits")
	func linesDoNotSplitColourCodes() {
		let client = GLTTestClient()
		let payload = String(repeating: "\u{3}04word\u{3} ", count: 120)
		var cursor = IRCLineCursor(NSAttributedString(string: payload))
		var reassembled = ""

		while true {
			let before = cursor.length
			guard let line = cursor.nextLine(forChannel: "#test", on: client, with: .privateMessage) else {
				break
			}

			#expect(cursor.length < before, "a line that consumes nothing never ends the message")
			#expect(endsMidColourCode(line) == false)
			reassembled += line
		}

		#expect(cursor.isEmpty)
		#expect(reassembled == payload)
	}

	/// Whether `line` ends part-way through one of the two-digit colour codes
	/// the test above wrote: the control character reached the wire with one of
	/// its two digits, and the other one arrives on the next line as text. A
	/// control character followed by anything that is not a digit — the space the
	/// payload puts after it — carries no argument and is whole.
	private func endsMidColourCode(_ line: String) -> Bool {
		let scalars = Array(line.unicodeScalars)

		guard let index = scalars.lastIndex(where: { Int($0.value) == IRCTextFormatterControlCharacter.colorDigit })
		else {
			return false
		}

		let arguments = scalars[scalars.index(after: index)...]

		return arguments.count == 1 && arguments.allSatisfy { $0.value >= 0x30 && $0.value <= 0x39 }
	}

	/** The wrap may only take back what the caller can re-queue.

	 It truncated the line unconditionally and gave the characters back only
	 when the caller could account for them; past that point the text left the
	 line being sent and nothing ever sent it. */
	@Test("Wrapping declines rather than truncate more than the caller can re-queue")
	func wrapDeclinesWhenItCannotGiveTheCharactersBack() {
		var string = "aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii"
		let unchanged = string

		#expect(
			string.wrapIRCTextFormatterResult(with: 0, maxDistance: 25, maximumGiveBack: 2)
				== UInt(bitPattern: NSNotFound)
		)
		#expect(string == unchanged)

		#expect(string.wrapIRCTextFormatterResult(with: 0, maxDistance: 25, maximumGiveBack: 5) == 5)
		#expect(string.hasSuffix("hhhh"))
	}

	/// Removes the bold and digit-colour control codes this test's attributes
	/// inject, leaving the source text the line was cut from.
	private func stripControlCharacters(from line: String) -> String {
		var result = ""
		var scalars = Array(line.unicodeScalars)[...]

		while let scalar = scalars.popFirst() {
			switch Int(scalar.value) {
			case IRCTextFormatterControlCharacter.bold, IRCTextFormatterControlCharacter.terminator:
				continue
			case IRCTextFormatterControlCharacter.colorDigit:
				scalars = droppingColorArguments(from: scalars)
			default:
				result.unicodeScalars.append(scalar)
			}
		}

		return result
	}

	/// A digit colour is up to two digits, optionally followed by a comma and
	/// up to two more for the background.
	private func droppingColorArguments(
		from scalars: ArraySlice<Unicode.Scalar>
	) -> ArraySlice<Unicode.Scalar> {
		var scalars = droppingDigits(from: scalars, limit: 2)

		guard scalars.first == "," else { return scalars }

		scalars = scalars.dropFirst()

		return droppingDigits(from: scalars, limit: 2)
	}

	private func droppingDigits(
		from scalars: ArraySlice<Unicode.Scalar>,
		limit: Int
	) -> ArraySlice<Unicode.Scalar> {
		var scalars = scalars
		var dropped = 0

		while dropped < limit, let scalar = scalars.first, scalar.value >= 0x30, scalar.value <= 0x39 {
			scalars = scalars.dropFirst()
			dropped += 1
		}

		return scalars
	}

	private func controlCharacter(at index: Int, in string: String) -> unichar {
		(string as NSString).character(at: index)
	}
}
