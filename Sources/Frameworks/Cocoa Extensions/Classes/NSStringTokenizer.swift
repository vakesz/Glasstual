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

private enum StringTokenizer {
	struct Options: OptionSet {
		let rawValue: UInt

		static let doubleQuotes = Options(rawValue: 1 << 0)
		static let singleQuotes = Options(rawValue: 1 << 1)
		static let terminatesWithSpace = Options(rawValue: 1 << 2)
		static let collapseSlashes = Options(rawValue: 1 << 3)
		static let `default`: Options = [.doubleQuotes, .terminatesWithSpace, .collapseSlashes]
	}

	struct WhitespaceToken {
		let value: String
		let tokenRange: NSRange
		let deletionRange: NSRange
	}

	struct QuoteToken {
		let tokenRange: NSRange
		let deletionRange: NSRange
		let escapedSlashRanges: [NSRange]
		let collapseSlashRanges: [NSRange]
	}

	static let emptyRange = NSRange(location: NSNotFound, length: 0)
	private static let backslash = unichar(92)
	private static let doubleQuote = unichar(34)
	private static let singleQuote = unichar(39)

	static func whitespaceToken(in string: NSString) -> WhitespaceToken? {
		guard string.length > 0 else {
			return nil
		}

		var tokenEnd = 0
		while tokenEnd < string.length,
		      !(CharacterSet.whitespaces as NSCharacterSet).characterIsMember(string.character(at: tokenEnd))
		{
			tokenEnd += 1
		}

		let tokenRange = NSRange(location: 0, length: tokenEnd)
		var deletionEnd = tokenEnd
		while deletionEnd < string.length,
		      (CharacterSet.whitespaces as NSCharacterSet).characterIsMember(string.character(at: deletionEnd))
		{
			deletionEnd += 1
		}

		return WhitespaceToken(
			value: string.substring(with: tokenRange),
			tokenRange: tokenRange,
			deletionRange: NSRange(location: 0, length: deletionEnd)
		)
	}

	static func quoteToken(in string: NSString, rawOptions: UInt) -> QuoteToken? {
		guard string.length >= 2 else {
			return nil
		}

		let options = rawOptions == 0 ? Options.default : Options(rawValue: rawOptions)
		let openingQuote = string.character(at: 0)
		guard openingQuote == doubleQuote && options.contains(.doubleQuotes)
			|| openingQuote == singleQuote && options.contains(.singleQuotes)
		else {
			return nil
		}

		var escapedSlashRanges: [NSRange] = []
		var scanLocation = 1
		var closingQuoteLocation: Int?

		while scanLocation < string.length {
			while scanLocation < string.length, string.character(at: scanLocation) != openingQuote {
				scanLocation += 1
			}

			guard scanLocation < string.length else {
				return nil
			}

			let quoteLocation = scanLocation
			scanLocation += 1

			var slashCount = 0
			var characterIndex = quoteLocation - 1
			while characterIndex > 0, string.character(at: characterIndex) == backslash {
				slashCount += 1
				characterIndex -= 1
			}

			let probableEndQuote = slashCount == 0 || slashCount.isMultiple(of: 2)
			if scanLocation == string.length {
				guard probableEndQuote else {
					return nil
				}
			} else if options.contains(.terminatesWithSpace), probableEndQuote {
				let nextCharacter = string.character(at: scanLocation)
				guard (CharacterSet.whitespacesAndNewlines as NSCharacterSet).characterIsMember(nextCharacter) else {
					return nil
				}
			}

			if slashCount > 0, !slashCount.isMultiple(of: 2) {
				escapedSlashRanges.append(NSRange(location: quoteLocation - 2, length: 1))
			}

			if probableEndQuote {
				closingQuoteLocation = quoteLocation
				break
			}
		}

		guard let closingQuoteLocation else {
			return nil
		}

		let tokenRange = NSRange(location: 1, length: closingQuoteLocation - 1)
		var deletionEnd = closingQuoteLocation + 1
		if options.contains(.terminatesWithSpace) {
			while deletionEnd < string.length,
			      (CharacterSet.whitespaces as NSCharacterSet).characterIsMember(string.character(at: deletionEnd))
			{
				deletionEnd += 1
			}
		}

		let collapseSlashRanges: [NSRange] = if options.contains(.collapseSlashes) {
			slashRangesToCollapse(
				in: string.substring(with: tokenRange) as NSString,
				removing: escapedSlashRanges
			)
		} else {
			[]
		}

		return QuoteToken(
			tokenRange: tokenRange,
			deletionRange: NSRange(location: 0, length: deletionEnd),
			escapedSlashRanges: escapedSlashRanges,
			collapseSlashRanges: collapseSlashRanges
		)
	}

	static func stringToken(from source: NSString, scan: QuoteToken) -> String {
		let token = NSMutableString(string: source.substring(with: scan.tokenRange))
		applyDeletions(scan.escapedSlashRanges, to: token)
		applyDeletions(scan.collapseSlashRanges, to: token)
		return token as String
	}

	static func attributedToken(from source: NSAttributedString, scan: QuoteToken) -> NSAttributedString {
		let token = NSMutableAttributedString(attributedString: source.attributedSubstring(from: scan.tokenRange))
		applyDeletions(scan.escapedSlashRanges, to: token)
		applyDeletions(scan.collapseSlashRanges, to: token)
		return NSAttributedString(attributedString: token)
	}

