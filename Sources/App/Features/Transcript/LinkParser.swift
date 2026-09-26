// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// A hyperlink located inside a string by `LinkParser`.
///
/// It is attached to rendered text under ``RendererFormatting/url`` and
/// travels on a `TranscriptBody` from the render pipeline back to the main
/// actor. A value rather than an object, so the rendered line that carries it
/// really is the value its own marker claims.
nonisolated struct LinkParserResult: Sendable, Hashable {
	/// Random identifier that is unique to this result.
	let uniqueIdentifier: String

	/// The address of the link including its scheme.
	///
	/// Scheme-less matches (such as `example.com`) are prefixed with `http://`.
	let stringValue: String

	/// The range of the match in the string that was scanned.
	let range: NSRange

	init(stringValue: String, range: NSRange) {
		uniqueIdentifier = UUID().uuidString
		self.stringValue = stringValue
		self.range = range
	}
}

/** The expressions ``LinkParser`` scans with.

 `NSDataDetector` and `NSRegularExpression` are references, so a value cannot
 hold them and go on calling itself one. They are built once, never mutated,
 and Foundation matches with them from any thread, which is what a holder of
 `let`s says. */
private final nonisolated class LinkParserExpressions: Sendable { // nonisolated: immutable
	static let shared = LinkParserExpressions()

	let detector: NSDataDetector
	/// Matches that `NSDataDetector` does not produce on its own, paired with
	/// whether the match carries a scheme.
	let supplementary: [(expression: NSRegularExpression, hasScheme: Bool)]

	private init() {
		do {
			detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
		} catch {
			fatalError("NSDataDetector could not be created: \(error)")
		}
		let patterns: [(String, Bool)] = [
			/* spotify:track:<id> */
			("(?<!\\S)spotify:(?:track|album|artist|search|playlist|user|radio):[^\\s<>]+", true),
			/* magnet:?xt=urn:btih:<hash> */
			("(?<!\\S)magnet:\\?xt=urn:(?:bitprint|btih|ed2k|md5|sha1|tree:tiger):[A-Fa-f0-9]{20,80}\\S*", true),
			/* /r/subreddit */
			("(?<!\\S)/r/[A-Za-z0-9][A-Za-z0-9_]{2,20}(?![^\\s.,;:!?)\\]}'\"])", false),
			/* host.local — mDNS names are not in the data detector's TLD list. */
			("(?<![^\\s(\\[{<\"'“‘])[\\w-]+(?:\\.[\\w-]+)*\\.local(?::\\d+)?(?:/\\S*)?", false),
		]
		supplementary = patterns.compactMap { pattern, hasScheme in
			guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
				return nil
			}
			return (expression, hasScheme)
		}
	}
}

nonisolated enum LinkParser {
	/// Locates hyperlinks in `string`.
	///
	/// Results are sorted by location and never overlap.
	///
	/// - Parameters:
	///   - string: The text to scan.
	///   - policy: The reader's scheme customization, taken on the main actor.
	static func locateLinks(in string: String, allowing policy: LinkSchemeRules) -> [LinkParserResult] {
		let scanString = string as NSString

		let fullRange = NSRange(location: 0, length: scanString.length)

		if fullRange.length < minimumLength {
			return []
		}

		var candidates: [(range: NSRange, hasScheme: Bool)] = []

		for match in LinkParserExpressions.shared.detector.matches(in: string, range: fullRange) {
			guard let url = match.url, let scheme = url.scheme?.lowercased() else {
				continue
			}

			/* The old lexer never linked e-mail addresses. IRC hostmasks
			 (nick!user@host) would otherwise turn into mailto: links. */
			if scheme == "mailto" {
				continue
			}

			let prefix = scanString.substring(with: match.range).lowercased()

			let explicitScheme = prefix.hasPrefix(scheme + ":")

			if explicitScheme, policy.permits(scheme: scheme) == false {
				continue
			}

			candidates.append((match.range, explicitScheme))
		}

		for (expression, hasScheme) in LinkParserExpressions.shared.supplementary {
			for match in expression.matches(in: string, range: fullRange) {
				candidates.append((match.range, hasScheme))
			}
		}

		candidates.sort {
			if $0.range.location != $1.range.location {
				return $0.range.location < $1.range.location
			}

			return $0.range.length > $1.range.length
		}

		var results: [LinkParserResult] = []

		var lastMaximum = 0

		for candidate in candidates {
			if candidate.range.location < lastMaximum {
				continue
			}

			let range = trimTrailingPunctuation(in: scanString, range: candidate.range)

			if range.length < minimumLength {
				continue
			}

			lastMaximum = NSMaxRange(range)

			var stringValue = scanString.substring(with: range)

			if candidate.hasScheme == false {
				stringValue = (stringValue.hasPrefix(redditPrefix) ? redditBase : defaultScheme) + stringValue
			}

			stringValue = stringValue.replacingOccurrences(of: "\"", with: "%22")

			results.append(LinkParserResult(stringValue: stringValue, range: range))
		}

		return results
	}

	/** The same scan for a caller already on the main actor, which can read the
	 reader's scheme customization itself — a topic being drawn, a link the input
	 field is completing. */
	@MainActor
	static func locateLinks(in string: String) -> [LinkParserResult] {
		locateLinks(in: string, allowing: .current())
	}

	static let bannedLineTypes =
		[
			ChatLine.string(for: .mode),
			ChatLine.string(for: .join),
			ChatLine.string(for: .nick),
			ChatLine.string(for: .invite),
		].compactMap(\.self)

	// MARK: - Configuration

	private static let minimumLength = 4

	private static let defaultScheme = "http://"

	private static let redditPrefix = "/r/"
	private static let redditBase = "https://www.reddit.com"

	// MARK: - Trimming

	private static let trailingCharacters = CharacterSet(charactersIn: "\"'“”‘’,:;>)]}–—.…?!@")

	private static let enclosures: [unichar: unichar] = [
		unichar(UInt8(ascii: ")")): unichar(UInt8(ascii: "(")),
		unichar(UInt8(ascii: "]")): unichar(UInt8(ascii: "[")),
		unichar(UInt8(ascii: "}")): unichar(UInt8(ascii: "{")),
	]

	/// Removes punctuation from the end of `range` that is unlikely to be part of the link.
	///
	/// A closing bracket is only removed when it has no matching opening bracket inside the range.
	private static func trimTrailingPunctuation(in string: NSString, range: NSRange) -> NSRange {
		var range = range

		while range.length > 1 {
			let character = string.character(at: NSMaxRange(range) - 1)

			guard let scalar = Unicode.Scalar(character), trailingCharacters.contains(scalar) else {
				break
			}

			if let opener = enclosures[character],
			   isBalanced(opener: opener, closer: character, in: string, range: range)
			{
				break
			}

			range.length -= 1
		}

		return range
	}

	private static func isBalanced(opener: unichar, closer: unichar, in string: NSString, range: NSRange) -> Bool {
		var depth = 0

		for index in range.location ..< NSMaxRange(range) {
			let character = string.character(at: index)

			if character == opener {
				depth += 1
			} else if character == closer {
				depth -= 1
			}
		}

		return depth >= 0
	}
}
