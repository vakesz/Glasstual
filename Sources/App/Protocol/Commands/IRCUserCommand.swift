/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation

/// The arguments of a user-typed command, read left to right.
///
/// Commands are typed into a rich-text field and a few of them (ME, TOPIC,
/// MSG) have to put the formatting back on the wire, so the arguments arrive
/// as an `NSAttributedString`. This walks a cursor over that string rather
/// than deleting characters from a shared `NSMutableAttributedString`: it is a
/// value, so one dispatcher pulling a token can no longer disturb the next one
/// that is handed the same line.
public struct CommandArguments {
	private let source: NSAttributedString
	private var tokenizer: CommandTokenizer

	/// What the command index declares this command takes. Handlers read
	/// arguments in whatever order suits them; this is the documented shape.
	public let arity: CommandArity

	public init(_ source: NSAttributedString, arity: CommandArity = .none) {
		self.source = source
		self.arity = arity
		tokenizer = CommandTokenizer(source.string)
	}

	public init(_ source: String, arity: CommandArity = .none) {
		self.init(NSAttributedString(string: source), arity: arity)
	}

	/// Everything the cursor has not passed yet, as plain text.
	public var rest: String {
		String(tokenizer.remainder)
	}

	/// Everything the cursor has not passed yet, formatting intact.
	public var attributedRest: NSAttributedString {
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

	public var isEmpty: Bool {
		rest.isEmpty
	}

	/// How many whitespace-delimited tokens are left.
	public var tokenCount: Int {
		var counter = tokenizer
		var count = 0

		while counter.nextToken().isEmpty == false {
			count += 1
		}

		return count
	}

	/// The caller has supplied at least as many tokens as the index declares
	/// required, and at least one either way.
	public var satisfiesDeclaredArity: Bool {
		isEmpty == false && tokenCount >= arity.required
	}

	/// Consumes and returns the next whitespace-delimited token, or the empty
	/// string once the line is exhausted.
	public mutating func next() -> String {
		tokenizer.nextToken()
	}

	/// Consumes and returns the quoted token at the cursor, or the empty string
	/// when the cursor is not on one. The cursor does not move in that case.
	public mutating func nextQuoted() -> String {
		tokenizer.nextQuotedToken()
	}
}

/// A line the user typed into the input field, split into its command and the
/// arguments that follow it.
public struct ParsedUserCommand {
	/// The command exactly as typed. Syntax messages quote it and unknown
	/// commands are handed to plugins and the server under it.
	public let command: String

	/// The command index entry, absent when the index has never heard of the
	/// name. Handlers switch on `localCommand` rather than on the string.
	public let descriptor: LocalCommandDescriptor?

	public var arguments: CommandArguments

	public var localCommand: IRCLocalCommand? {
		descriptor?.command
	}

	public var isDeveloperModeOnly: Bool {
		descriptor?.isDeveloperModeOnly ?? false
	}

	public init?(_ input: Any) {
		let source: NSAttributedString

		if let string = input as? String {
			source = NSAttributedString(string: string)
		} else if let attributed = input as? NSAttributedString {
			source = attributed
		} else {
			assertionFailure("Command input must be String or NSAttributedString")

			return nil
		}

		guard source.length > 0 else {
			return nil
		}

		var line = source

		if line.string.hasPrefix("/") {
			line = line.attributedSubstring(from: NSRange(location: 1, length: line.length - 1))
		}

		var tokenizer = CommandTokenizer(line.string)
		let name = tokenizer.nextToken()
		let remainder = line.attributedSubstring(
			from: NSRange(
				location: tokenizer.consumedUTF16Length,
				length: line.length - tokenizer.consumedUTF16Length
			)
		)

		command = name
		descriptor = CommandIndex.descriptor(forLocalCommand: name)
		arguments = CommandArguments(remainder, arity: descriptor?.arity ?? .none)
	}
}
