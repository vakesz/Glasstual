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

	/// Consumes and returns the double-quoted token at the cursor with its
	/// escapes resolved, or the empty string when the cursor is not on one. The
	/// cursor does not move when there is no token.
	///
	/// A closing quote counts only when whitespace or the end of the line
	/// follows it, and each run of *n* backslashes collapses to *n* minus
	/// *n* / 2 of them.
	public mutating func nextQuotedToken() -> String {
		let source = Array(remainder)

		guard source.count >= 2, source[0] == "\"" else {
			return ""
		}

		guard let scan = Self.scanQuotedToken(source) else {
			return ""
		}

		var token = Array(source[1 ..< scan.closingQuote])

		/* Positions are token-relative: a backslash at source index i is at
		 token index i - 1. */
		for position in scan.escapedSlashPositions.reversed() where position < token.count {
			token.remove(at: position)
		}

		token = Self.collapsingSlashRuns(token)

		var deletionEnd = scan.closingQuote + 1

		while deletionEnd < source.count, Self.isWhitespace(source[deletionEnd]) {
			deletionEnd += 1
		}

		cursor = base.index(cursor, offsetBy: deletionEnd)
		return String(token)
	}

	private struct QuoteScan {
		let closingQuote: Int
		let escapedSlashPositions: [Int]
	}

	private static func scanQuotedToken(_ source: [Character]) -> QuoteScan? {
		var escapedSlashPositions: [Int] = []
		var index = 1

		while index < source.count {
			while index < source.count, source[index] != "\"" {
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
			} else if probableEndQuote {
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
