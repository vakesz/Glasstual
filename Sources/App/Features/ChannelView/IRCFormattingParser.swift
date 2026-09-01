/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

/// Turns IRC formatting control sequences into attributed text in one pass.
/// The renderer consumes the attributes without needing to know how control
/// sequences change formatting state or how many UTF-16 units they occupy.
nonisolated enum IRCFormattingParser { // nonisolated: value
	static func parse(_ source: String) -> NSMutableAttributedString {
		var parser = Parser(source: source)
		return parser.parse()
	}

	private struct Parser {
		private let inputCharacters: [UniChar]
		private let result: NSMutableAttributedString
		private var removedCount = 0

		init(source: String) {
			let input = source as NSString
			var characters = [UniChar](repeating: 0, count: input.length)
			if input.length > 0 {
				input.getCharacters(&characters, range: NSRange(location: 0, length: input.length))
			}
			inputCharacters = characters
			result = NSMutableAttributedString(string: source)
		}

		mutating func parse() -> NSMutableAttributedString {
			result.beginEditing()
			var inputIndex = 0

			while inputIndex < inputCharacters.count {
				let character = inputCharacters[inputIndex]
				guard character < 0x20 else {
					inputIndex += 1
					continue
				}

				let consumedCount = consume(character, at: inputIndex - removedCount)
				removedCount += consumedCount
				inputIndex += max(consumedCount, 1)
			}

			result.endEditing()
			return result
		}

		private mutating func consume(_ character: UniChar, at position: Int) -> Int {
			switch character {
			case UniChar(IRCTextFormatterControlCharacter.bold):
				return toggle(RendererFormatting.bold, at: position)
			case UniChar(IRCTextFormatterControlCharacter.italic),
			     UniChar(IRCTextFormatterControlCharacter.legacyItalic):
				return toggle(RendererFormatting.italic, at: position)
			case UniChar(IRCTextFormatterControlCharacter.monospace):
				return toggle(RendererFormatting.monospace, at: position)
			case UniChar(IRCTextFormatterControlCharacter.strikethrough):
				return toggle(RendererFormatting.strikethrough, at: position)
			case UniChar(IRCTextFormatterControlCharacter.underline):
				return toggle(RendererFormatting.underline, at: position)
			case UniChar(IRCTextFormatterControlCharacter.colorDigit),
			     UniChar(IRCTextFormatterControlCharacter.colorHex):
				return consumeColor(character, at: position)
			case UniChar(IRCTextFormatterControlCharacter.terminator):
				result.setAttributes([:], range: remainingRange(from: position))
				result.deleteCharacters(in: NSRange(location: position, length: 1))
				return 1
			default:
				return 0
			}
		}

		private func toggle(_ key: NSAttributedString.Key, at position: Int) -> Int {
			if position > 0, result.attribute(key, at: position, effectiveRange: nil) != nil {
				result.removeAttribute(key, range: remainingRange(from: position))
			} else {
				result.addAttribute(key, value: true, range: remainingRange(from: position))
			}

			result.deleteCharacters(in: NSRange(location: position, length: 1))
			return 1
		}

		private func consumeColor(_ character: UniChar, at position: Int) -> Int {
			let components = (result.string as NSString).colorComponents(
				ofCharacter: character,
				startingAt: UInt(position)
			)
			applyColor(components.foreground, key: RendererFormatting.foregroundColor, at: position)

			if components.background != nil {
				applyColor(components.background, key: RendererFormatting.backgroundColor, at: position)
			} else if components.foreground == nil, position > 0 {
				removeAttribute(RendererFormatting.backgroundColor, at: position)
			}

			let consumedCount = max(components.charactersConsumed, 1)
			result.deleteCharacters(in: NSRange(location: position, length: consumedCount))
			return consumedCount
		}

		private func applyColor(_ color: IRCColor?, key: NSAttributedString.Key, at position: Int) {
			if let color {
				result.addAttribute(
					key,
					value: color.attributeValue,
					range: remainingRange(from: position)
				)
			} else if position > 0 {
				removeAttribute(key, at: position)
			}
		}

		private func removeAttribute(_ key: NSAttributedString.Key, at position: Int) {
			guard result.attribute(key, at: position, effectiveRange: nil) != nil else {
				return
			}
			result.removeAttribute(key, range: remainingRange(from: position))
		}

		private func remainingRange(from position: Int) -> NSRange {
			NSRange(location: position, length: result.length - position)
		}
	}
}
