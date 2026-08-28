import CocoaExtensions
import Foundation
import Testing

/// User- and plugin-supplied patterns are evaluated once per incoming message,
/// so the compiled expression is cached. Caching must not change the answers.
@Suite("Regular expression cache")
struct RegularExpressionCacheTests {
	@Test("Repeated evaluation of the same pattern is stable")
	func repeatedEvaluationIsStable() {
		for _ in 0 ..< 4 {
			#expect(RegularExpression.string("hello world", isMatchedByRegex: "^hello"))
			#expect(RegularExpression.string("goodbye world", isMatchedByRegex: "^hello") == false)
		}
	}

	@Test("Case sensitivity is part of the cache identity")
	func caseSensitivityIsNotShared() {
		#expect(RegularExpression.string("HELLO", isMatchedByRegex: "hello", withoutCase: false) == false)
		#expect(RegularExpression.string("HELLO", isMatchedByRegex: "hello", withoutCase: true))
		/* Again, now that both variants are cached. */
		#expect(RegularExpression.string("HELLO", isMatchedByRegex: "hello", withoutCase: false) == false)
	}

	@Test("A pattern that cannot compile never matches")
	func invalidPatternNeverMatches() {
		#expect(RegularExpression.string("anything", isMatchedByRegex: "([unclosed") == false)
		#expect(RegularExpression.string("anything", isMatchedByRegex: "([unclosed") == false)
	}

	@Test("Replacement and range lookups agree with matching")
	func replacementAndRangeAgree() {
		#expect(RegularExpression.string("a1b2", replacedByRegex: "[0-9]", with: "#") == "a#b#")

		let range = RegularExpression.string("a1b2", rangeOfRegex: "[0-9]")

		#expect(range.location == 1)
		#expect(range.length == 1)
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
}
