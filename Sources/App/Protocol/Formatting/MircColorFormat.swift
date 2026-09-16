/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions

// AppKit: IRC formatting is applied to attributed strings as fonts and colours.
import AppKit
import Foundation

enum TextFormatterEffectType: Int, Sendable {
	case none
	case bold
	case italic
	case monospace
	case strikethrough
	case underline
	case foregroundColor
	case backgroundColor
	case spoiler
}

nonisolated struct TextFormatterAttributeName: RawRepresentable, Hashable, Sendable { // nonisolated: value
	let rawValue: String

	static let boldAttributeName = Self(rawValue: "IRCTextFormatterBoldAttributeName")
	static let italicAttributeName = Self(rawValue: "IRCTextFormatterItalicAttributeName")
	static let monospaceAttributeName = Self(rawValue: "IRCTextFormatterMonospaceAttributeName")
	static let strikethroughAttributeName = Self(rawValue: "IRCTextFormatterStrikethroughAttributeName")
	static let underlineAttributeName = Self(rawValue: "IRCTextFormatterUnderlineAttributeName")
	static let foregroundColorAttributeName = Self(rawValue: "IRCTextFormatterForegroundColorAttributeName")
	static let backgroundColorAttributeName = Self(rawValue: "IRCTextFormatterBackgroundColorAttributeName")
	static let spoilerAttributeName = Self(rawValue: "IRCTextFormatterSpoilerAttributeName")
}

nonisolated enum TextFormatterControlCharacter { // nonisolated: value
	static let colorDigit = 0x03
	static let colorHex = 0x04
	static let bold = 0x02
	static let italic = 0x1D
	static let legacyItalic = 0x16
	static let monospace = 0x11
	static let strikethrough = 0x1E
	static let underline = 0x1F
	static let terminator = 0x0F
}

nonisolated enum TextFormatterColor { // nonisolated: value
	static let maximumPaletteIndex = 98
}

private let truncationPRIVMSGCommandConstant = 9
private let truncationACTIONCommandConstant = 17
private let truncationNOTICECommandConstant = 8
private let truncationHostmaskConstant = 60
private let truncationWrapMaxDistance = 25

/// U+200D. A composed character sequence stops at one, so a family or a
/// profession emoji is several sequences that must not be told apart.
private let zeroWidthJoiner: unichar = 0x200D

/** The smallest run at `location` that a line break must not fall inside.

 `rangeOfComposedCharacterSequence(at:)` alone is not that run. It stops at a
 zero-width joiner, so wrapping a line between two of its sequences turned one
 emoji into two or three unrelated ones; and it knows nothing about mIRC codes,
 so a `\u{3}` the person pasted could go out on one line with its digits on the
 next, where they read as text. */
private func unbreakableUnitRange(in string: NSString, at location: Int) -> NSRange {
	let length = string.length
	let character = string.character(at: location)

	if character == UniChar(TextFormatterControlCharacter.colorDigit) ||
		character == UniChar(TextFormatterControlCharacter.colorHex)
	{
		let consumed = string.colorComponents(
			ofCharacter: character,
			startingAt: UInt(location)
		).charactersConsumed

		return NSRange(location: location, length: min(max(consumed, 1), length - location))
	}

	let range = string.rangeOfComposedCharacterSequence(at: location)
	var end = range.location + range.length

	while end < length, string.character(at: end) == zeroWidthJoiner {
		end += 1

		guard end < length else {
			break
		}

		let joined = string.rangeOfComposedCharacterSequence(at: end)
		end = joined.location + joined.length
	}

	return NSRange(location: range.location, length: end - range.location)
}

private func appendControlCharacter(_ character: unichar, to string: inout String) {
	guard let scalar = Unicode.Scalar(character) else {
		return
	}

	string.unicodeScalars.append(scalar)
}

func formatterKey(_ name: TextFormatterAttributeName) -> NSAttributedString.Key {
	NSAttributedString.Key(name.rawValue)
}

/** Whether a formatting flag is set on an attribute run.

 An attribute set by this application is a `Bool`; one that came back out of an
 archive or a pasteboard is the `NSNumber` the archive wrote, so both read as
 the flag they stand for. */
private func formatterFlag(
	_ name: TextFormatterAttributeName,
	in attributes: [NSAttributedString.Key: Any]
) -> Bool {
	switch attributes[formatterKey(name)] {
	case let value as Bool: value
	case let value as NSNumber: value.boolValue
	default: false
	}
}

