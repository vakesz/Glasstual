// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** The prefilter in front of link detection may never hide a link the full
 scan finds, so every claim here is checked against the full scan itself. */
@MainActor
struct LinkParserPrefilterTests {
	private struct Located: Equatable {
		let value: String
		let location: Int
		let length: Int

		init(_ result: LinkParserResult) {
			value = result.stringValue
			location = result.range.location
			length = result.range.length
		}
	}

	private static func located(_ results: [LinkParserResult]) -> [Located] {
		results.map(Located.init)
	}

	private static let policies = [LinkSchemeRules(), LinkSchemeRules(permitsAnyScheme: true)]

	/// Every string the existing corpus and punctuation suites use, plus lines
	/// that look link-like without being one.
	private static var corpusTexts: [String] {
		let corpus = (LinkParserCorpusTests.detectionCases + LinkParserCorpusTests.punctuationCases).map(\.text)
		return corpus + [
			"nothing to see here at all",
			"user@host without a dot",
			"nick!user@host.example said hi",
			"call +1 555 0100 now",
			"the version is 1.2.3 today",
			"e.g. this and that",
			"http//missing.colon and www missing dot",
			"example。com and example．com and ｅｘａｍｐｌｅ｡ｃｏｍ",
			"https://example.com/path?q=1&r=2#frag",
			"irc://irc.example.net/#channel",
			"mailto:someone@example.com",
			"a.b",
			"ab:",
			"/r/ab",
		]
	}

	@Test("The prefilter returns exactly what the full scan returns over the link corpus")
	func prefilterMatchesFullScanOnTheCorpus() {
		for text in Self.corpusTexts {
			for policy in Self.policies {
				let filtered = Self.located(LinkParser.locateLinks(in: text, allowing: policy))
				let full = Self.located(LinkParser.scan(text, allowing: policy))
				#expect(filtered == full, "prefilter changed the result for \(text.debugDescription)")
			}
		}
	}

	@Test("A line without a dot, colon or slash is not scanned and has no link")
	func linesWithoutLinkCharactersAreSkipped() {
		for text in ["plain words only", "nick!user@host", "version 123", "naïve café ünïcode", "tab\tand\nnewline here"] {
			#expect(LinkParser.canContainLink(text) == false)
			#expect(LinkParser.scan(text, allowing: LinkSchemeRules()).isEmpty)
			#expect(LinkParser.locateLinks(in: text, allowing: LinkSchemeRules()).isEmpty)
		}
		for text in ["a.b", "a:b", "a/b", "see example.com"] {
			#expect(LinkParser.canContainLink(text))
		}
	}

	/** No character other than `.`, `:` and `/` can make the scan find a link.
	 Each scalar is substituted into templates that otherwise contain none of the
	 three, and any template that yields a link must have been let through. */
	@Test("No BMP scalar other than dot, colon and slash can produce a link on its own", .timeLimit(.minutes(10)))
	func onlyTheThreeCharactersProduceLinks() {
		let templates: [(String) -> String] = [
			{ "abc\($0)def\($0)ghi" },
			{ "www\($0)example\($0)com" },
			{ "http\($0)\($0)example\($0)com" },
			{ "user\($0)host\($0)com" },
			{ "abc\($0)abc\($0)local" },
			{ "go \($0)r\($0)swift now" },
			{ "spotify\($0)track\($0)6rqhFgbbKwnb9MLmUQDhG6" },
			{ "a\($0)b\($0)c\($0)d\($0)e" },
		]
		var missed: [String] = []
		for value in UInt32(0) ... 0xFFFF {
			guard let scalar = Unicode.Scalar(value) else { continue }
			let character = String(Character(scalar))
			for template in templates {
				let text = template(character)
				guard LinkParser.canContainLink(text) == false else { continue }
				if LinkParser.scan(text, allowing: LinkSchemeRules(permitsAnyScheme: true)).isEmpty == false {
					missed.append(String(format: "U+%04X %@", value, text))
				}
			}
		}
		#expect(missed.isEmpty, "the prefilter would hide links made with: \(missed.prefix(10))")
	}

	@Test("A seeded fuzz over link-like text never differs from the full scan", .timeLimit(.minutes(5)))
	func fuzzNeverDiffersFromTheFullScan() {
		let fragments = [
			"http", "https", "www", "com", "org", "local", "r", "spotify", "magnet", "xmpp", "mailto", "example", "host", "user", "swift",
			".", ":", "/", "//", "@", "!", "?", "#", "%", "&", "=", "+", "-", "_", "(", ")", "[", "]", "<", ">", "\"", "'", ",", ";", " ",
			" ",
			" ",
			"。", "．", "｡", "：", "／", "1", "22", "8080", "é", "日本",
		]
		var state: UInt64 = 0x1234_5678_9ABC_DEF0
		func next() -> Int {
			state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
			return Int(truncatingIfNeeded: state >> 33)
		}
		var differing: [String] = []
		for _ in 0 ..< 20000 {
			var text = ""
			for _ in 0 ..< (2 + next() % 12) {
				text += fragments[next() % fragments.count]
			}
			let filtered = Self.located(LinkParser.locateLinks(in: text, allowing: LinkSchemeRules()))
			let full = Self.located(LinkParser.scan(text, allowing: LinkSchemeRules()))
			if filtered != full {
				differing.append(text)
			}
		}
		#expect(differing.isEmpty, "prefilter changed the result for: \(differing.prefix(10))")
	}
}
