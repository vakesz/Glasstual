/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
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

import Foundation

/// A hyperlink located inside a string by `LinkParser`.
///
/// This is the object exposed to plugins through `THOPluginDidPostNewMessageConcreteObject`
/// and attached to rendered text as `TVCLogRendererFormattingURLAttribute`.
///
/// `Sendable` because every stored property is an immutable value: a rendered
/// line carries its links from the render pipeline back to the main actor, and
/// a checked conformance has to be declared beside the type it applies to.
@objc(TLOLinkParserResult)
public final nonisolated class LinkParserResult: NSObject, Sendable {
	/// Random identifier that is unique to this result.
	@objc public let uniqueIdentifier: String

	/// The address of the link including its scheme.
	///
	/// Scheme-less matches (such as `example.com`) are prefixed with `http://`.
	@objc public let stringValue: String

	/// The range of the match in the string that was scanned.
	@objc public let range: NSRange

	/// `true` when the match carried an explicit scheme.
	///
	/// `false` for matches that were inferred from a bare domain name.
	@objc public let strictMatch: Bool

	init(stringValue: String, range: NSRange, strictMatch: Bool) {
		uniqueIdentifier = UUID().uuidString
		self.stringValue = stringValue
		self.range = range
		self.strictMatch = strictMatch
	}
}

@objc(TLOLinkParser)
public nonisolated class LinkParser: NSObject {
	/// Locates hyperlinks in `string`.
	///
	/// Results are sorted by location and never overlap.
	@objc(locateLinksInString:)
	public static func locateLinks(in string: String) -> [LinkParserResult] {
		let scanString = string as NSString

		let fullRange = NSRange(location: 0, length: scanString.length)

		if fullRange.length < minimumLength {
			return []
		}

		var candidates: [(range: NSRange, hasScheme: Bool)] = []

		for match in linkDetector.matches(in: string, range: fullRange) {
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

			if explicitScheme, isPermittedScheme(scheme) == false {
				continue
			}

			candidates.append((match.range, explicitScheme))
		}

		for (expression, hasScheme) in supplementaryExpressions {
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

			results.append(LinkParserResult(stringValue: stringValue, range: range, strictMatch: candidate.hasScheme))
		}

		return results
	}

	/// Returns `string` with a scheme prepended when it is a URL in its entirety,
	/// or `nil` when the string is not a URL.
	@objc(URLWithProperScheme:)
	public static func urlWithProperScheme(_ string: String) -> String? {
		let fullRange = NSRange(location: 0, length: (string as NSString).length)

		guard let result = locateLinks(in: string).first, NSEqualRanges(result.range, fullRange) else {
			return nil
		}

		return result.stringValue
	}

	@objc
	public static let bannedLineTypes =
		[
			LogLine.string(for: .mode),
			LogLine.string(for: .join),
			LogLine.string(for: .nick),
			LogLine.string(for: .invite),
		].compactMap(\.self)

	// MARK: - Configuration

	private static let minimumLength = 4

	private static let defaultScheme = "http://"

	private static let redditPrefix = "/r/"
	private static let redditBase = "https://www.reddit.com"

	/// Schemes that are always linked, regardless of user preferences.
	private static let builtInSchemes: Set<String> = [
		"http", "https",
		"xmpp",
		"rdar", "radr", "radar", "x-radar",
		"spotify", "dict", "magnet", "message",
	]

	/** Schemes that hand a remote peer's string to the file system, a network
	 mount or a system settings pane. They are refused ahead of the user
	 customization keys below so that a permissive `permittedSchemesAny`
	 cannot re-enable them. */
	private static let deniedSchemes: Set<String> = [
		"file",
		"smb", "afp", "nfs", "cifs",
		"x-apple.systempreferences",
	]

	/// Whether a scheme may be linked, and may be handed to `NSWorkspace`.
	///
	/// - Parameter scheme: A URL scheme, without the trailing colon.
	static func isPermittedScheme(_ scheme: String) -> Bool {
		let scheme = scheme.lowercased()

		if deniedSchemes.contains(scheme) {
			return false
		}

		if builtInSchemes.contains(scheme) {
			return true
		}

		/* The declarations keep the key names the AutoHyperlinks framework that
		 preceded this parser used, so a user customization carries over. */
		if Preferences.LinkSchemes.permitAny.value {
			return true
		}

		return Preferences.LinkSchemes.permittedDefault.value.contains(scheme)
			|| Preferences.LinkSchemes.permitted.value.contains(scheme)
	}

	private static let linkDetector: NSDataDetector = {
		do {
			return try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
		} catch {
			fatalError("NSDataDetector could not be created: \(error)")
		}
	}()

	/// Matches that `NSDataDetector` does not produce on its own,
	/// paired with whether the match carries a scheme.
	private static let supplementaryExpressions: [(NSRegularExpression, Bool)] = {
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

		return patterns.compactMap { pattern, hasScheme in
			guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
				return nil
			}

			return (expression, hasScheme)
		}
	}()

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
