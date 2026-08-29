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
import os

@objc
public enum IRCTextFormatterEffectType: Int, Sendable {
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

public nonisolated struct IRCTextFormatterAttributeName: RawRepresentable, Hashable, Sendable { // nonisolated: value
	public let rawValue: String

	public init(rawValue: String) {
		self.rawValue = rawValue
	}

	public static let boldAttributeName = Self(rawValue: "IRCTextFormatterBoldAttributeName")
	public static let italicAttributeName = Self(rawValue: "IRCTextFormatterItalicAttributeName")
	public static let monospaceAttributeName = Self(rawValue: "IRCTextFormatterMonospaceAttributeName")
	public static let strikethroughAttributeName = Self(rawValue: "IRCTextFormatterStrikethroughAttributeName")
	public static let underlineAttributeName = Self(rawValue: "IRCTextFormatterUnderlineAttributeName")
	public static let foregroundColorAttributeName = Self(rawValue: "IRCTextFormatterForegroundColorAttributeName")
	public static let backgroundColorAttributeName = Self(rawValue: "IRCTextFormatterBackgroundColorAttributeName")
	public static let spoilerAttributeName = Self(rawValue: "IRCTextFormatterSpoilerAttributeName")
}

public nonisolated enum IRCTextFormatterControlCharacter { // nonisolated: value
	public static let colorDigit = 0x03
	public static let colorHex = 0x04
	public static let bold = 0x02
	public static let italic = 0x1D
	public static let legacyItalic = 0x16
	public static let monospace = 0x11
	public static let strikethrough = 0x1E
	public static let underline = 0x1F
	public static let terminator = 0x0F
}

public nonisolated enum IRCTextFormatterColor { // nonisolated: value
	public static let maximumPaletteIndex = 98
}

private let truncationPRIVMSGCommandConstant = 9
private let truncationACTIONCommandConstant = 17
private let truncationNOTICECommandConstant = 8
private let truncationHostmaskConstant = 60
private let truncationWrapMaxDistance = 25
private let colorHighestDigit = 98

private let colorFormatLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCColorFormat"
)

private func appendControlCharacter(_ character: unichar, to string: NSMutableString) {
	string.appendFormat("%C", character)
}

private func stringKeyedAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [String: Any] {
	Dictionary(uniqueKeysWithValues: attributes.map { ($0.key.rawValue, $0.value) })
}

private func formatterKey(_ name: IRCTextFormatterAttributeName) -> NSAttributedString.Key {
	NSAttributedString.Key(name.rawValue)
}

private func attributeName(_ name: IRCTextFormatterAttributeName) -> String {
	name.rawValue
}

private func formatterColorIsValid(_ value: Any?) -> Bool {
	if let colorCode = (value as? NSNumber)?.intValue {
		return (0 ... IRCTextFormatterColor.maximumPaletteIndex).contains(colorCode)
	}
	return value is NSColor
}

private func formatterEffectIsSet(
	_ effect: IRCTextFormatterEffectType,
	in attributes: NSDictionary
) -> Bool {
	switch effect {
	case .none:
		false
	case .bold:
		attributes.ce_bool(forKey: attributeName(.boldAttributeName))
	case .italic:
		attributes.ce_bool(forKey: attributeName(.italicAttributeName))
	case .monospace:
		attributes.ce_bool(forKey: attributeName(.monospaceAttributeName))
	case .strikethrough:
		attributes.ce_bool(forKey: attributeName(.strikethroughAttributeName))
	case .underline:
		attributes.ce_bool(forKey: attributeName(.underlineAttributeName))
	case .foregroundColor:
		formatterColorIsValid(attributes[attributeName(.foregroundColorAttributeName)])
	case .backgroundColor:
		formatterColorIsValid(attributes[attributeName(.backgroundColorAttributeName)])
	case .spoiler:
		attributes.ce_bool(forKey: attributeName(.spoilerAttributeName))
	}
}

