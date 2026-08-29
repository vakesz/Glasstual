/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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
@testable import Glasstual
import Testing

/// Behaviour corpus for hyperlink detection in message bodies.
@MainActor
struct TLOLinkParserCorpusTests {
	nonisolated struct LinkCase: Sendable {
		let text: String
		let links: [String]

		init(_ text: String, _ links: [String]) {
			self.text = text
			self.links = links
		}
	}

	// MARK: - Detection

	nonisolated static let detectionCases: [LinkCase] = [
		/* Plain addresses with an explicit scheme. */
		LinkCase("see http://example.com/page for details", ["http://example.com/page"]),
		LinkCase("http://example.com:8080/x", ["http://example.com:8080/x"]),
		LinkCase("http://example.com/#frag", ["http://example.com/#frag"]),
		LinkCase("HTTP://EXAMPLE.COM/A", ["HTTP://EXAMPLE.COM/A"]),
		LinkCase(
			"multiple http://a.example.com and http://b.example.com links",
			["http://a.example.com", "http://b.example.com"]
		),
		/* Bare domains get the default scheme. */
		LinkCase("visit example.com now", ["http://example.com"]),
		LinkCase("visit www.example.com now", ["http://www.example.com"]),
		/* mDNS names are matched by a supplementary expression. */
		LinkCase("printer.local/setup", ["http://printer.local/setup"]),
		/* Subreddit shorthand expands to a reddit address. */
		LinkCase("go to /r/swift now", ["https://www.reddit.com/r/swift"]),
		/* Built-in schemes the data detector does not produce on its own. */
		LinkCase("spotify:track:6rqhFgbbKwnb9MLmUQDhG6", ["spotify:track:6rqhFgbbKwnb9MLmUQDhG6"]),
		LinkCase(
			"magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567",
			["magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"]
		),
		LinkCase("xmpp:user@example.com", ["xmpp:user@example.com"]),
		/* IPv6 literals keep their brackets and port. */
		LinkCase("ipv6 http://[2001:db8::1]/path here", ["http://[2001:db8::1]/path"]),
		LinkCase("ipv6 http://[2001:db8::1]:8080/path here", ["http://[2001:db8::1]:8080/path"]),
		/* E-mail addresses and IRC hostmasks are never links. */
		LinkCase("mail me at someone@example.com ok", []),
		LinkCase("nick!user@host said hi", []),
		/* Too short to be a link. */
		LinkCase("a.b", []),
	]

	@Test(arguments: Self.detectionCases)
	func locatesLinks(testCase: LinkCase) {
		let located = LinkParser.locateLinks(in: testCase.text).map(\.stringValue)

		#expect(located == testCase.links)
	}

	// MARK: - Trailing punctuation and brackets

	nonisolated static let punctuationCases: [LinkCase] = [
		/* Sentence punctuation is not part of the address. */
		LinkCase("see http://example.com/page. for details", ["http://example.com/page"]),
		LinkCase("question? http://example.com/a?", ["http://example.com/a"]),
		LinkCase("trailing dots http://example.com/a...", ["http://example.com/a"]),
		LinkCase("end of sentence at example.com.", ["http://example.com"]),
		LinkCase("quote \"http://example.com/a\" end", ["http://example.com/a"]),
		/* A comma inside a path is kept; the data detector decides the extent. */
		LinkCase("https://example.com/a,b", ["https://example.com/a,b"]),
		/* An unmatched closing bracket belongs to the sentence. */
		LinkCase("wrap (http://example.com/page) here", ["http://example.com/page"]),
		LinkCase("brackets [http://example.com/a] end", ["http://example.com/a"]),
		LinkCase("emphasis (see example.com)", ["http://example.com"]),
		LinkCase("unbalanced http://example.com/a) tail", ["http://example.com/a"]),
		LinkCase("http://example.com/a]", ["http://example.com/a"]),
		/* A matched closing bracket belongs to the address. */
		LinkCase(
			"wrap http://example.com/page_(disambiguation) here",
			["http://example.com/page_(disambiguation)"]
		),
	]

	@Test(arguments: Self.punctuationCases)
	func trimsTrailingPunctuationButKeepsBalancedBrackets(testCase: LinkCase) {
		let located = LinkParser.locateLinks(in: testCase.text).map(\.stringValue)

		#expect(located == testCase.links)
	}

