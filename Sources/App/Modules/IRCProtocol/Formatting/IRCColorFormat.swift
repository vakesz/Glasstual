/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import os

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
	public class func effect(with type: IRCTextFormatterEffectType) -> TextFormatterEffect? {
		self.init(effect: type, withValue: nil)
	}

	@objc(effectWithType:withValue:)
	public class func effect(with type: IRCTextFormatterEffectType, withValue value: Any?) -> TextFormatterEffect? {
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
			controlCharacter = unichar(IRCTextFormatterEffectBoldCharacter)
			valueLength = 2
		case .italic:
			controlCharacter = unichar(IRCTextFormatterEffectItalicCharacter)
			valueLength = 2
		case .monospace:
			controlCharacter = unichar(IRCTextFormatterEffectMonospaceCharacter)
			valueLength = 2
		case .strikethrough:
			controlCharacter = unichar(IRCTextFormatterEffectStrikethroughCharacter)
			valueLength = 2
		case .underline:
			controlCharacter = unichar(IRCTextFormatterEffectUnderlineCharacter)
			valueLength = 2
		case .foregroundColor, .backgroundColor:
			if let color = value as? NSColor {
				controlCharacter = unichar(IRCTextFormatterEffectColorAsHexCharacter)
				valueOut = String((color.hexadecimalValue as NSString).substring(from: 1))
			} else if let number = value as? NSNumber {
				controlCharacter = unichar(IRCTextFormatterEffectColorAsDigitCharacter)
				valueOut = number.integerStringValueWithLeadingZero
			}

			guard let resolvedValue = valueOut else {
				return false
			}

			if type == .foregroundColor {
				valueLength = UInt(resolvedValue.utf16.count) + 2
			} else {
				valueLength = UInt(resolvedValue.utf16.count) + 1
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
	public class func effects(in attributes: [String: Any]) -> TextFormatterEffects {
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
			guard dictionary.bool(forKey: attributeName(key)), let effect = TextFormatterEffect(effect: type) else {
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

public extension NSAttributedString {
	@objc(stringFormattedForChannel:onClient:withLineType:effectiveRange:)
	func stringFormatted(
		forChannel channelName: String,
		on client: IRCClient,
		with lineType: TVCLogLineType,
		effectiveRange: NSRangePointer?
	) -> String {
		var minimumLength: UInt = 1

		if let userHostmask = client.userHostmask {
			minimumLength += UInt(userHostmask.utf16.count)
		} else {
			minimumLength += UInt(truncationHostmaskConstant)
		}

		switch lineType {
		case .privateMessage, .privateMessageNoHighlight:
			minimumLength += UInt(truncationPRIVMSGCommandConstant)
		case .action, .actionNoHighlight:
			minimumLength += UInt(truncationACTIONCommandConstant)
		case .notice:
			minimumLength += UInt(truncationNOTICECommandConstant)
		default:
			preconditionFailure("Line type not supported")
		}

		minimumLength += UInt(channelName.utf16.count)
		minimumLength += 2
		minimumLength += 2

		var maximumLength = UInt(510)
		let serverLineLength = client.supportInfo.maximumLineLength

		if serverLineLength > (minimumLength + 2) {
			maximumLength = serverLineLength - 2
		}

		let string = string as NSString
		let result = NSMutableString()
		let encoding = String.Encoding(rawValue: client.effectivePrimaryEncoding)

		var resultLength = minimumLength
		var deletionLength: UInt = 0
		var limitRange = NSRange(location: 0, length: string.length)

		while limitRange.length > 0 {
			var breakLoopAfterAppend = false
			var segmentRange = NSRange()

			let attributes = stringKeyedAttributes(
				attributes(at: limitRange.location, longestEffectiveRange: &segmentRange, in: limitRange)
			)
			let formatters = TextFormatterEffects.effects(in: attributes)
			let formattersLength = formatters.maximumLength

			if segmentRange.location > 0 {
				let newLength = resultLength + formattersLength + 2

				if newLength > maximumLength {
					break
				}
			}

			resultLength += formattersLength
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

				resultLength += UInt(characterSize)

				if resultLength > maximumLength {
					let indexDifference = result.wrapIRCTextFormatterResult(
						with: UInt(segmentRange.location),
						maxDistance: UInt(truncationWrapMaxDistance)
					)

					if indexDifference != UInt(bitPattern: NSNotFound) {
						deletionLength -= UInt(indexDifference)
					}

					breakLoopAfterAppend = true

					break
				}

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
			"Minimum length: \(minimumLength, privacy: .public); Final length: \(resultLength, privacy: .public); Difference: \(Int(maximumLength) - Int(resultLength), privacy: .public);"
		)

		return result as String
	}

	@objc var stringFormattedForIRC: String {
		let string = string as NSString
		let result = NSMutableString()

		enumerateAttributes(in: range, options: []) { attributes, effectiveRange, _ in
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

			func markFound() {
				returnValue = true
				stop.pointee = true
			}

			switch effect {
			case .none:
				break
			case .bold:
				guard dictionary.bool(forKey: attributeName(IRCTextFormatterAttributeName.boldAttributeName)) else {
					return
				}

				markFound()
			case .italic:
				guard dictionary.bool(forKey: attributeName(IRCTextFormatterAttributeName.italicAttributeName)) else {
					return
				}

				markFound()
			case .monospace:
				guard dictionary.bool(forKey: attributeName(IRCTextFormatterAttributeName.monospaceAttributeName))
				else {
					return
				}

				markFound()
			case .underline:
				guard dictionary.bool(forKey: attributeName(IRCTextFormatterAttributeName.underlineAttributeName))
				else {
					return
				}

				markFound()
			case .strikethrough:
				guard dictionary.bool(forKey: attributeName(IRCTextFormatterAttributeName.strikethroughAttributeName))
				else {
					return
				}

				markFound()
			case .foregroundColor:
				guard
					let foregroundColor = dictionary[
						attributeName(IRCTextFormatterAttributeName.foregroundColorAttributeName)
					]
				else {
					return
				}

				if let colorCode = (foregroundColor as? NSNumber)?.intValue {
					guard colorCode >= 0, colorCode <= colorHighestDigit else {
						return
					}
				} else if (foregroundColor is NSColor) == false {
					return
				}

				markFound()
			case .backgroundColor:
				guard
					let backgroundColor = dictionary[
						attributeName(IRCTextFormatterAttributeName.backgroundColorAttributeName)
					]
				else {
					return
				}

				if let colorCode = (backgroundColor as? NSNumber)?.intValue {
					guard colorCode >= 0, colorCode <= colorHighestDigit else {
						return
					}
				} else if (backgroundColor is NSColor) == false {
					return
				}

				markFound()
			case .spoiler:
				guard dictionary.bool(forKey: attributeName(IRCTextFormatterAttributeName.spoilerAttributeName)) else {
					return
				}

				markFound()
			@unknown default:
				break
			}
		}

		return returnValue
	}
}

public extension NSMutableAttributedString {
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
			var baseFont = attributes[.font] as? NSFont

			switch effect {
			case .none:
				break
			case .bold:
				if let currentFont = baseFont, currentFont.fontTraitSet(.boldFontMask) == false {
					baseFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
				}

				if let baseFont {
					addAttribute(
						formatterKey(IRCTextFormatterAttributeName.boldAttributeName), value: true,
						range: effectiveRange
					)
					addAttribute(.font, value: baseFont, range: effectiveRange)
				}
			case .italic:
				if let currentFont = baseFont, currentFont.fontTraitSet(.italicFontMask) == false {
					baseFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
				}

				if let baseFont {
					addAttribute(
						formatterKey(IRCTextFormatterAttributeName.italicAttributeName), value: true,
						range: effectiveRange
					)
					addAttribute(.font, value: baseFont, range: effectiveRange)
				}
			case .monospace:
				let monospaceFont = monospaceFontMatching(baseFont)

				addAttribute(
					formatterKey(IRCTextFormatterAttributeName.monospaceAttributeName), value: true,
					range: effectiveRange
				)
				addAttribute(.font, value: monospaceFont, range: effectiveRange)
			case .underline:
				addAttribute(
					formatterKey(IRCTextFormatterAttributeName.underlineAttributeName), value: true,
					range: effectiveRange
				)
				addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: effectiveRange)
			case .strikethrough:
				addAttribute(
					formatterKey(IRCTextFormatterAttributeName.strikethroughAttributeName),
					value: true,
					range: effectiveRange
				)
				addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: effectiveRange)
			case .foregroundColor:
				guard let value else {
					break
				}

				if let number = value as? NSNumber {
					let colorCode = number.intValue

					if colorCode >= 0, colorCode <= colorHighestDigit {
						addAttribute(
							formatterKey(IRCTextFormatterAttributeName.foregroundColorAttributeName),
							value: colorCode,
							range: effectiveRange
						)
						addAttribute(
							.foregroundColor,
							value: TVCLogRenderer.mapColorCode(UInt(colorCode)),
							range: effectiveRange
						)
					}
				} else if let color = value as? NSColor {
					addAttribute(
						formatterKey(IRCTextFormatterAttributeName.foregroundColorAttributeName),
						value: color,
						range: effectiveRange
					)
					addAttribute(.foregroundColor, value: color, range: effectiveRange)
				}
			case .backgroundColor:
				guard let value else {
					break
				}

				if let number = value as? NSNumber {
					let colorCode = number.intValue

					if colorCode >= 0, colorCode <= colorHighestDigit {
						addAttribute(
							formatterKey(IRCTextFormatterAttributeName.backgroundColorAttributeName),
							value: colorCode,
							range: effectiveRange
						)
						addAttribute(
							.backgroundColor,
							value: TVCLogRenderer.mapColorCode(UInt(colorCode)),
							range: effectiveRange
						)
					}
				} else if let color = value as? NSColor {
					addAttribute(
						formatterKey(IRCTextFormatterAttributeName.backgroundColorAttributeName),
						value: color,
						range: effectiveRange
					)
					addAttribute(.backgroundColor, value: color, range: effectiveRange)
				}
			case .spoiler:
				if let value {
					addAttribute(
						formatterKey(IRCTextFormatterAttributeName.spoilerAttributeName),
						value: value,
						range: effectiveRange
					)
				}
			@unknown default:
				break
			}
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
				if baseFont.fontTraitSet(.boldFontMask) {
					baseFont = NSFontManager.shared.convert(baseFont, toNotHaveTrait: .boldFontMask)

					addAttribute(.font, value: baseFont, range: effectiveRange)
					removeAttribute(
						formatterKey(IRCTextFormatterAttributeName.boldAttributeName), range: effectiveRange
					)
				}
			case .italic:
				if baseFont.fontTraitSet(.italicFontMask) {
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

public extension NSMutableString {
	@objc(wrapIRCTextFormatterResultWith:maxDistance:)
	func wrapIRCTextFormatterResult(with minimumIndex: UInt, maxDistance: UInt) -> UInt {
		precondition(maxDistance > 0)

		let selfLength = length
		let searchIndex = Int(bitPattern: UInt(selfLength) &- 1 &- maxDistance)
		let searchRange = NSRange(location: searchIndex, length: Int(maxDistance))
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