private func formatterColorIsValid(_ value: Any?) -> Bool {
	if let colorCode = (value as? NSNumber)?.intValue {
		return (0 ... TextFormatterColor.maximumPaletteIndex).contains(colorCode)
	}
	return value is NSColor
}

private func formatterEffectIsSet(
	_ effect: TextFormatterEffectType,
	in attributes: [NSAttributedString.Key: Any]
) -> Bool {
	switch effect {
	case .none:
		false
	case .bold:
		formatterFlag(.boldAttributeName, in: attributes)
	case .italic:
		formatterFlag(.italicAttributeName, in: attributes)
	case .monospace:
		formatterFlag(.monospaceAttributeName, in: attributes)
	case .strikethrough:
		formatterFlag(.strikethroughAttributeName, in: attributes)
	case .underline:
		formatterFlag(.underlineAttributeName, in: attributes)
	case .foregroundColor:
		formatterColorIsValid(attributes[formatterKey(.foregroundColorAttributeName)])
	case .backgroundColor:
		formatterColorIsValid(attributes[formatterKey(.backgroundColorAttributeName)])
	case .spoiler:
		formatterFlag(.spoilerAttributeName, in: attributes)
	}
}

func monospaceFontMatching(_ baseFont: NSFont?) -> NSFont {
	let pointSize = baseFont?.pointSize ?? 0
	let monospaceFont = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
	let traits = (baseFont?.fontDescriptor.symbolicTraits ?? [])
		.intersection([.bold, .italic])

	guard !traits.isEmpty else {
		return monospaceFont
	}

	let descriptor = monospaceFont.fontDescriptor.withSymbolicTraits(traits)

	return NSFont(descriptor: descriptor, size: pointSize) ?? monospaceFont
}

/// One formatting run as it goes out on the wire: the control character it is
/// written with, the value that follows it, and how many bytes the pair costs.
struct TextFormatterEffect {
	let type: TextFormatterEffectType
	let value: String?
	let controlCharacter: unichar
	let length: UInt

	init?(effect type: TextFormatterEffectType, withValue value: Any? = nil) {
		var controlCharacter: unichar = 0
		var valueLength: UInt = 0
		var valueOut: String?

		switch type {
		case .none:
			break
		case .bold:
			controlCharacter = unichar(TextFormatterControlCharacter.bold)
			valueLength = 2
		case .italic:
			controlCharacter = unichar(TextFormatterControlCharacter.italic)
			valueLength = 2
		case .monospace:
			controlCharacter = unichar(TextFormatterControlCharacter.monospace)
			valueLength = 2
		case .strikethrough:
			controlCharacter = unichar(TextFormatterControlCharacter.strikethrough)
			valueLength = 2
		case .underline:
			controlCharacter = unichar(TextFormatterControlCharacter.underline)
			valueLength = 2
		case .foregroundColor, .backgroundColor:
			if let color = value as? NSColor {
				controlCharacter = unichar(TextFormatterControlCharacter.colorHex)
				valueOut = String((color.hexadecimalString as NSString).substring(from: 1))
			} else if let number = value as? NSNumber {
				controlCharacter = unichar(TextFormatterControlCharacter.colorDigit)
				valueOut = number.textualIntegerStringValueWithLeadingZero
			}

			guard let resolvedValue = valueOut else {
				return nil
			}

			if type == .foregroundColor {
				valueLength = UInt(resolvedValue.utf8.count) + 2
			} else {
				valueLength = UInt(resolvedValue.utf8.count) + 1
			}
		default:
			return nil
		}

		self.type = type
		self.controlCharacter = controlCharacter
		self.value = valueOut
		length = valueLength
	}

	func appendToStart(of string: inout String) {
		if type == .backgroundColor {
			string += ",\(value ?? "")"

			return
		}

		appendControlCharacter(controlCharacter, to: &string)

		if let value {
			string += value
		}
	}

	func appendToEnd(of string: inout String) {
		if type == .backgroundColor {
			return
		}

		appendControlCharacter(controlCharacter, to: &string)
	}
}

final class TextFormatterEffects {
	private(set) var effects: [TextFormatterEffect] = []
	private(set) var maximumLength: UInt = 0

	init(attributes: [NSAttributedString.Key: Any]) {
		setup(with: attributes)
	}

