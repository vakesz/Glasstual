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

import AppKit
import Foundation
import os

/// A hyperlink located inside a string by `LinkParser`.
///
/// It is attached to rendered text under ``RendererFormatting/url`` and
/// travels on a `TranscriptBody` from the render pipeline back to the main
/// actor. A value rather than an object, so the rendered line that carries it
/// really is the value its own marker claims.
nonisolated struct LinkParserResult: Sendable, Hashable { // nonisolated: value
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

/** Which schemes beyond the built-in ones the reader allows.

 The declarations keep the key names the AutoHyperlinks framework that preceded
 this parser used, so a user customization carries over. */
nonisolated struct LinkSchemePolicy: Sendable { // nonisolated: value
	var permitsAnyScheme = false
	var permittedSchemes: Set<String> = []

	/// The allowlist the reader's preferences describe right now.
	@MainActor static func current() -> LinkSchemePolicy {
		LinkSchemePolicy(
			permitsAnyScheme: Preferences.LinkSchemes.permitAny.value,
			permittedSchemes: Set(Preferences.LinkSchemes.permittedDefault.value)
				.union(Preferences.LinkSchemes.permitted.value)
		)
	}
}

nonisolated enum LinkParser { // nonisolated: value
	/// Locates hyperlinks in `string`.
	///
	/// Results are sorted by location and never overlap.
	///
	/// - Parameters:
	///   - string: The text to scan.
	///   - policy: The reader's scheme customization, taken on the main actor.
	static func locateLinks(in string: String, allowing policy: LinkSchemePolicy) -> [LinkParserResult] {
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

			if explicitScheme, isPermittedScheme(scheme, allowing: policy) == false {
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

	/// The two schemes a link the app opens itself is written in.
	static let webSchemes: Set<String> = ["http", "https"]

	/// The app's own schemes, which a link may carry back into the app.
	static let appSchemes: Set<String> = ["glasstual", "textual"]

	/// Schemes that are always linked, regardless of user preferences.
	private static let builtInSchemes: Set<String> = webSchemes.union([
		"xmpp",
		"rdar", "radr", "radar", "x-radar",
		"spotify", "dict", "magnet", "message",
	])

	/** Schemes that hand a remote peer's string to the file system, a network
	 mount, a system settings pane or an interpreter. They are refused ahead of
	 the user customization keys below so that a permissive `permitsAnyScheme`
	 cannot re-enable them. */
	private static let deniedSchemes: Set<String> = [
		"file",
		"smb", "afp", "nfs", "cifs",
		"x-apple.systempreferences",
		"javascript", "data", "vbscript", "blob", "filesystem", "about",
	]

	/// Whether `url` addresses a host over HTTP(S), which is the only shape an
	/// inline image may be fetched from.
	static func isWebURL(_ url: URL) -> Bool {
		webSchemes.contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
	}

	/// Whether the app hands `url` straight to the system rather than offering
	/// it to a channel- or nickname-specific action first.
	static func opensDirectly(_ url: URL) -> Bool {
		let scheme = url.scheme?.lowercased() ?? ""
		return webSchemes.contains(scheme) || appSchemes.contains(scheme)
	}

	/// Whether a scheme may be linked, and may be handed to `NSWorkspace`.
	///
	/// - Parameters:
	///   - scheme: A URL scheme, without the trailing colon.
	///   - policy: The reader's scheme customization, taken on the main actor.
	static func isPermittedScheme(_ scheme: String, allowing policy: LinkSchemePolicy) -> Bool {
		let scheme = scheme.lowercased()

		if deniedSchemes.contains(scheme) {
			return false
		}

		if builtInSchemes.contains(scheme) {
			return true
		}

		return policy.permitsAnyScheme || policy.permittedSchemes.contains(scheme)
	}

	/** The same answer for a caller that is already on the main actor and so can
	 read the live preferences itself — opening a clicked link, drawing a topic. */
	@MainActor
	static func isPermittedScheme(_ scheme: String) -> Bool {
		isPermittedScheme(scheme, allowing: .current())
	}

	/// The same answer for a whole address, which is what a rendered run and a
	/// drawn topic carry.
	static func isPermittedLink(_ location: String, allowing policy: LinkSchemePolicy) -> Bool {
		guard let url = URL(string: location), let scheme = url.scheme else { return false }
		return isPermittedScheme(scheme, allowing: policy)
	}

	@MainActor
	static func isPermittedLink(_ location: String) -> Bool {
		isPermittedLink(location, allowing: .current())
	}

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

private let openLinkLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "OpenLink"
)

enum OpenLink {
	/** Hands a URL the allowlist has already cleared to the system.

	 `NSWorkspace` launches whatever app has registered the scheme, so this is
	 the last step of a launch a remote peer asked for. It is a stored value
	 rather than a call so that ``opener`` can stand somewhere else in a test. */
	static let workspaceOpener: @MainActor (URL, Bool) -> Void = { url, inBackground in
		guard inBackground else {
			NSWorkspace.shared.open(url)

			return
		}

		/* User should not be clicking links frequently enough that
		 we need to worry about making the configuration static. */
		let configuration = NSWorkspace.OpenConfiguration()
		configuration.activates = false

		NSWorkspace.shared.open(url, configuration: configuration)
	}

	/** Where a URL goes once ``open(url:inBackground:)`` has cleared it.

	 The guard in front of this is the only thing between a string a stranger
	 typed in a channel and an app launch on this machine, so a test has to be
	 able to prove that the guard refuses what it should and passes what it
	 should -- without asking the real workspace to open `file:///etc/passwd` to
	 find out. Tests substitute their own opener and restore
	 ``workspaceOpener``; nothing in the app replaces it. */
	static var opener = workspaceOpener

	static func open(url: URL, inBackground: Bool = Preferences.Messages.openBrowserInBackground.value) {
		/* Links come from other people. `NSWorkspace` launches whatever app has
		 registered the scheme, so the same allowlist that decides what becomes
		 clickable also decides what may be opened: no caller is trusted to have
		 filtered already. */
		guard let scheme = url.scheme, LinkParser.isPermittedScheme(scheme) else {
			openLinkLogger.info("Refused to open URL with scheme '\(url.scheme ?? "(none)", privacy: .public)'")

			return
		}

		opener(url, inBackground)
	}

	static func open(string: String, inBackground: Bool = Preferences.Messages.openBrowserInBackground.value) {
		guard let urlToOpen = URL(string: string) else {
			return
		}

		open(url: urlToOpen, inBackground: inBackground)
	}
}
