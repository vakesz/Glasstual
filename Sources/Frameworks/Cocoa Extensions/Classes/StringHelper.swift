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

/* A portion of this source file contains copyrighted work derived from one or
 more 3rd party, open source projects. The use of this work is hereby
 acknowledged. */

/*
 The New BSD License

 Copyright (c) 2008 - 2010 Satoshi Nakagawa < psychs AT limechat DOT net >
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 SUCH DAMAGE.
 */

import Foundation

public let unicodeReplacementCharacter = "\u{FFFD}"

/// `NAME_MAX` on APFS and HFS+.
private let maximumFilenameBytes = 255

/// Space characters that IRC peers use interchangeably with U+0020.
private let spaceLikeScalars: CharacterSet = {
	var set = CharacterSet()
	set.insert("\u{00A0}")
	set.insert(charactersIn: "\u{2002}" ... "\u{200A}")
	set.insert("\u{202F}")
	set.insert("\u{205F}")
	set.insert("\u{3000}")
	set.insert("\u{E0020}")
	return set
}()

public extension String {
	/// The receiver reduced to something safe to use as a single path component.
	///
	/// Filenames arrive from remote peers over DCC and from user-set client and
	/// channel names. Anything that could redirect the write (path separators,
	/// `.`, `..`, a leading dot) or that the file system cannot hold (control
	/// and format characters, more than `NAME_MAX` bytes) is substituted or cut
	/// rather than passed through.
	var safeFilename: String {
		guard !isEmpty else {
			return self
		}

		let disallowed = CharacterSet(charactersIn: "/:").union(.controlCharacters)
		let substituted = trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map {
			disallowed.contains($0) ? Unicode.Scalar("_") : $0
		}

		var result = String(String.UnicodeScalarView(substituted))

		let leadingDots = result.prefix { $0 == "." }.count

		if leadingDots > 0 {
			result = String(repeating: "_", count: leadingDots) + result.dropFirst(leadingDots)
		}

		return result.truncated(toUTF8Bytes: maximumFilenameBytes)
	}

	/// The receiver with zero-width spaces removed and every other space-like
	/// scalar folded to U+0020.
	var normalizingSpaces: String {
		guard !isEmpty else {
			return self
		}

		var result = String.UnicodeScalarView()

		for scalar in unicodeScalars where scalar != "\u{200B}" {
			result.append(spaceLikeScalars.contains(scalar) ? " " : scalar)
		}

		return String(result)
	}

	/// The receiver's standardized path with the user's home directory replaced
	/// by `~`. A path outside the home directory is returned unchanged.
	var standardizedTildePath: String {
		let homeDirectory = FileManager.pathOfHomeDirectoryOutsideSandbox
		let standardized = (self as NSString).standardizingPath

		guard standardized.hasPrefix(homeDirectory) else {
			return self
		}

		let remainder = standardized.dropFirst(homeDirectory.count)

		if remainder.isEmpty {
			return "~"
		}

		guard remainder.hasPrefix("/") else {
			return standardized
		}

		return "~" + remainder
	}

	/// Percent encoding that keeps only the unreserved URI characters.
	var percentEncoded: String? {
		addingPercentEncoding(withAllowedCharacters: .textualPercentEncoded)
	}

	func onlyContainsCharacters(from characterSet: CharacterSet) -> Bool {
		unicodeScalars.allSatisfy(characterSet.contains)
	}

	/// How well `word` matches the receiver, for ranking channel-name searches.
	///
	/// The score is the number of matched characters, less a penalty for gaps
	/// between them and `weight` times the share of the receiver left over.
	/// Zero means "no match".
	func matchScore(against word: String, lengthPenaltyWeight weight: CGFloat) -> CGFloat {
		let source = Array(lowercased())
		let candidate = Array(word.lowercased())

		guard !candidate.isEmpty, candidate.count <= source.count else {
			return 0
		}

		var commonCharacterCount = 0
		var startPosition = 0
		var distancePenalty: CGFloat = 0

		for character in candidate {
			guard let matchPosition = source[startPosition...].firstIndex(of: character) else {
				return 0
			}

			let distance = matchPosition - startPosition

			if distance > 0 {
				distancePenalty += CGFloat(distance - 1) / CGFloat(distance)
			}

			commonCharacterCount += 1
			startPosition = matchPosition + 1
		}

		let lengthPenalty = 1 - CGFloat(candidate.count) / CGFloat(source.count)
		return CGFloat(commonCharacterCount) - distancePenalty - weight * lengthPenalty
	}