	private func setup(with attributes: [NSAttributedString.Key: Any]) {
		var maximumLength: UInt = 0
		var effects: [TextFormatterEffect] = []
		effects.reserveCapacity(7)

		let foregroundColor = TextFormatterEffect(
			effect: .foregroundColor,
			withValue: attributes[formatterKey(.foregroundColorAttributeName)]
		)
		let backgroundColor = TextFormatterEffect(
			effect: .backgroundColor,
			withValue: attributes[formatterKey(.backgroundColorAttributeName)]
		)

		if let foregroundColor {
			effects.append(foregroundColor)
			maximumLength += foregroundColor.length

			/* Background must follow foreground, and both values must use the
			 same control character (digit vs hex). */
			if let backgroundColor, foregroundColor.controlCharacter == backgroundColor.controlCharacter {
				effects.append(backgroundColor)
				maximumLength += backgroundColor.length
			}
		}

		func appendBooleanEffect(_ type: TextFormatterEffectType, key: TextFormatterAttributeName) {
			guard formatterFlag(key, in: attributes), let effect = TextFormatterEffect(effect: type) else {
				return
			}

			effects.append(effect)
			maximumLength += effect.length
		}

		appendBooleanEffect(.bold, key: TextFormatterAttributeName.boldAttributeName)
		appendBooleanEffect(.italic, key: TextFormatterAttributeName.italicAttributeName)
		appendBooleanEffect(.monospace, key: TextFormatterAttributeName.monospaceAttributeName)
		appendBooleanEffect(.strikethrough, key: TextFormatterAttributeName.strikethroughAttributeName)
		appendBooleanEffect(.underline, key: TextFormatterAttributeName.underlineAttributeName)

		self.effects = effects
		self.maximumLength = maximumLength
	}

	func appendToStart(of string: inout String) {
		for effect in effects {
			effect.appendToStart(of: &string)
		}
	}

	func appendToEnd(of string: inout String) {
		for effect in effects.reversed() {
			effect.appendToEnd(of: &string)
		}
	}
}

/// Byte count of `string` on the wire. The 512-byte IRC line limit is a byte
/// budget, so UTF-16 code units must not be counted against it.
private func wireByteCount(_ string: String, encoding: UInt) -> Int {
	let count = (string as NSString).lengthOfBytes(using: encoding)

	return count > 0 ? count : string.utf8.count
}

extension LineBudget {
	/** The budget for one line of `lineType` addressed to `channelName`.

	 The framing charged up front is what the *server* will prepend when it
	 relays the line: `:hostmask COMMAND target :`, plus the CR LF. The
	 hostmask is only known once the server has told us, so a constant stands
	 in until it has. */
	@MainActor
	static func forMessage(
		toChannel channelName: String,
		on client: Client,
		lineType: LogLineType,
		encoding: UInt
	) -> LineBudget {
		var overhead = 1

		if let userHostmask = client.userHostmask {
			overhead += wireByteCount(userHostmask, encoding: encoding)
		} else {
			overhead += truncationHostmaskConstant
		}

		switch lineType {
		case .privateMessage, .privateMessageNoHighlight:
			overhead += truncationPRIVMSGCommandConstant
		case .action, .actionNoHighlight:
			overhead += truncationACTIONCommandConstant
		case .notice:
			overhead += truncationNOTICECommandConstant
		default:
			preconditionFailure("Line type not supported")
		}

		overhead += wireByteCount(channelName, encoding: encoding)
		overhead += 2
		overhead += 2

		var maximum = 510
		let serverLineLength = Int(client.supportInfo.maximumLineLength)

		if serverLineLength > (overhead + 2) {
			maximum = serverLineLength - 2
		}

		return LineBudget(overhead: overhead, maximum: maximum)
	}
}

/** One message's text, consumed one wire line at a time.

 A message longer than the line budget goes out as several lines, and each of
 them is cut from the front of what is left. The cursor is a value that hands
 back the remainder, so no mutable AppKit object sits in the send path. */
@MainActor
struct LineCursor {
	private var remaining: NSAttributedString

	init(_ text: NSAttributedString) {
		remaining = text
	}

	/// How much of the text is still to be sent. Each line consumes a prefix,
	/// so this only ever falls, and reaching zero is what ends the message.
	var length: Int {
		remaining.length
	}

