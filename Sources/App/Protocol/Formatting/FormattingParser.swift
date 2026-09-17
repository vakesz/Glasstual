// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Turns IRC formatting control sequences into attributed text in one pass.
/// The renderer consumes the attributes without needing to know how control
/// sequences change formatting state or how many UTF-16 units they occupy.
///
/// Every other control character is settled in the same pass, the way
/// ``TranscriptTextSanitizer`` says: a line separator is drawn as a space and
/// the rest are dropped, so no formatted string can break out of its line.
nonisolated enum FormattingParser {
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
				guard character < 0x20 || TranscriptTextSanitizer.disposition(of: character) != .keep else {
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
			case UniChar(TextFormatterControlCharacter.bold):
				return toggle(RendererFormatting.bold, at: position)
			case UniChar(TextFormatterControlCharacter.italic),
			     UniChar(TextFormatterControlCharacter.legacyItalic):
				return toggle(RendererFormatting.italic, at: position)
			case UniChar(TextFormatterControlCharacter.monospace):
				return toggle(RendererFormatting.monospace, at: position)
			case UniChar(TextFormatterControlCharacter.strikethrough):
				return toggle(RendererFormatting.strikethrough, at: position)
			case UniChar(TextFormatterControlCharacter.underline):
				return toggle(RendererFormatting.underline, at: position)
			case UniChar(TextFormatterControlCharacter.colorDigit),
			     UniChar(TextFormatterControlCharacter.colorHex):
				return consumeColor(character, at: position)
			case UniChar(TextFormatterControlCharacter.terminator):
				result.setAttributes([:], range: remainingRange(from: position))
				result.deleteCharacters(in: NSRange(location: position, length: 1))
				return 1
			default:
				switch TranscriptTextSanitizer.disposition(of: character) {
				case .keep:
					return 0
				case .space:
					result.replaceCharacters(in: NSRange(location: position, length: 1), with: " ")
					return 0
				case .remove:
					result.deleteCharacters(in: NSRange(location: position, length: 1))
					return 1
				}
			}
		}

		private func toggle(_ key: NSAttributedString.Key, at position: Int) -> Int {
			if result.attribute(key, at: position, effectiveRange: nil) != nil {
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

			/* Each half is applied on its own. Deciding the background from
			 whether the foreground was named is what kept an old background
			 alive through \u{3}04,99: the code did name a background, and what
			 it named was the absence of one. */
			apply(components.foreground, key: RendererFormatting.foregroundColor, at: position)
			apply(components.background, key: RendererFormatting.backgroundColor, at: position)

			let consumedCount = max(components.charactersConsumed, 1)
			result.deleteCharacters(in: NSRange(location: position, length: consumedCount))
			return consumedCount
		}

		private func apply(_ selection: MircColorSelection, key: NSAttributedString.Key, at position: Int) {
			switch selection {
			case .unchanged:
				break
			case .reset:
				removeAttribute(key, at: position)
			case let .color(color):
				result.addAttribute(
					key,
					value: color.attributeValue,
					range: remainingRange(from: position)
				)
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
