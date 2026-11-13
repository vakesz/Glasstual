// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The command token and caret in a single command line. Ranges use TextKit's
/// UTF-16 coordinates, including when arguments contain emoji or other scripts.
struct SlashCommandRequest {
	let commandName: String
	let commandPrefix: String
	let commandRange: NSRange
	let isEditingCommand: Bool
	private let selection: NSRange
	private let hasArgumentSeparator: Bool

	init?(text: String, selection: NSRange) {
		guard text.hasPrefix("/"), text.hasPrefix("//") == false,
		      text.rangeOfCharacter(from: .newlines) == nil,
		      selection.location != NSNotFound, selection.location >= 1,
		      selection.length == 0, let selectedRange = Range(selection, in: text),
		      selectedRange.lowerBound.samePosition(in: text.unicodeScalars) != nil
		else { return nil }

		let tokenEnd = text.firstIndex(where: \.isWhitespace) ?? text.endIndex
		let tokenRange = NSRange(text.startIndex ..< tokenEnd, in: text)
		let editingCommand = selection.location <= NSMaxRange(tokenRange)
		let prefixLength = min(selection.location, NSMaxRange(tokenRange)) - 1
		commandName = String(text[text.index(after: text.startIndex) ..< tokenEnd]).lowercased()
		commandPrefix = (text as NSString).substring(with: NSRange(location: 1, length: prefixLength)).lowercased()
		commandRange = tokenRange
		isEditingCommand = editingCommand
		self.selection = selection
		hasArgumentSeparator = tokenEnd < text.endIndex
	}

	/// Replace only the command token. Existing spacing and arguments survive.
	func replacement(for suggestion: SlashCommandSuggestion) -> SlashCommandReplacement {
		let text = "/" + suggestion.name + (hasArgumentSeparator ? "" : " ")
		let argumentCaretOffset = isEditingCommand ? 0 : selection.location - NSMaxRange(commandRange)
		return SlashCommandReplacement(
			range: commandRange,
			text: text,
			selection: NSRange(location: text.utf16.count + argumentCaretOffset, length: 0)
		)
	}
}

struct SlashCommandReplacement: Equatable {
	let range: NSRange
	let text: String
	let selection: NSRange
}