	private static func slashRangesToCollapse(
		in originalToken: NSString,
		removing escapedSlashRanges: [NSRange]
	) -> [NSRange] {
		let token = NSMutableString(string: originalToken)
		applyDeletions(escapedSlashRanges, to: token)

		var ranges: [NSRange] = []
		var index = 0
		while index < token.length {
			guard token.character(at: index) == backslash else {
				index += 1
				continue
			}

			let start = index
			while index < token.length, token.character(at: index) == backslash {
				index += 1
			}

			let slashCount = index - start
			let deletionLength = slashCount / 2
			if deletionLength > 0 {
				ranges.append(NSRange(location: start, length: deletionLength))
			}
		}
		return ranges
	}

	private static func applyDeletions(_ ranges: [NSRange], to string: NSMutableString) {
		for range in ranges.reversed() {
			string.deleteCharacters(in: range)
		}
	}

	private static func applyDeletions(_ ranges: [NSRange], to string: NSMutableAttributedString) {
		for range in ranges.reversed() {
			string.deleteCharacters(in: range)
		}
	}
}

public extension NSString {
	@objc(getTokenFromWhitespaceGroupWithBlock:)
	func ce_getTokenFromWhitespaceGroup(
		_ completion: (String?, NSRange, NSRange) -> Void
	) {
		guard let token = StringTokenizer.whitespaceToken(in: self) else {
			completion(nil, StringTokenizer.emptyRange, StringTokenizer.emptyRange)
			return
		}
		completion(token.value, token.tokenRange, token.deletionRange)
	}

	@objc(getTokenFromQuoteGroupWithBlock:options:)
	func ce_getTokenFromQuoteGroup(
		_ completion: (String?, NSRange, NSRange) -> Void,
		options: UInt
	) {
		guard let scan = StringTokenizer.quoteToken(in: self, rawOptions: options) else {
			completion(nil, StringTokenizer.emptyRange, StringTokenizer.emptyRange)
			return
		}
		completion(StringTokenizer.stringToken(from: self, scan: scan), scan.tokenRange, scan.deletionRange)
	}

	@objc(trimAndGetFirstToken)
	var ceTrimAndGetFirstToken: String {
		let trimmed = trimmingCharacters(in: .whitespacesAndNewlines) as NSString
		return StringTokenizer.whitespaceToken(in: trimmed)?.value ?? ""
	}
}

public extension NSMutableString {
	@objc(getTokenInsideQuotes)
	var ceTokenInsideQuotes: String {
		guard let scan = StringTokenizer.quoteToken(in: self, rawOptions: 0) else {
			return ""
		}
		let token = StringTokenizer.stringToken(from: self, scan: scan)
		deleteCharacters(in: scan.deletionRange)
		return token
	}

	@objc(getToken)
	var ceToken: String {
		guard let token = StringTokenizer.whitespaceToken(in: self) else {
			return ""
		}
		deleteCharacters(in: token.deletionRange)
		return token.value
	}

	@objc(lowercaseGetToken)
	var ceLowercaseToken: String {
		ceToken.lowercased()
	}

	@objc(uppercaseGetToken)
	var ceUppercaseToken: String {
		ceToken.uppercased()
	}
}

public extension NSAttributedString {
	@objc(getTokenFromWhitespaceGroupWithBlock:)
	func ce_getTokenFromWhitespaceGroup(
		_ completion: (String?, NSRange, NSRange) -> Void
	) {
		guard let token = StringTokenizer.whitespaceToken(in: string as NSString) else {
			completion(nil, StringTokenizer.emptyRange, StringTokenizer.emptyRange)
			return
		}
		completion(token.value, token.tokenRange, token.deletionRange)
	}

	@objc(getTokenFromQuoteGroupWithBlock:options:)
	func ce_getTokenFromQuoteGroup(
		_ completion: (NSAttributedString?, NSRange, NSRange) -> Void,
		options: UInt
	) {
		guard let scan = StringTokenizer.quoteToken(in: string as NSString, rawOptions: options) else {
			completion(nil, StringTokenizer.emptyRange, StringTokenizer.emptyRange)
			return
		}
		completion(StringTokenizer.attributedToken(from: self, scan: scan), scan.tokenRange, scan.deletionRange)
	}
}

public extension NSMutableAttributedString {
	@objc(getTokenAsString)
	var ceTokenAsString: String {
		consumeWhitespaceToken(asAttributedString: false) as? String ?? ""
	}

	@objc(lowercaseGetToken)
	var ceLowercaseToken: String {
		ceTokenAsString.lowercased()
	}

	@objc(uppercaseGetToken)
	var ceUppercaseToken: String {
		ceTokenAsString.uppercased()
	}

	@objc(getToken)
	var ceToken: NSAttributedString {
		consumeWhitespaceToken(asAttributedString: true) as? NSAttributedString
			?? NSAttributedString(string: "")
	}

	@objc(getTokenInsideQuotes)
	var ceTokenInsideQuotes: NSAttributedString {
		guard let scan = StringTokenizer.quoteToken(in: string as NSString, rawOptions: 0) else {
			return NSAttributedString(string: "")
		}
		let token = StringTokenizer.attributedToken(from: self, scan: scan)
		deleteCharacters(in: scan.deletionRange)
		return token
	}

	private func consumeWhitespaceToken(asAttributedString: Bool) -> Any {
		guard let scan = StringTokenizer.whitespaceToken(in: string as NSString) else {
			return asAttributedString ? NSAttributedString(string: "") : ""
		}

		let attributedToken = attributedSubstring(from: scan.tokenRange)
		deleteCharacters(in: scan.deletionRange)
		return asAttributedString ? attributedToken : scan.value
	}
}
