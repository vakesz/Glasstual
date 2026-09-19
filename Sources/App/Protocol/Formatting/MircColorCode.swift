// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions

// AppKit: a hexadecimal colour code names a colour the renderer stores as an
// `NSColor` attribute.
import AppKit
import Foundation

private nonisolated func isBase10Numeric(_ character: unichar) -> Bool { // nonisolated: pure
	character >= 0x30 && character <= 0x39
}

/// The character separating a colour code's foreground from its background.
private nonisolated let comma: unichar = 0x2C

private nonisolated func paletteSelection(forIndex index: Int) -> MircColorSelection { // nonisolated: pure
	/* mIRC 99 is not a palette entry, it is the absence of one. */
	guard index <= TextFormatterColor.maximumPaletteIndex else {
		return .reset
	}

	return .color(.palette(index))
}

/// The channels a hexadecimal colour control code names, each in `0...1`.
///
/// A value rather than an `NSColor`: the enum below is a `Sendable` value that
/// crosses isolation domains, and an `NSColor` payload made it hold a class.
/// The colour is built where it is drawn.
nonisolated struct MircColorChannels: Sendable, Equatable, Hashable {
	let red: Double
	let green: Double
	let blue: Double
	let alpha: Double

	init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
		self.red = red
		self.green = green
		self.blue = blue
		self.alpha = alpha
	}

	/// Six hexadecimal digits, `RRGGBB`, the only form a `\u{4}` code carries.
	init?(sixDigitHexadecimal value: String) {
		guard value.count == 6, let packed = UInt32(value, radix: 16) else {
			return nil
		}

		self.init(
			red: Double((packed >> 16) & 0xFF) / 0xFF,
			green: Double((packed >> 8) & 0xFF) / 0xFF,
			blue: Double(packed & 0xFF) / 0xFF
		)
	}

	var color: NSColor {
		NSColor(
			deviceRed: CGFloat(red),
			green: CGFloat(green),
			blue: CGFloat(blue),
			alpha: CGFloat(alpha)
		)
	}
}

/// A colour named by an IRC colour control code.
nonisolated enum MircColor: Sendable, Equatable {
	/// An mIRC palette index.
	case palette(Int)
	/// A literal colour from a hexadecimal control code.
	case rgb(MircColorChannels)

	/// The value the renderer stores as a text attribute.
	var attributeValue: AnyObject {
		switch self {
		case let .palette(index): NSNumber(value: index)
		case let .rgb(channels): channels.color
		}
	}
}

/** What one half of a colour control code said about that half.

 The three answers are not two: a code that names no background at all leaves
 whatever background is in force, and one that names 99 takes it away. Reading
 both as "no colour" is why `\u{3}04,99` painted red text on the background the
 previous code had set — 99 fell outside the palette and was dropped, so
 nothing cleared it. */
nonisolated enum MircColorSelection: Sendable, Equatable {
	/// The code did not name this half.
	case unchanged
	/// The code asked for the view's own colour: mIRC 99, or a bare control
	/// character with no digits behind it.
	case reset
	case color(MircColor)
}

/// What one colour control code says.
nonisolated struct MircColorComponents: Sendable {
	let foreground: MircColorSelection
	let background: MircColorSelection
	/// How many characters of the control code were read.
	let charactersConsumed: Int

	static let unread = MircColorComponents(foreground: .unchanged, background: .unchanged, charactersConsumed: 0)
}

/** Reading a colour control code out of a line.

 The scan is indexed in UTF-16 units because a control code is ASCII and the
 renderer walks the same `NSString` ranges the attributed string uses. */
nonisolated extension NSString { // nonisolated: pure
	/// The colours a colour control code names, and how many characters of the
	/// code were read.
	///
	/// A digit code names palette indices and a hex code names literal colours,
	/// and the result says which kind was read.
	func colorComponents(ofCharacter character: unichar, startingAt rangeStart: UInt) -> MircColorComponents {
		/* A start past the end is a question about a range this string does not
		 have, and the answer is "nothing was read". It used to be a
		 `precondition` on a public entry point, which turned a caller's
		 arithmetic slip into a crash. */
		guard rangeStart < UInt(length) else {
			return .unread
		}

		let rangeStart = Int(rangeStart)

		if character == TextFormatterControlCharacter.colorDigit {
			return paletteColorComponents(startingAt: rangeStart)
		}

		if character == TextFormatterControlCharacter.colorHex {
			return hexadecimalColorComponents(startingAt: rangeStart)
		}

		return .unread
	}

	private func paletteColorComponents(startingAt rangeStart: Int) -> MircColorComponents {
		var position = rangeStart + 1

		guard let foreground = paletteIndex(at: &position) else {
			/* A control character with no digits behind it is mIRC's "colour
			 off": it clears both halves. */
			return MircColorComponents(
				foreground: .reset,
				background: .reset,
				charactersConsumed: position - rangeStart
			)
		}

		var background = MircColorSelection.unchanged
		var afterSeparator = position + 1

		if position < length, character(at: position) == comma, let index = paletteIndex(at: &afterSeparator) {
			position = afterSeparator
			background = paletteSelection(forIndex: index)
		}

		return MircColorComponents(
			foreground: paletteSelection(forIndex: foreground),
			background: background,
			charactersConsumed: position - rangeStart
		)
	}

	private func hexadecimalColorComponents(startingAt rangeStart: Int) -> MircColorComponents {
		var position = rangeStart + 1

		guard let foreground = hexadecimalChannels(at: &position) else {
			return MircColorComponents(
				foreground: .reset,
				background: .reset,
				charactersConsumed: position - rangeStart
			)
		}

		var background = MircColorSelection.unchanged
		var afterSeparator = position + 1

		if position < length, character(at: position) == comma,
		   let channels = hexadecimalChannels(at: &afterSeparator)
		{
			position = afterSeparator
			background = .color(.rgb(channels))
		}

		return MircColorComponents(
			foreground: .color(.rgb(foreground)),
			background: background,
			charactersConsumed: position - rangeStart
		)
	}

	/// One or two decimal digits at `position`, advancing past what it read.
	private func paletteIndex(at position: inout Int) -> Int? {
		guard position < length, isBase10Numeric(character(at: position)) else {
			return nil
		}

		var value = Int(character(at: position) - 0x30)
		position += 1

		if position < length, isBase10Numeric(character(at: position)) {
			value = value * 10 + Int(character(at: position) - 0x30)
			position += 1
		}

		return value
	}

	/// Six hexadecimal digits at `position`, advancing past them.
	private func hexadecimalChannels(at position: inout Int) -> MircColorChannels? {
		guard position + 6 <= length else {
			return nil
		}

		let candidate = substring(with: NSRange(location: position, length: 6))

		guard candidate.onlyContainsCharacters(from: .hexadecimalDigits),
		      let channels = MircColorChannels(sixDigitHexadecimal: candidate)
		else {
			return nil
		}

		position += 6

		return channels
	}
}
