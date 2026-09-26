// Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// How many argument groups a command's documented syntax declares.
///
/// Every top-level `<group>` is required and every `[group]` is optional. It
/// describes the documented syntax, not what a particular handler goes on to
/// read.
nonisolated struct CommandArity: Sendable, Equatable {
	let required: Int
	let optional: Int

	static let none = CommandArity(required: 0, optional: 0)

	init(required: Int, optional: Int) {
		self.required = required
		self.optional = optional
	}

	init(syntax: String?) {
		guard let syntax else {
			self = .none

			return
		}

		var required = 0
		var optional = 0
		var depth = 0
		var openedWith: Character?

		for character in syntax {
			switch character {
			case "<", "[":
				if depth == 0 {
					openedWith = character
				}

				depth += 1
			case ">", "]":
				guard depth > 0 else {
					continue
				}

				depth -= 1

				if depth == 0 {
					if openedWith == "<" {
						required += 1
					} else {
						optional += 1
					}
				}
			default:
				continue
			}
		}

		self.init(required: required, optional: optional)
	}
}

/// The arguments of a user-typed command, read left to right.
///
/// Commands are typed into a rich-text field and a few of them (ME, TOPIC,
/// MSG) have to put the formatting back on the wire, so the arguments arrive
/// as an `NSAttributedString`. This walks a cursor over that string rather
/// than deleting characters from one shared mutable attributed string: it is a
/// value, so one dispatcher pulling a token can no longer disturb the next one
/// that is handed the same line.
struct CommandArguments {
	private let source: NSAttributedString
	private var tokenizer: CommandTokenizer

	/// What the command index declares this command takes. Handlers read
	/// arguments in whatever order suits them; this is the documented shape.
	let arity: CommandArity

	init(_ source: NSAttributedString, arity: CommandArity = .none) {
		self.source = NSAttributedString(attributedString: source)
		self.arity = arity
		tokenizer = CommandTokenizer(source.string)
	}

	init(_ source: String, arity: CommandArity = .none) {
		self.init(NSAttributedString(string: source), arity: arity)
	}

	/// Everything the cursor has not passed yet, as plain text.
	var rest: String {
		String(tokenizer.remainder)
	}

	/// Everything the cursor has not passed yet, formatting intact.
	var attributedRest: NSAttributedString {
		let consumed = tokenizer.consumedUTF16Length

		guard consumed > 0 else {
			return source
		}

		guard consumed < source.length else {
			return NSAttributedString()
		}

		return source.attributedSubstring(
			from: NSRange(location: consumed, length: source.length - consumed)
		)
	}

	var isEmpty: Bool {
		rest.isEmpty
	}

	/// How many whitespace-delimited tokens are left.
	var tokenCount: Int {
		var counter = tokenizer
		var count = 0

		while counter.nextToken().isEmpty == false {
			count += 1
		}

		return count
	}

	/// The caller has supplied at least as many tokens as the index declares
	/// required, and at least one either way.
	var satisfiesDeclaredArity: Bool {
		isEmpty == false && tokenCount >= arity.required
	}

	/// Consumes and returns the next whitespace-delimited token, or the empty
	/// string once the line is exhausted.
	mutating func next() -> String {
		tokenizer.nextToken()
	}

	/// Consumes and returns the quoted token at the cursor, or the empty string
	/// when the cursor is not on one. The cursor does not move in that case.
	mutating func nextQuoted() -> String {
		tokenizer.nextQuotedToken()
	}
}

/// A line the user typed into the input field, split into its command and the
/// arguments that follow it.
struct ParsedUserCommand {
	/// The command exactly as typed. Syntax messages quote it and unknown
	/// commands are handed to a user script or to the server under it.
	let command: String

	/// The command the name resolves to, absent when the session has never heard
	/// of it. Handlers switch on this rather than on the string.
	let localCommand: LocalCommand?

	var arguments: CommandArguments

	var isDeveloperModeOnly: Bool {
		localCommand?.isDeveloperModeOnly ?? false
	}

	init?(_ input: String) {
		self.init(NSAttributedString(string: input))
	}

	init?(_ source: NSAttributedString) {
		guard source.length > 0 else {
			return nil
		}

		var line = source

		if line.string.hasPrefix("/") {
			line = line.attributedSubstring(from: NSRange(location: 1, length: line.length - 1))
		}

		var tokenizer = CommandTokenizer(line.string)
		let name = tokenizer.nextToken()
		guard !name.isEmpty else { return nil }
		let remainder = line.attributedSubstring(
			from: NSRange(
				location: tokenizer.consumedUTF16Length,
				length: line.length - tokenizer.consumedUTF16Length
			)
		)

		command = name
		localCommand = LocalCommand(typedName: name)
		arguments = CommandArguments(remainder, arity: localCommand?.arity ?? .none)
	}
}