	/// The range of each character of `characters`, searched for in order with
	/// each search starting where the previous match ended. Scanning stops at
	/// the first character that is not found.
	///
	/// Ranges are UTF-16 offsets because the only consumer applies attributes
	/// to an `NSAttributedString` built from the receiver.
	func rangesOfFirstOccurrences(
		ofCharactersIn characters: String,
		options: NSString.CompareOptions
	) -> [NSRange] {
		let source = self as NSString

		guard source.length > 0 else {
			return []
		}

		var ranges: [NSRange] = []
		var currentPosition = 0

		for character in characters {
			let range = source.range(
				of: String(character),
				options: options,
				range: NSRange(location: currentPosition, length: source.length - currentPosition)
			)

			guard range.location != NSNotFound else {
				break
			}

			ranges.append(range)
			currentPosition = NSMaxRange(range)
		}

		return ranges
	}

	/// The longest prefix of the receiver that fits in `limit` UTF-8 bytes
	/// without splitting a character.
	func truncated(toUTF8Bytes limit: Int) -> String {
		guard utf8.count > limit else {
			return self
		}

		var result = ""
		var byteCount = 0

		for character in self {
			let width = String(character).utf8.count

			guard byteCount + width <= limit else {
				break
			}

			result.append(character)
			byteCount += width
		}

		return result
	}
}

public extension String.Encoding {
	/// Every encoding the system supports, keyed by its localized name.
	///
	/// Values stay `NSNumber` because the caller stores them as menu item tags
	/// and looks titles back up through `NSDictionary`.
	static func supportedEncodingsByTitle(favoringUTF8: Bool) -> [String: NSNumber] {
		var result: [String: NSNumber] = [:]

		for encoding in supportedEncodings(favoringUTF8: favoringUTF8) {
			result[String.localizedName(of: Self(rawValue: encoding.uintValue))] = encoding
		}

		return result
	}

	static func supportedEncodings(favoringUTF8: Bool) -> [NSNumber] {
		var result: [NSNumber] = []

		if favoringUTF8 {
			result.append(NSNumber(value: Self.utf8.rawValue))
		}

		for encoding in String.availableStringEncodings where !favoringUTF8 || encoding != .utf8 {
			result.append(NSNumber(value: encoding.rawValue))
		}

		return result
	}

	/// The IANA character set name for a raw `String.Encoding` value, e.g.
	/// "utf-8". `nil` when the encoding has no registered name.
	static func ianaCharsetName(forRawValue rawValue: UInt) -> String? {
		let coreFoundationEncoding = CFStringConvertNSStringEncodingToEncoding(rawValue)
		return CFStringConvertEncodingToIANACharSetName(coreFoundationEncoding) as String?
	}
}

public extension NSAttributedString {
	/// The receiver broken on newlines, with the newlines discarded. A string
	/// with no newline in it comes back as a single element.
	var splitIntoLines: [NSAttributedString] {
		guard length > 0 else {
			return []
		}

		let sourceString = string as NSString
		var result: [NSAttributedString] = []
		var lineStart = 0

		while lineStart < sourceString.length {
			let searchRange = NSRange(location: lineStart, length: sourceString.length - lineStart)
			let newlineRange = sourceString.rangeOfCharacter(from: .newlines, options: [], range: searchRange)

			guard newlineRange.location != NSNotFound else {
				break
			}

			result.append(attributedSubstring(from: NSRange(
				location: lineStart,
				length: newlineRange.location - lineStart
			)))
			lineStart = NSMaxRange(newlineRange)
		}

		guard !result.isEmpty else {
			return [self]
		}

		if lineStart < sourceString.length {
			result.append(attributedSubstring(from: NSRange(
				location: lineStart,
				length: sourceString.length - lineStart
			)))
		}

		return result
	}

	/// The receiver from `index` (a UTF-16 offset) to its end.
	func attributedSubstring(fromIndex index: Int) -> NSAttributedString {
		attributedSubstring(from: NSRange(location: index, length: length - index))
	}
}