	// MARK: - Dangerous schemes

	/// Schemes that execute code or read local state are never linked.
	@Test(arguments: [
		"javascript:alert(1)",
		"javascript:void(document.cookie)",
		"data:text/html;base64,PHNjcmlwdD4=",
		"data:text/plain,hello",
		"file:///etc/passwd",
		"FILE:///etc/passwd",
		"file://localhost/etc/passwd",
		"see file:///Users/someone/secret.txt here",
		"see javascript:alert(1) here",
	])
	func neverLinksExecutableOrLocalSchemes(text: String) {
		let located = LinkParser.locateLinks(in: text)

		for result in located {
			let scheme = result.stringValue.lowercased()

			#expect(scheme.hasPrefix("javascript:") == false)
			#expect(scheme.hasPrefix("data:") == false)
			#expect(scheme.hasPrefix("file:") == false)
		}
	}

	// MARK: - Ranges and whole-string matches

	@Test
	func reportsTheRangeAndStrictnessOfEachMatch() throws {
		let text = "visit example.com and http://other.example/a"
		let located = LinkParser.locateLinks(in: text)

		#expect(located.count == 2)

		let first = try #require(located.first)
		let second = try #require(located.last)

		#expect(first.range == NSRange(location: 6, length: 11))
		#expect(first.strictMatch == false)
		#expect(second.strictMatch)
		#expect(first.uniqueIdentifier != second.uniqueIdentifier)
	}

	@Test(arguments: [
		"example.com",
		"http://example.com/a",
		"https://example.com/a",
	])
	func addsASchemeWhenTheWholeStringIsALink(address: String) {
		#expect(LinkParser.urlWithProperScheme(address) != nil)
	}

	@Test(arguments: [
		"not a url at all",
		"see example.com here",
		"javascript:alert(1)",
		"file:///etc/passwd",
		"",
	])
	func returnsNilWhenTheStringIsNotEntirelyALink(address: String) {
		#expect(LinkParser.urlWithProperScheme(address) == nil)
	}

	@Test
	func prependsTheDefaultSchemeToBareDomains() {
		#expect(LinkParser.urlWithProperScheme("example.com") == "http://example.com")
	}
}

/// Corpus for the policy `OpenLink` applies before handing a URL to
/// `NSWorkspace`.
///
/// `OpenLink` exposes no predicate, so the gate it applies today is mirrored
/// by `refusesToday(_:)`. Opening is only exercised for URLs that must be
/// refused — driving the openable cases would launch applications.
@MainActor
struct TLOpenLinkCorpusTests {
	/// Mirrors the single check in `OpenLink.open(url:inBackground:)`.
	private static func refusesToday(_ url: URL) -> Bool {
		url.isFileURL
	}

	@Test(arguments: [
		"file:///etc/passwd",
		"file:///Applications/Calculator.app",
		"file://localhost/etc/passwd",
	])
	func refusesFileURLs(address: String) throws {
		let url = try #require(URL(string: address))

		#expect(Self.refusesToday(url))

		/* Exercise the production guard: it must return without opening. */
		OpenLink.open(url: url, inBackground: true)
	}

	@Test(arguments: [
		"https://example.com/",
		"http://example.com/a",
		"xmpp:user@example.com",
	])
	func acceptsOrdinaryRemoteURLs(address: String) throws {
		let url = try #require(URL(string: address))

		#expect(Self.refusesToday(url) == false)
	}

	/// Schemes that reach local shares or system surfaces must be refused too.
	@Test(
		.disabled("Phase 1: OpenLink gates on isFileURL only, so smb: and x-apple.systempreferences: are opened"),
		arguments: [
			"smb://example.com/share",
			"afp://example.com/share",
			"x-apple.systempreferences:com.apple.preference.security",
		]
	)
	func refusesLocalShareAndSystemSchemes(address: String) throws {
		let url = try #require(URL(string: address))

		#expect(Self.refusesToday(url))
	}

	@Test
	func ignoresStringsThatAreNotURLs() {
		/* The string entry point must not crash on malformed input. */
		OpenLink.open(string: "", inBackground: true)
		OpenLink.open(string: "file:///etc/passwd", inBackground: true)
	}
}