	var isEmpty: Bool {
		length == 0
	}

	/** The next wire line, or `nil` once there is nothing left to send.

	 `nil` also answers the case a caller would otherwise have to guard by hand:
	 formatting that consumed nothing loops forever, so a pass that makes no
	 progress ends the message instead. */
	mutating func nextLine(
		forChannel channelName: String,
		on client: Client,
		with lineType: LogLineType
	) -> String? {
		guard remaining.length > 0 else {
			return nil
		}

		var consumed = NSRange()
		let line = remaining.stringFormatted(
			forChannel: channelName,
			on: client,
			with: lineType,
			effectiveRange: &consumed
		)

		let end = consumed.location + consumed.length

		guard consumed.location == 0, end > 0, end <= remaining.length else {
			return nil
		}

		remaining = remaining.attributedSubstring(
			from: NSRange(location: end, length: remaining.length - end)
		)

		return line
	}
}

extension NSAttributedString {
	func stringFormatted(
		forChannel channelName: String,
		on client: Client,
		with lineType: LogLineType,
		effectiveRange: NSRangePointer?
	) -> String {
		let encoding = client.effectivePrimaryEncoding
		var budget = LineBudget.forMessage(
			toChannel: channelName,
			on: client,
			lineType: lineType,
			encoding: encoding.rawValue
		)

		let string = string as NSString
		var result = ""

		var deletionLength: UInt = 0
		var consumedAnyCharacter = false
		var limitRange = NSRange(location: 0, length: string.length)

		while limitRange.length > 0 {
			var breakLoopAfterAppend = false
			var segmentRange = NSRange()

			let attributes = attributes(
				at: limitRange.location,
				longestEffectiveRange: &segmentRange,
				in: limitRange
			)
			let formatters = TextFormatterEffects(attributes: attributes)
			let formattersLength = formatters.maximumLength

			if segmentRange.location > 0, budget.fits(Int(formattersLength) + 2) == false {
				break
			}

			budget.charge(Int(formattersLength))
			formatters.appendToStart(of: &result)

			/* Where this segment's own characters start in `result`.

			 `deletionLength` counts UTF-16 units of the plain source; `result`
			 also holds the control codes the formatters injected, so the two
			 run at different offsets. Everything appended from here to the end
			 of the segment is copied from the source verbatim, which is what
			 lets a wrap inside this window be measured in either. */
			let segmentResultLocation = result.utf16.count

			var i = 0

			while i < segmentRange.length {
				let characterIndex = segmentRange.location + i
				let characterRange = unbreakableUnitRange(in: string, at: characterIndex)
				let character = string.substring(with: characterRange)
				var characterSize = (character as NSString).lengthOfBytes(using: encoding.rawValue)

				if characterSize == 0 {
					characterSize = characterRange.length
				}

				budget.charge(characterSize)

				if budget.isOverBudget {
					if consumedAnyCharacter {
						/* The floor is in `result`'s coordinates, so the wrap
						 cannot back past this segment's first character. Held
						 there, the units it removed from `result` are exactly
						 the source units it gave back — and `deletionLength` is
						 the ceiling on how many it may remove, because a unit
						 taken off `result` that is not given back here is a
						 character the caller believes it sent and never will.
						 The wrap declines rather than truncate past it. */
						let indexDifference = result.wrapIRCTextFormatterResult(
							with: UInt(segmentResultLocation),
							maxDistance: UInt(truncationWrapMaxDistance),
							maximumGiveBack: deletionLength
						)

						if indexDifference != UInt(bitPattern: NSNotFound) {
							deletionLength -= indexDifference
						}
					} else {
						// A server-assigned hostmask plus a long channel name
						// can push the minimum length past the maximum. Consume
						// the character anyway: the callers loop until the
						// string is empty, and consuming nothing never ends.
						deletionLength += UInt(characterRange.length)
						result.append(character)
					}

					breakLoopAfterAppend = true

					break
				}

				consumedAnyCharacter = true
				deletionLength += UInt(characterRange.length)
				i += characterRange.length
				result.append(character)
			}

			formatters.appendToEnd(of: &result)

			if breakLoopAfterAppend {
				break
			}

			let segmentRangeNewLength = string.length - Int(deletionLength)

			if segmentRangeNewLength <= 0 {
				break
			}

			limitRange = NSRange(location: Int(deletionLength), length: segmentRangeNewLength)
		}

		if let effectiveRange {
			effectiveRange.pointee = NSRange(location: 0, length: Int(deletionLength))
		}

		return result
	}

