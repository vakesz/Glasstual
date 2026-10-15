// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What a UTF-16 unit of wire text becomes when it is drawn.

 Wire text is held to a single line and its explicit bidirectional formatting
 is removed, so a stranger's message cannot start a paragraph of its own or
 turn the rest of a line around. The IRC formatting codes are not this type's
 business: the formatting parser consumes them first and hands every other
 control character here. */
nonisolated enum ControlCharacterDisposition: Equatable {
	case keep
	/// Drawn as a space: it would otherwise break the line.
	case space
	/// Not drawn at all.
	case remove

	init(of unit: UniChar) {
		switch unit {
		case 0x09:
			self = .keep
		case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029:
			self = .space
		case 0x00 ..< 0x20, 0x7F, 0x80 ..< 0xA0:
			self = .remove
		case 0x202A ... 0x202E, 0x2066 ... 0x2069:
			self = .remove
		default:
			self = .keep
		}
	}

	/// Whether any unit of `text` would be changed.
	static func needsSanitizing(_ text: String) -> Bool {
		text.utf16.contains { Self(of: $0) != .keep }
	}

	/// `text` as one line with no control characters and no explicit
	/// bidirectional formatting, for wire text that carries no IRC formatting:
	/// a nickname, a reaction, a failure reason.
	static func singleLine(_ text: String) -> String {
		guard needsSanitizing(text) else { return text }
		var units: [UniChar] = []
		units.reserveCapacity(text.utf16.count)
		for unit in text.utf16 {
			switch Self(of: unit) {
			case .keep: units.append(unit)
			case .space: units.append(0x20)
			case .remove: break
			}
		}
		return String(decoding: units, as: UTF16.self)
	}

	/// The same, applied in place to attributed text that has already been
	/// formatted, keeping every remaining character's attributes.
	static func sanitize(_ text: NSMutableAttributedString) {
		let source = text.string as NSString
		guard needsSanitizing(text.string) else { return }
		var location = source.length
		while location > 0 {
			location -= 1
			switch Self(of: source.character(at: location)) {
			case .keep: break
			case .space: text.replaceCharacters(in: NSRange(location: location, length: 1), with: " ")
			case .remove: text.deleteCharacters(in: NSRange(location: location, length: 1))
			}
		}
	}
}
