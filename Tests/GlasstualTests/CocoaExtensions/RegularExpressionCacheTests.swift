import CocoaExtensions
import Foundation
import Testing

/// User-supplied patterns are evaluated once per incoming message,
/// so the compiled expression is cached. Caching must not change the answers.
@Suite("Regular expression cache")
@MainActor
struct RegularExpressionCacheTests {
	@Test("Repeated evaluation of the same pattern is stable")
	func repeatedEvaluationIsStable() {
		for _ in 0 ..< 4 {
			#expect(RegularExpression.firstMatch(of: "^hello", in: "hello world") == .matched)
			#expect(RegularExpression.firstMatch(of: "^hello", in: "goodbye world") == .unmatched)
		}
	}

	@Test("Case sensitivity is part of the cache identity")
	func caseSensitivityIsNotShared() {
		#expect(RegularExpression.firstMatch(of: "hello", in: "HELLO", withoutCase: false) == .unmatched)
		#expect(RegularExpression.firstMatch(of: "hello", in: "HELLO", withoutCase: true) == .matched)
		/* Again, now that both variants are cached. */
		#expect(RegularExpression.firstMatch(of: "hello", in: "HELLO", withoutCase: false) == .unmatched)
	}

	@Test("A pattern that cannot compile never matches")
	func invalidPatternNeverMatches() {
		#expect(RegularExpression.firstMatch(of: "([unclosed", in: "anything") == .invalidPattern)
		#expect(RegularExpression.firstMatch(of: "([unclosed", in: "anything") == .invalidPattern)
	}

	@Test("Capture groups survive caching")
	func captureGroupsSurvive() {
		let matches = RegularExpression.matches(
			in: "key=value",
			withRegex: "([a-z]+)=([a-z]+)",
			withoutCase: false,
			substringGroups: true
		)

		#expect(matches == ["key=value", "key", "value"])
	}

	/** The whole match leads, and a group that did not take part in the match is
	 not reported at all. The ZNC playback rewriter reads its groups by position
	 after dropping the first, so a pattern it hands over keeps every group
	 mandatory rather than optional. */
	@Test("Groups are reported behind the whole match, and only when they matched")
	func groupsFollowTheWholeMatch() {
		let alternation = RegularExpression.matches(
			in: "quit: bye",
			withRegex: #"^(?:quit with message: \[(.*)\]|quit: (.*))$"#,
			withoutCase: false,
			substringGroups: true
		)

		#expect(alternation == ["quit: bye", "bye"])

		let empty = RegularExpression.matches(
			in: "set mode: +o",
			withRegex: #"^set mode: ([^\s]+)(.*)$"#,
			withoutCase: false,
			substringGroups: true
		)

		#expect(empty == ["set mode: +o", "+o", ""])
	}

	@Test("Without capture groups only the whole match is reported")
	func wholeMatchesOnly() {
		let matches = RegularExpression.matches(
			in: "a1b2",
			withRegex: "[0-9]",
			withoutCase: false,
			substringGroups: false
		)

		#expect(matches == ["1", "2"])
	}
}