	var stringFormattedForIRC: String {
		let string = string as NSString
		var result = ""
		let fullRange = NSRange(location: 0, length: length)

		enumerateAttributes(in: fullRange, options: []) { attributes, effectiveRange, _ in
			let formatters = TextFormatterEffects(attributes: attributes)

			formatters.appendToStart(of: &result)
			result.append(string.substring(with: effectiveRange))
			formatters.appendToEnd(of: &result)
		}

		return result
	}

	func ircFormatterAttributeSet(inRange effect: TextFormatterEffectType, range limitRange: NSRange) -> Bool {
		var returnValue = false

		enumerateAttributes(in: limitRange, options: []) { attributes, _, stop in
			if formatterEffectIsSet(effect, in: attributes) {
				returnValue = true
				stop.pointee = true
			}
		}

		return returnValue
	}
}

nonisolated extension String { // nonisolated: pure
	/** Breaks the tail of a formatted line at a space rather than mid-word.

	 Truncates this string back to the last space within `maxDistance` UTF-16
	 units of its end and answers how many units went; `NSNotFound` when there is
	 no space to break at, in which case the string is left alone.

	 `maximumGiveBack` is how many units the caller can hand back to the queue.
	 Truncating more than that drops text: the characters leave the line being
	 sent while the caller still counts them as consumed, so nothing ever sends
	 them. Past that ceiling the wrap declines and the line goes out unwrapped,
	 which re-queues the tail instead of losing it. */
	mutating func wrapIRCTextFormatterResult(
		with minimumIndex: UInt,
		maxDistance: UInt,
		maximumGiveBack: UInt = .max
	) -> UInt {
		let text = self as NSString
		let selfLength = text.length
		let distance = Int(clamping: maxDistance)

		// The window is the tail of the string. Computing its start in
		// unsigned arithmetic underflowed whenever the result was shorter
		// than the distance, producing a large-negative NSRange location and
		// an uncatchable NSRangeException.
		guard distance > 0, selfLength > 0 else {
			return UInt(bitPattern: NSNotFound)
		}

		let searchStart = max(0, selfLength - 1 - distance)
		let searchLength = min(distance, selfLength - searchStart)

		guard searchLength > 0 else {
			return UInt(bitPattern: NSNotFound)
		}

		let searchRange = NSRange(location: searchStart, length: searchLength)
		let spaceRange = text.rangeOfCharacter(
			from: .whitespaces,
			options: .backwards,
			range: searchRange
		)

		if spaceRange.location == NSNotFound || spaceRange.location < Int(minimumIndex) {
			return UInt(bitPattern: NSNotFound)
		}

		let indexDifference = selfLength - spaceRange.location

		guard UInt(indexDifference) <= maximumGiveBack else {
			return UInt(bitPattern: NSNotFound)
		}

		self = text.substring(to: spaceRange.location)

		return UInt(indexDifference)
	}
}

// MARK: - Colour control codes

private nonisolated func isBase10Numeric(_ character: unichar) -> Bool { // nonisolated: pure
	character >= 0x30 && character <= 0x39
}

/// The character separating a colour code's foreground from its background.
private nonisolated let comma: unichar = 0x2C // nonisolated: let

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
nonisolated struct MircColorChannels: Sendable, Equatable, Hashable { // nonisolated: value
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
nonisolated enum MircColor: Sendable, Equatable { // nonisolated: value
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
nonisolated enum MircColorSelection: Sendable, Equatable { // nonisolated: value
	/// The code did not name this half.
	case unchanged
	/// The code asked for the view's own colour: mIRC 99, or a bare control
	/// character with no digits behind it.
	case reset
	case color(MircColor)
}

/// What one colour control code says.
nonisolated struct MircColorComponents: Sendable { // nonisolated: value
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

		if character == UniChar(TextFormatterControlCharacter.colorDigit) {
			return paletteColorComponents(startingAt: rangeStart)
		}

		if character == UniChar(TextFormatterControlCharacter.colorHex) {
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

		guard candidate.onlyContainsCharacters(from: .textualHexadecimal),
		      let channels = MircColorChannels(sixDigitHexadecimal: candidate)
		else {
			return nil
		}

		position += 6

		return channels
	}
}