private func monospaceFontMatching(_ baseFont: NSFont?) -> NSFont {
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

@objc(IRCTextFormatterEffect)
public final class TextFormatterEffect: NSObject {
	@objc public private(set) var type: IRCTextFormatterEffectType = .none
	@objc public private(set) var value: String?
	@objc public private(set) var controlCharacter: unichar = 0
	@objc public private(set) var length: UInt = 0

	override public convenience init() {
		self.init(effect: .none, withValue: nil)!
	}

	@objc(effectWithType:)
	public static func effect(with type: IRCTextFormatterEffectType) -> TextFormatterEffect? {
		self.init(effect: type, withValue: nil)
	}

	@objc(effectWithType:withValue:)
	public static func effect(with type: IRCTextFormatterEffectType, withValue value: Any?) -> TextFormatterEffect? {
		self.init(effect: type, withValue: value)
	}

	@objc(initWithEffect:)
	public convenience init?(effect type: IRCTextFormatterEffectType) {
		self.init(effect: type, withValue: nil)
	}

	@objc(initWithEffect:withValue:)
	public init?(effect type: IRCTextFormatterEffectType, withValue value: Any?) {
		super.init()

		guard setup(effect: type, withValue: value) else {
			return nil
		}
	}

	private func setup(effect type: IRCTextFormatterEffectType, withValue value: Any?) -> Bool {
		var controlCharacter: unichar = 0
		var valueLength: UInt = 0
		var valueOut: String?

		switch type {
		case .none:
			break
		case .bold:
			controlCharacter = unichar(IRCTextFormatterControlCharacter.bold)
			valueLength = 2
		case .italic:
			controlCharacter = unichar(IRCTextFormatterControlCharacter.italic)
			valueLength = 2
		case .monospace:
			controlCharacter = unichar(IRCTextFormatterControlCharacter.monospace)
			valueLength = 2
		case .strikethrough:
			controlCharacter = unichar(IRCTextFormatterControlCharacter.strikethrough)
			valueLength = 2
		case .underline:
			controlCharacter = unichar(IRCTextFormatterControlCharacter.underline)
			valueLength = 2
		case .foregroundColor, .backgroundColor:
			if let color = value as? NSColor {
				controlCharacter = unichar(IRCTextFormatterControlCharacter.colorHex)
				valueOut = String((color.textualHexadecimalValue as NSString).substring(from: 1))
			} else if let number = value as? NSNumber {
				controlCharacter = unichar(IRCTextFormatterControlCharacter.colorDigit)
				valueOut = number.textualIntegerStringValueWithLeadingZero
			}

			guard let resolvedValue = valueOut else {
				return false
			}

			if type == .foregroundColor {
				valueLength = UInt(resolvedValue.utf8.count) + 2
			} else {
				valueLength = UInt(resolvedValue.utf8.count) + 1
			}
		default:
			return false
		}

		self.type = type
		self.controlCharacter = controlCharacter
		self.value = valueOut
		length = valueLength

		return true
	}

	@objc(appendToStartOf:)
	public func appendToStart(of string: NSMutableString) {
		if type == .backgroundColor {
			string.appendFormat(",%@", value ?? "")

			return
		}

		if let value {
			appendControlCharacter(controlCharacter, to: string)
			string.append(value)
		} else {
			appendControlCharacter(controlCharacter, to: string)
		}
	}

	@objc(appendToEndOf:)
	public func appendToEnd(of string: NSMutableString) {
		if type == .backgroundColor {
			return
		}

		appendControlCharacter(controlCharacter, to: string)
	}
}

@objc(IRCTextFormatterEffects)
public final class TextFormatterEffects: NSObject {
	@objc public private(set) var effects: [TextFormatterEffect] = []
	@objc public private(set) var maximumLength: UInt = 0

	override public convenience init() {
		self.init(attributes: [:])
	}

	@objc(effectsInAttributes:)
	public static func effects(in attributes: [String: Any]) -> TextFormatterEffects {
		TextFormatterEffects(attributes: attributes)
	}

	@objc(initWithAttributes:)
	public init(attributes: [String: Any]) {
		super.init()

		setup(with: attributes)
	}

	private func setup(with attributes: [String: Any]) {
		var maximumLength: UInt = 0
		var effects: [TextFormatterEffect] = []
		effects.reserveCapacity(7)

		let foregroundColor = TextFormatterEffect(
			effect: .foregroundColor,
			withValue: attributes[attributeName(IRCTextFormatterAttributeName.foregroundColorAttributeName)]
		)
		let backgroundColor = TextFormatterEffect(
			effect: .backgroundColor,
			withValue: attributes[attributeName(IRCTextFormatterAttributeName.backgroundColorAttributeName)]
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

		let dictionary = attributes as NSDictionary

		func appendBooleanEffect(_ type: IRCTextFormatterEffectType, key: IRCTextFormatterAttributeName) {
			guard dictionary.ce_bool(forKey: attributeName(key)), let effect = TextFormatterEffect(effect: type) else {
				return
			}

			effects.append(effect)
			maximumLength += effect.length
		}

		appendBooleanEffect(.bold, key: IRCTextFormatterAttributeName.boldAttributeName)
		appendBooleanEffect(.italic, key: IRCTextFormatterAttributeName.italicAttributeName)
		appendBooleanEffect(.monospace, key: IRCTextFormatterAttributeName.monospaceAttributeName)
		appendBooleanEffect(.strikethrough, key: IRCTextFormatterAttributeName.strikethroughAttributeName)
		appendBooleanEffect(.underline, key: IRCTextFormatterAttributeName.underlineAttributeName)

		self.effects = effects
		self.maximumLength = maximumLength
	}

	@objc(appendToStartOf:)
	public func appendToStart(of string: NSMutableString) {
		for effect in effects {
			effect.appendToStart(of: string)
		}
	}

	@objc(appendToEndOf:)
	public func appendToEnd(of string: NSMutableString) {
		for effect in effects.reversed() {
			effect.appendToEnd(of: string)
		}
	}
}

/// Byte count of `string` on the wire. The 512-byte IRC line limit is a byte
/// budget, so UTF-16 code units must not be counted against it.
private func wireByteCount(_ string: String, encoding: UInt) -> Int {
	let count = (string as NSString).lengthOfBytes(using: encoding)

	return count > 0 ? count : string.utf8.count
}

extension IRCLineBudget {
	/** The budget for one line of `lineType` addressed to `channelName`.

	 The framing charged up front is what the *server* will prepend when it
	 relays the line: `:hostmask COMMAND target :`, plus the CR LF. The
	 hostmask is only known once the server has told us, so a constant stands
	 in until it has. */
	@MainActor
	static func forMessage(
		toChannel channelName: String,
		on client: IRCClient,
		lineType: TVCLogLineType,
		encoding: UInt
	) -> IRCLineBudget {
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

		return IRCLineBudget(overhead: overhead, maximum: maximum)
	}
}

public extension NSAttributedString {
	@objc(stringFormattedForChannel:onClient:withLineType:effectiveRange:)
	func stringFormatted(
		forChannel channelName: String,
		on client: IRCClient,
		with lineType: TVCLogLineType,
		effectiveRange: NSRangePointer?
	) -> String {
		let encoding = client.effectivePrimaryEncoding
		var budget = IRCLineBudget.forMessage(
			toChannel: channelName,
			on: client,
			lineType: lineType,
			encoding: encoding.rawValue
		)

		let string = string as NSString
		let result = NSMutableString()

		var deletionLength: UInt = 0
		var consumedAnyCharacter = false
		var limitRange = NSRange(location: 0, length: string.length)

		while limitRange.length > 0 {
			var breakLoopAfterAppend = false
			var segmentRange = NSRange()

			let attributes = stringKeyedAttributes(
				attributes(at: limitRange.location, longestEffectiveRange: &segmentRange, in: limitRange)
			)
			let formatters = TextFormatterEffects.effects(in: attributes)
			let formattersLength = formatters.maximumLength

			if segmentRange.location > 0, budget.fits(Int(formattersLength) + 2) == false {
				break
			}

			budget.charge(Int(formattersLength))
			formatters.appendToStart(of: result)

			var i = 0

			while i < segmentRange.length {
				let characterIndex = segmentRange.location + i
				let characterRange = string.rangeOfComposedCharacterSequence(at: characterIndex)
				let character = string.substring(with: characterRange)
				var characterSize = (character as NSString).lengthOfBytes(using: encoding.rawValue)

				if characterSize == 0 {
					characterSize = characterRange.length
				}

				budget.charge(characterSize)

				if budget.isOverBudget {
					if consumedAnyCharacter {
						let indexDifference = result.wrapIRCTextFormatterResult(
							with: UInt(segmentRange.location),
							maxDistance: UInt(truncationWrapMaxDistance)
						)

						if indexDifference != UInt(bitPattern: NSNotFound), deletionLength >= indexDifference {
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

			formatters.appendToEnd(of: result)

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

		colorFormatLogger.debug(
			"""
			Minimum length: \(budget.overhead, privacy: .public); \
			Final length: \(budget.used, privacy: .public); \
			Difference: \(budget.maximum - budget.used, privacy: .public);
			"""
		)

		return result as String
	}

	@objc var stringFormattedForIRC: String {
		let string = string as NSString
		let result = NSMutableString()
		let fullRange = NSRange(location: 0, length: length)

		enumerateAttributes(in: fullRange, options: []) { attributes, effectiveRange, _ in
			let formatters = TextFormatterEffects.effects(in: stringKeyedAttributes(attributes))

			formatters.appendToStart(of: result)
			result.append(string.substring(with: effectiveRange))
			formatters.appendToEnd(of: result)
		}

		return result as String
	}

	@objc(IRCFormatterAttributeSetInRange:range:)
	func ircFormatterAttributeSet(inRange effect: IRCTextFormatterEffectType, range limitRange: NSRange) -> Bool {
		var returnValue = false

		enumerateAttributes(in: limitRange, options: []) { attributes, _, stop in
			let dictionary = stringKeyedAttributes(attributes) as NSDictionary
			if formatterEffectIsSet(effect, in: dictionary) {
				returnValue = true
				stop.pointee = true
			}
		}

		return returnValue
	}
}

public extension NSMutableAttributedString {
	private func addIRCFontTrait(
		_ trait: NSFontTraitMask,
		formatterAttribute: IRCTextFormatterAttributeName,
		baseFont: NSFont?,
		range: NSRange
	) {
		guard let baseFont else {
			return
		}

		let font = if baseFont.textual_fontTraitIsSet(trait) {
			baseFont
		} else {
			NSFontManager.shared.convert(baseFont, toHaveTrait: trait)
		}

		addAttribute(formatterKey(formatterAttribute), value: true, range: range)
		addAttribute(.font, value: font, range: range)
	}

	private func addIRCColor(
		_ value: Any?,
		formatterAttribute: IRCTextFormatterAttributeName,
		appKitAttribute: NSAttributedString.Key,
		range: NSRange
	) {
		if let colorCode = (value as? NSNumber)?.intValue,
		   (0 ... colorHighestDigit).contains(colorCode)
		{
			addAttribute(formatterKey(formatterAttribute), value: colorCode, range: range)
			addAttribute(appKitAttribute, value: TVCLogRenderer.mapColorCode(UInt(colorCode)), range: range)
		} else if let color = value as? NSColor {
			addAttribute(formatterKey(formatterAttribute), value: color, range: range)
			addAttribute(appKitAttribute, value: color, range: range)
		}
	}

	private func applyIRCFormatterAttribute(
		_ effect: IRCTextFormatterEffectType,
		value: Any?,
		attributes: [NSAttributedString.Key: Any],
		range: NSRange
	) {
		let baseFont = attributes[.font] as? NSFont

		switch effect {
		case .none:
			break
		case .bold:
			addIRCFontTrait(
				.boldFontMask,
				formatterAttribute: .boldAttributeName,
				baseFont: baseFont,
				range: range
			)
		case .italic:
			addIRCFontTrait(
				.italicFontMask,
				formatterAttribute: .italicAttributeName,
				baseFont: baseFont,
				range: range
			)
		case .monospace:
			addAttribute(formatterKey(.monospaceAttributeName), value: true, range: range)
			addAttribute(.font, value: monospaceFontMatching(baseFont), range: range)
		case .underline:
			addAttribute(formatterKey(.underlineAttributeName), value: true, range: range)
			addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
		case .strikethrough:
			addAttribute(formatterKey(.strikethroughAttributeName), value: true, range: range)
			addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
		case .foregroundColor:
			addIRCColor(
				value,
				formatterAttribute: .foregroundColorAttributeName,
				appKitAttribute: .foregroundColor,
				range: range
			)
		case .backgroundColor:
			addIRCColor(
				value,
				formatterAttribute: .backgroundColorAttributeName,
				appKitAttribute: .backgroundColor,
				range: range
			)
		case .spoiler:
			if let value {
				addAttribute(formatterKey(.spoilerAttributeName), value: value, range: range)
			}
		@unknown default:
			break
		}
	}

	@objc(stringFormattedForChannel:onClient:withLineType:)
	func stringFormatted(
		forChannel channelName: String,
		on client: IRCClient,
		with lineType: TVCLogLineType
	) -> String {
		var effectiveRange = NSRange()
		let result = stringFormatted(
			forChannel: channelName,
			on: client,
			with: lineType,
			effectiveRange: &effectiveRange
		)

		deleteCharacters(in: effectiveRange)

		return result
	}

	@objc(setIRCFormatterAttribute:value:range:)
	func setIRCFormatterAttribute(
		_ effect: IRCTextFormatterEffectType,
		value: Any?,
		range limitRange: NSRange
	) {
		enumerateAttributes(in: limitRange, options: .reverse) { attributes, effectiveRange, _ in
			applyIRCFormatterAttribute(effect, value: value, attributes: attributes, range: effectiveRange)
		}
	}

	@objc(removeIRCFormatterAttribute:range:)
	func removeIRCFormatterAttribute(_ effect: IRCTextFormatterEffectType, range limitRange: NSRange) {
		enumerateAttributes(in: limitRange, options: .reverse) { attributes, effectiveRange, _ in
			guard var baseFont = attributes[.font] as? NSFont else {
				return
			}

			switch effect {
			case .none:
				break
			case .bold:
				if baseFont.textual_fontTraitIsSet(.boldFontMask) {
					baseFont = NSFontManager.shared.convert(baseFont, toNotHaveTrait: .boldFontMask)

					addAttribute(.font, value: baseFont, range: effectiveRange)
					removeAttribute(
						formatterKey(IRCTextFormatterAttributeName.boldAttributeName), range: effectiveRange
					)
				}
			case .italic:
				if baseFont.textual_fontTraitIsSet(.italicFontMask) {
					baseFont = NSFontManager.shared.convert(baseFont, toNotHaveTrait: .italicFontMask)

					addAttribute(.font, value: baseFont, range: effectiveRange)
					removeAttribute(
						formatterKey(IRCTextFormatterAttributeName.italicAttributeName), range: effectiveRange
					)
				}
			case .monospace:
				removeAttribute(.font, range: effectiveRange)
				removeAttribute(
					formatterKey(IRCTextFormatterAttributeName.monospaceAttributeName), range: effectiveRange
				)
			case .underline:
				removeAttribute(.underlineStyle, range: effectiveRange)
				removeAttribute(
					formatterKey(IRCTextFormatterAttributeName.underlineAttributeName), range: effectiveRange
				)
			case .strikethrough:
				removeAttribute(.strikethroughStyle, range: effectiveRange)
				removeAttribute(
					formatterKey(IRCTextFormatterAttributeName.strikethroughAttributeName), range: effectiveRange
				)
			case .foregroundColor:
				/* Matches the original implementation, which removes the AppKit
				 background color when clearing the IRC foreground formatter. */
				removeAttribute(.backgroundColor, range: effectiveRange)
				removeAttribute(
					formatterKey(IRCTextFormatterAttributeName.foregroundColorAttributeName), range: effectiveRange
				)
			case .backgroundColor:
				removeAttribute(.backgroundColor, range: effectiveRange)
				removeAttribute(
					formatterKey(IRCTextFormatterAttributeName.backgroundColorAttributeName), range: effectiveRange
				)
			case .spoiler:
				removeAttribute(formatterKey(IRCTextFormatterAttributeName.spoilerAttributeName), range: effectiveRange)
			@unknown default:
				break
			}
		}
	}
}

public nonisolated extension NSMutableString { // nonisolated: pure
	@objc(wrapIRCTextFormatterResultWith:maxDistance:)
	func wrapIRCTextFormatterResult(with minimumIndex: UInt, maxDistance: UInt) -> UInt {
		let selfLength = length
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
		let spaceRange = rangeOfCharacter(
			from: .whitespaces,
			options: .backwards,
			range: searchRange
		)

		if spaceRange.location == NSNotFound || spaceRange.location < Int(minimumIndex) {
			return UInt(bitPattern: NSNotFound)
		}

		let indexDifference = selfLength - spaceRange.location

		deleteCharacters(in: NSRange(location: spaceRange.location, length: indexDifference))

		return UInt(indexDifference)
	}
}
