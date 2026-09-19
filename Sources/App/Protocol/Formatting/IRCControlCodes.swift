// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Ending a line's formatting, and reading a line with none of it.
///
/// Only what a control-code scan can answer from the string itself lives here.
/// Turning those codes into attributes is the transcript's own pass and sits
/// with the renderer.
nonisolated extension NSString { // nonisolated: pure
	var stringByAppendingIRCFormattingStop: String {
		(self as String) + String(utf16CodeUnits: [TextFormatterControlCharacter.terminator], count: 1)
	}

	var stripIRCEffects: String {
		TextFormatting.removingControlCodes(from: self as String)
	}
}

/** IRC wire-format normalization: the mIRC control codes a message body can carry. */
nonisolated enum TextFormatting {
	/** Removes mIRC formatting control sequences while preserving message text.

	 The colour codes are measured by the same scanner the renderer reads them
	 with, ``NSString/colorComponents(ofCharacter:startingAt:)``, so a code this
	 pass strips and a code the transcript paints can never be different lengths.
	 The body is walked as a UTF-16 array because every other control character
	 costs one unit, and the scanner is only asked about the two colour codes. */
	static func removingControlCodes(from text: String) -> String {
		let input = Array(text.utf16)
		guard input.isEmpty == false else {
			return text
		}

		let scanner = text as NSString
		var output: [UInt16] = []
		output.reserveCapacity(input.count)

		var index = input.startIndex
		while index < input.endIndex {
			let character = input[index]

			switch character {
			case TextFormatterControlCharacter.bold,
			     TextFormatterControlCharacter.italic,
			     TextFormatterControlCharacter.legacyItalic,
			     TextFormatterControlCharacter.monospace,
			     TextFormatterControlCharacter.strikethrough,
			     TextFormatterControlCharacter.underline,
			     TextFormatterControlCharacter.terminator:
				index += 1
			case TextFormatterControlCharacter.colorDigit,
			     TextFormatterControlCharacter.colorHex:
				/* A code the scanner refuses to read consumed nothing, and a walk
				 that consumes nothing never ends: the control character itself is
				 dropped and the scan carries on behind it. */
				let components = scanner.colorComponents(
					ofCharacter: character,
					startingAt: UInt(index)
				)

				index += max(components.charactersConsumed, 1)
			default:
				output.append(character)
				index += 1
			}
		}

		return String(decoding: output, as: UTF16.self)
	}
}
