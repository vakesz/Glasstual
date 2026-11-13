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
}
