/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2020 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
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
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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

import Foundation

/// Splits an IRC command line into tokens, left to right.
///
/// The tokenizer owns a cursor into the string it was created with. Each
/// `next…` call returns the token at the cursor and moves the cursor past it
/// and past the whitespace that followed, so a sequence of calls walks the
/// line. An exhausted tokenizer keeps returning the empty string.
public struct CommandTokenizer: Sendable {
	public struct Options: OptionSet, Sendable {
		public let rawValue: UInt

		public init(rawValue: UInt) {
			self.rawValue = rawValue
		}

		/// `"` opens and closes a quoted token.
		public static let doubleQuotes = Options(rawValue: 1 << 0)

		/// `'` opens and closes a quoted token.
		public static let singleQuotes = Options(rawValue: 1 << 1)

		/// A closing quote only counts when whitespace or the end of the line
		/// follows it.
		public static let terminatesWithSpace = Options(rawValue: 1 << 2)

		/// Each run of *n* backslashes in the token collapses to *n* minus
		/// *n* / 2 of them.
		public static let collapseSlashes = Options(rawValue: 1 << 3)

		public static let `default`: Options = [.doubleQuotes, .terminatesWithSpace, .collapseSlashes]
	}

	private let base: String
	private var cursor: String.Index

	public init(_ source: String) {
		base = source
		cursor = source.startIndex
	}

	/// The part of the line that has not been consumed yet.
	public var remainder: Substring {
		base[cursor...]
	}

	/// How much of the line has been consumed, as a UTF-16 offset. Callers
	/// mutating a parallel `NSAttributedString` need this to delete the same
	/// span from it.
	public var consumedUTF16Length: Int {
		base.utf16.distance(from: base.startIndex, to: cursor)
	}

	/// Consumes and returns everything up to the next whitespace run, then
	/// steps over that run.
	public mutating func nextToken() -> String {
		let source = remainder

		guard !source.isEmpty else {
			return ""
		}

		let tokenEnd = source.firstIndex(where: Self.isWhitespace) ?? source.endIndex
		let token = String(source[..<tokenEnd])

		var deletionEnd = tokenEnd

		while deletionEnd < source.endIndex, Self.isWhitespace(source[deletionEnd]) {
			deletionEnd = source.index(after: deletionEnd)
		}

		cursor = deletionEnd
		return token
	}

	public mutating func nextUppercaseToken() -> String {
		nextToken().uppercased()
	}

	/// Consumes and returns the quoted token at the cursor with its escapes
	/// resolved, or the empty string when the cursor is not on one. The cursor
	/// does not move when there is no token.
	public mutating func nextQuotedToken(options: Options = .default) -> String {
		let source = Array(remainder)

		guard source.count >= 2 else {
			return ""
		}

		let openingQuote = source[0]

		guard openingQuote == "\"" && options.contains(.doubleQuotes)
			|| openingQuote == "'" && options.contains(.singleQuotes)
		else {
			return ""
		}

		guard let scan = Self.scanQuotedToken(source, openingQuote: openingQuote, options: options) else {
			return ""
		}

		var token = Array(source[1 ..< scan.closingQuote])

		/* Positions are token-relative: a backslash at source index i is at
		 token index i - 1. */
		for position in scan.escapedSlashPositions.reversed() where position < token.count {
			token.remove(at: position)
		}

		if options.contains(.collapseSlashes) {
			token = Self.collapsingSlashRuns(token)
		}

		var deletionEnd = scan.closingQuote + 1

		if options.contains(.terminatesWithSpace) {
			while deletionEnd < source.count, Self.isWhitespace(source[deletionEnd]) {
				deletionEnd += 1
			}
		}

		cursor = base.index(cursor, offsetBy: deletionEnd)
		return String(token)
	}

	private struct QuoteScan {
		let closingQuote: Int
		let escapedSlashPositions: [Int]
	}

	private static func scanQuotedToken(
		_ source: [Character],
		openingQuote: Character,
		options: Options
	) -> QuoteScan? {
		var escapedSlashPositions: [Int] = []
		var index = 1

		while index < source.count {
			while index < source.count, source[index] != openingQuote {
				index += 1
			}

			guard index < source.count else {
				return nil
			}

			let quotePosition = index
			index += 1

			var slashCount = 0
			var characterIndex = quotePosition - 1

			while characterIndex > 0, source[characterIndex] == "\\" {
				slashCount += 1
				characterIndex -= 1
			}

			let probableEndQuote = slashCount == 0 || slashCount.isMultiple(of: 2)

			if index == source.count {
				guard probableEndQuote else {
					return nil
				}
			} else if options.contains(.terminatesWithSpace), probableEndQuote {
				guard isWhitespaceOrNewline(source[index]) else {
					return nil
				}
			}

			if !slashCount.isMultiple(of: 2) {
				escapedSlashPositions.append(quotePosition - 2)
			}

			if probableEndQuote {
				return QuoteScan(closingQuote: quotePosition, escapedSlashPositions: escapedSlashPositions)
			}
		}

		return nil
	}

	private static func collapsingSlashRuns(_ characters: [Character]) -> [Character] {
		var result: [Character] = []
		var index = 0

		while index < characters.count {
			guard characters[index] == "\\" else {
				result.append(characters[index])
				index += 1
				continue
			}

			let start = index

			while index < characters.count, characters[index] == "\\" {
				index += 1
			}

			let slashCount = index - start
			result.append(contentsOf: repeatElement("\\", count: slashCount - slashCount / 2))
		}

		return result
	}

	private static func isWhitespace(_ character: Character) -> Bool {
		guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
			return false
		}

		return CharacterSet.whitespaces.contains(scalar)
	}

	private static func isWhitespaceOrNewline(_ character: Character) -> Bool {
		guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
			return false
		}

		return CharacterSet.whitespacesAndNewlines.contains(scalar)
	}
}

public extension String {
	/// The first whitespace-delimited token of the receiver, ignoring any
	/// leading or trailing whitespace. Empty when the receiver holds none.
	var firstToken: String {
		var tokenizer = CommandTokenizer(trimmingCharacters(in: .whitespacesAndNewlines))
		return tokenizer.nextToken()
	}
}

public extension NSMutableAttributedString {
	/// Consumes the next whitespace-delimited token and returns it as plain
	/// text, leaving the rest of the attributed line -- attributes intact --
	/// in the receiver.
	func nextTokenAsString() -> String {
		consume { $0.nextToken() }
	}

	/// Consumes the quoted token at the start of the receiver and returns it
	/// as plain text. The receiver is left untouched when it does not start
	/// with one.
	func nextQuotedTokenAsString() -> String {
		consume { $0.nextQuotedToken() }
	}

	private func consume(_ body: (inout CommandTokenizer) -> String) -> String {
		var tokenizer = CommandTokenizer(string)
		let token = body(&tokenizer)

		let consumed = tokenizer.consumedUTF16Length

		if consumed > 0 {
			deleteCharacters(in: NSRange(location: 0, length: consumed))
		}

		return token
	}
}
