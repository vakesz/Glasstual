// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Formatting parser line feeds")
struct FormattingParserLineFeedTests {
	@Test("A line feed is drawn as a space unless the caller keeps it")
	func lineFeedIsASpaceByDefault() {
		#expect(FormattingParser.parse("one\ntwo").string == "one two")
	}

	@Test("A caller that holds a person's text keeps its line feeds")
	func lineFeedsCanBeKept() {
		#expect(FormattingParser.parse("one\ntwo", preservingLineFeeds: true).string == "one\ntwo")
	}

	@Test("Keeping line feeds changes no other separator", arguments: ["\r", "\u{2028}", "\u{85}"])
	func otherSeparatorsStayCollapsed(_ separator: String) {
		#expect(FormattingParser.parse("one\(separator)two", preservingLineFeeds: true).string == "one two")
	}

	@Test("Formatting after a kept line feed still applies")
	func formattingSurvivesALineFeed() {
		let parsed = FormattingParser.parse("\u{2}bold\nstill\u{2} plain", preservingLineFeeds: true)

		#expect(parsed.string == "bold\nstill plain")
		#expect(parsed.attribute(IRCFormattingAttribute.bold, at: 6, effectiveRange: nil) != nil)
		#expect(parsed.attribute(IRCFormattingAttribute.bold, at: 11, effectiveRange: nil) == nil)
	}
}
