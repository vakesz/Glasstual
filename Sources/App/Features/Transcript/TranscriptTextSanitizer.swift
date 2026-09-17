// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Keeps text a stranger sent inside the run it was drawn in.

 The transcript is one text storage. A line separator in a message starts a new
 paragraph in it, and a paragraph that begins with a timestamp and a name looks
 exactly like a line someone else sent; a bidirectional override turns the rest
 of the paragraph around, reactions and receipts included. Wire text is
 therefore held to a single line, its explicit bidirectional formatting is
 removed, and the transcript draws each piece of it inside an isolate of its
 own, which is what bounds the reordering the implicit algorithm still does.

 The IRC formatting codes are not this type's business: the formatting parser
 consumes them first and hands every other control character here. */
nonisolated enum TranscriptTextSanitizer {
	/// U+2068 FIRST STRONG ISOLATE: opens the isolate a wire string is drawn in.
	static let isolateStart = "\u{2068}"
	/// U+2069 POP DIRECTIONAL ISOLATE: closes it.
	static let isolateEnd = "\u{2069}"

	/// What a UTF-16 unit of wire text becomes when it is drawn.
	enum Disposition: Equatable {
		case keep
		/// Drawn as a space: it would otherwise break the line.
		case space
		/// Not drawn at all.
		case remove
	}

	static func disposition(of unit: UniChar) -> Disposition {
		switch unit {
		case 0x09:
			.keep
		case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029:
			.space
		case 0x00 ..< 0x20, 0x7F, 0x80 ..< 0xA0:
			.remove
		case 0x202A ... 0x202E, 0x2066 ... 0x2069:
			.remove
		default:
			.keep
		}
	}

	/// Whether any unit of `text` would be changed.
	static func needsSanitizing(_ text: String) -> Bool {
		text.utf16.contains { disposition(of: $0) != .keep }
	}

	/// `text` as one line with no control characters and no explicit
	/// bidirectional formatting, for wire text that carries no IRC formatting:
	/// a nickname, a reaction, a failure reason.
	static func singleLine(_ text: String) -> String {
		guard needsSanitizing(text) else { return text }
		var units: [UniChar] = []
		units.reserveCapacity(text.utf16.count)
		for unit in text.utf16 {
			switch disposition(of: unit) {
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
			switch disposition(of: source.character(at: location)) {
			case .keep: break
			case .space: text.replaceCharacters(in: NSRange(location: location, length: 1), with: " ")
			case .remove: text.deleteCharacters(in: NSRange(location: location, length: 1))
			}
		}
	}
}
