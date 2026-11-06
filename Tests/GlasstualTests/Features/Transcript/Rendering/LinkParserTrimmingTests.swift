// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Trailing punctuation and bracket balance beyond what `LinkParserCorpusTests` covers.
struct LinkParserTrimmingTests {
	nonisolated static let cases: [(text: String, link: String)] = [
		("see {http://example.com/a} now", "http://example.com/a"),
		("see http://example.com/a} now", "http://example.com/a"),
		("see http://example.com/a)). now", "http://example.com/a"),
		("see (http://example.com/a_(b)) now", "http://example.com/a_(b)"),
		("see http://example.com/a; now", "http://example.com/a"),
		("see http://example.com/a! now", "http://example.com/a"),
		("see http://example.com/a\u{2026} now", "http://example.com/a"),
		("see \u{201C}http://example.com/a\u{201D} now", "http://example.com/a"),
	]

	@Test("Closing punctuation outside the address is trimmed and a matched pair is kept", arguments: Self.cases)
	func trims(_ testCase: (text: String, link: String)) {
		#expect(LinkParser.locateLinks(in: testCase.text).map(\.stringValue) == [testCase.link])
	}
}
