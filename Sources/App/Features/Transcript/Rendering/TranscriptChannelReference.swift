// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The channel names in a message, found under the prefixes the server advertised.

 One pass over the UTF-16 units with no pattern and no backtracking, so the
 cost grows with the length of the message and nothing a stranger writes can
 make it grow faster. A name starts at a `CHANTYPES` prefix that begins a word,
 so `foo#bar` names nothing, and runs to whitespace, a control character, a
 comma or a colon. The punctuation that closes a sentence or a bracket is not
 part of it: `join #swift.` names `#swift`. */
nonisolated enum TranscriptChannelReference {
	/// Characters a name may directly follow, besides whitespace, control
	/// characters and the start of the text.
	private static let openingPunctuation: Set<UInt16> = Set("([{<\"',;".utf16)
	/// Characters that end a name and are not part of it.
	private static let separators: Set<UInt16> = Set(",:".utf16)
	/// Characters a sentence or an enclosing bracket puts after a name.
	private static let trailingPunctuation: Set<UInt16> = Set(".,;:!?)'\">".utf16)

	/// The UTF-16 ranges of the channel names in `body`, in order. Only a
	/// prefix of one UTF-16 unit that is not whitespace, a control character or
	/// a separator can begin a name; `CHANTYPES` advertises single characters.
	static func locate(in body: String, prefixes: [String]) -> [NSRange] {
		let starts = Set(prefixes.compactMap { prefix -> UInt16? in
			let units = Array(prefix.utf16)
			guard units.count == 1, let unit = units.first,
			      isNameCharacter(unit), separators.contains(unit) == false
			else {
				return nil
			}
			return unit
		})
		guard starts.isEmpty == false else { return [] }

		let units = Array(body.utf16)
		var ranges: [NSRange] = []
		var index = 0
		while index < units.count {
			guard starts.contains(units[index]), beginsWord(at: index, in: units) else {
				index += 1
				continue
			}
			var end = index + 1
			while end < units.count, isNameCharacter(units[end]), separators.contains(units[end]) == false {
				end += 1
			}
			let nameEnd = trimmedEnd(of: index ..< end, in: units)
			if units[(index + 1) ..< nameEnd].contains(where: { starts.contains($0) == false }) {
				ranges.append(NSRange(location: index, length: nameEnd - index))
			}
			index = max(end, index + 1)
		}
		return ranges
	}

	private static func beginsWord(at index: Int, in units: [UInt16]) -> Bool {
		guard index > 0 else { return true }
		let previous = units[index - 1]
		return isNameCharacter(previous) == false || openingPunctuation.contains(previous)
	}

	private static func trimmedEnd(of range: Range<Int>, in units: [UInt16]) -> Int {
		var end = range.upperBound
		while end > range.lowerBound + 1, trailingPunctuation.contains(units[end - 1]) {
			end -= 1
		}
		return end
	}

	/// Whether a unit can sit inside a name: anything but whitespace and
	/// control characters, which include the bell some clients end a name with.
	private static func isNameCharacter(_ unit: UInt16) -> Bool {
		guard let scalar = Unicode.Scalar(unit) else { return true }
		return scalar.properties.isWhitespace == false && scalar.properties.generalCategory != .control
	}
}
