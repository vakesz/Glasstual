// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions

// AppKit: IRC formatting is applied to attributed strings as fonts and colours.
import AppKit
import Foundation

enum TextFormatterEffectKind: Int, Sendable {
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

nonisolated struct TextFormatterAttributeName: RawRepresentable, Hashable, Sendable {
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

/// The mIRC control codes a message body carries, as the UTF-16 code units the
/// scanners and serialisers compare against.
nonisolated enum TextFormatterControlCharacter {
	static let colorDigit: unichar = 0x03
	static let colorHex: unichar = 0x04
	static let bold: unichar = 0x02
	static let italic: unichar = 0x1D
	static let legacyItalic: unichar = 0x16
	static let monospace: unichar = 0x11
	static let strikethrough: unichar = 0x1E
	static let underline: unichar = 0x1F
	static let terminator: unichar = 0x0F
}

nonisolated enum TextFormatterColor {
	static let maximumPaletteIndex = 98
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
	_ effect: TextFormatterEffectKind,
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
	let type: TextFormatterEffectKind
	let value: String?
	let controlCharacter: unichar
	let length: UInt

	init?(effect type: TextFormatterEffectKind, withValue value: Any? = nil) {
		var controlCharacter: unichar = 0
		var valueLength: UInt = 0
		var valueOut: String?

		switch type {
		case .none:
			break
		case .bold:
			controlCharacter = TextFormatterControlCharacter.bold
			valueLength = 2
		case .italic:
			controlCharacter = TextFormatterControlCharacter.italic
			valueLength = 2
		case .monospace:
			controlCharacter = TextFormatterControlCharacter.monospace
			valueLength = 2
		case .strikethrough:
			controlCharacter = TextFormatterControlCharacter.strikethrough
			valueLength = 2
		case .underline:
			controlCharacter = TextFormatterControlCharacter.underline
			valueLength = 2
		case .foregroundColor, .backgroundColor:
			if let color = value as? NSColor {
				controlCharacter = TextFormatterControlCharacter.colorHex
				valueOut = String((color.hexadecimalString as NSString).substring(from: 1))
			} else if let number = value as? NSNumber {
				controlCharacter = TextFormatterControlCharacter.colorDigit
				valueOut = number.twoDigitString
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

		func appendBooleanEffect(_ type: TextFormatterEffectKind, key: TextFormatterAttributeName) {
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

extension NSAttributedString {
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

	func ircFormatterAttributeSet(inRange effect: TextFormatterEffectKind, range limitRange: NSRange) -> Bool {
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
