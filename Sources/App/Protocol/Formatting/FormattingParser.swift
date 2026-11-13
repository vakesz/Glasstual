// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Turns IRC formatting control sequences into attributed text in one pass.
/// The renderer consumes the attributes without needing to know how control
/// sequences change formatting state or how many UTF-16 units they occupy.
///
/// Every other control character is settled in the same pass, the way
/// ``ControlCharacterDisposition`` says: a line separator is drawn as a space and
/// the rest are dropped, so no formatted string can break out of its line.
///
/// A line feed is the one separator that can be kept. Only a `draft/multiline`
/// message can carry one, since a line on the wire cannot, so the renderer asks
/// for it on the lines that hold a person's text and nowhere else.
nonisolated enum FormattingParser {
	static func parse(_ source: String, preservingLineFeeds: Bool = false) -> NSMutableAttributedString {
		var parser = Parser(source: source, preservesLineFeeds: preservingLineFeeds)
		return parser.parse()
	}

	private struct Parser {
		private let inputCharacters: [UniChar]
		/// The source again, as the string the colour scanner reads. Built once:
		/// the digits of a code are not deleted until it is consumed, so they are
		/// read where they were written instead of from a copy of the result.
		private let inputString: NSString
		private let result: NSMutableAttributedString
		private let preservesLineFeeds: Bool
		private var removedCount = 0

		init(source: String, preservesLineFeeds: Bool) {
			self.preservesLineFeeds = preservesLineFeeds
			let input = source as NSString
			var characters = [UniChar](repeating: 0, count: input.length)
			if input.length > 0 {
				input.getCharacters(&characters, range: NSRange(location: 0, length: input.length))
			}
			inputCharacters = characters
			inputString = NSString(characters: characters, length: characters.count)
			result = NSMutableAttributedString(string: source)
		}

		mutating func parse() -> NSMutableAttributedString {
			result.beginEditing()
			var inputIndex = 0

			while inputIndex < inputCharacters.count {
				let character = inputCharacters[inputIndex]
				if preservesLineFeeds, character == 0x0A {
					inputIndex += 1
					continue
				}

				guard character < 0x20 || ControlCharacterDisposition(of: character) != .keep else {
					inputIndex += 1
					continue
				}

				let consumedCount = consume(character, at: inputIndex - removedCount, inputIndex: inputIndex)
				removedCount += consumedCount
				inputIndex += max(consumedCount, 1)
			}

			result.endEditing()
			return result
		}

		private mutating func consume(_ character: UniChar, at position: Int, inputIndex: Int) -> Int {
			switch character {
			case TextFormatterControlCharacter.bold:
				return toggle(IRCFormattingAttribute.bold, at: position)
			case TextFormatterControlCharacter.italic:
				return toggle(IRCFormattingAttribute.italic, at: position)
			case TextFormatterControlCharacter.reverse:
				return toggle(IRCFormattingAttribute.reverse, at: position)
			case TextFormatterControlCharacter.monospace:
				return toggle(IRCFormattingAttribute.monospace, at: position)
			case TextFormatterControlCharacter.strikethrough:
				return toggle(IRCFormattingAttribute.strikethrough, at: position)
			case TextFormatterControlCharacter.underline:
				return toggle(IRCFormattingAttribute.underline, at: position)
			case TextFormatterControlCharacter.colorDigit,
			     TextFormatterControlCharacter.colorHex:
				return consumeColor(character, at: position, inputIndex: inputIndex)
			case TextFormatterControlCharacter.terminator:
				result.setAttributes([:], range: remainingRange(from: position))
				result.deleteCharacters(in: NSRange(location: position, length: 1))
				return 1
			default:
				switch ControlCharacterDisposition(of: character) {
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

		/// `position` is where the code sits in the result, which is where it is
		/// deleted; `inputIndex` is where it sits in the source, which is where
		/// it is read.
		private func consumeColor(_ character: UniChar, at position: Int, inputIndex: Int) -> Int {
			let components = inputString.colorComponents(
				ofCharacter: character,
				startingAt: UInt(inputIndex)
			)

			/* Each half is applied on its own. Deciding the background from
			 whether the foreground was named is what kept an old background
			 alive through \u{3}04,99: the code did name a background, and what
			 it named was the absence of one. */
			apply(components.foreground, key: IRCFormattingAttribute.foregroundColor, at: position)
			apply(components.background, key: IRCFormattingAttribute.backgroundColor, at: position)

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
