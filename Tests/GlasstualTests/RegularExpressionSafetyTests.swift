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
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Testing

/// Patterns come from chat filters and address-book entries and are matched
/// against whatever a peer sends, so the two things bounded here are how long a
/// broken pattern costs and how much text a working one sees.
@Suite("Regular expression safety")
@MainActor
struct RegularExpressionSafetyTests {
	/** A pattern that cannot compile used to be recompiled, and re-logged, for
	 every message that reached it. The answer is the same either way — no match —
	 so what is observed here is the compile itself: the cache remembers the
	 failure, and the pattern reaches `NSRegularExpression` exactly once however
	 many times it is asked. */
	@Test("A pattern that cannot compile is compiled once and remembered")
	func failedCompilationIsRemembered() {
		let pattern = "([unclosed-\(UUID().uuidString)"
		#expect(RegularExpression.compilationCount(of: pattern) == 0)

		for _ in 0 ..< 8 {
			#expect(RegularExpression.string("anything", isMatchedByRegex: pattern) == false)
			#expect(RegularExpression.string("anything", rangeOfRegex: pattern).location == NSNotFound)
			#expect(
				RegularExpression.matches(
					in: "anything",
					withRegex: pattern,
					withoutCase: false,
					substringGroups: true
				).isEmpty
			)
		}

		#expect(RegularExpression.compilationCount(of: pattern) == 1)
	}

	/** A pattern that failed caseless must not answer for the same pattern with
	 case, and neither may be confused with a pattern that does compile. The two
	 spellings of the broken pattern are two keys, so they are two compiles, and
	 neither is tried again. */
	@Test("Remembering a failure does not answer for another pattern")
	func failureIsScopedToItsKey() {
		let broken = "(\(UUID().uuidString)"

		#expect(RegularExpression.string("hello", isMatchedByRegex: broken) == false)
		#expect(RegularExpression.string("hello", isMatchedByRegex: broken, withoutCase: true) == false)
		#expect(RegularExpression.compilationCount(of: broken) == 1)
		#expect(RegularExpression.compilationCount(of: broken, caseless: true) == 1)

		#expect(RegularExpression.string("hello", isMatchedByRegex: broken) == false)
		#expect(RegularExpression.compilationCount(of: broken) == 1)

		#expect(RegularExpression.string("HELLO", isMatchedByRegex: "hello", withoutCase: true))
		#expect(RegularExpression.string("hello", isMatchedByRegex: "^hello$"))
	}

	@Test("The subject is cut to the requested length")
	func boundedInputCutsTheSubject() {
		#expect(RegularExpression.boundedInput("hello", limit: 5) == "hello")
		#expect(RegularExpression.boundedInput("hello", limit: 2) == "he")
		#expect(RegularExpression.boundedInput("hello", limit: 0).isEmpty)
		/* Cutting by characters rather than by code units, so a subject never
		 ends in half of a scalar pair. */
		#expect(RegularExpression.boundedInput("a👩‍👩‍👧b", limit: 2) == "a👩‍👩‍👧")
	}

	@Test("A bounded match never looks past the limit")
	func boundedMatchStopsAtTheLimit() {
		let subject = String(repeating: "x", count: 64) + "needle"

		#expect(RegularExpression.string(subject, isMatchedByRegex: "needle", withoutCase: false, inputLimit: 4096))
		#expect(
			RegularExpression.string(subject, isMatchedByRegex: "needle", withoutCase: false, inputLimit: 64) == false
		)
		#expect(
			RegularExpression.matches(
				in: subject,
				withRegex: "needle",
				withoutCase: false,
				substringGroups: false,
				inputLimit: 64
			).isEmpty
		)
	}

	/** The shape the editor warns about: an unbounded repetition wrapped around a
	 body that can already match the same text in more than one length, which is
	 what makes ICU backtrack exponentially. */
	@Test(
		"A repetition wrapped around an unbounded repetition is reported",
		arguments: [
			"(a+)+",
			"(a*)*",
			"(a+)*",
			"(\\d+)*",
			"((x*))+",
			"(\\d{2,}){3,}",
			"(?:a+)+",
			"(a+)+$",
			"^(?:[a-z]+\\s?)+$",
			"(\\w+\\s*)+",
		]
	)
	func nestedQuantifiersAreReported(_ pattern: String) {
		#expect(RegularExpression.hasNestedQuantifier(pattern))
	}

	/** Patterns people actually write have to keep working: a repetition on its
	 own, an alternation, a bounded repeat, and a literal quantifier inside a
	 character class or behind a backslash are all fine.

	 The last four are what the heuristic used to report and no longer does. A
	 group that repeats around a body with anything mandatory in it — the `#`,
	 the comma, the dot — has one way to divide a subject, and a repetition with
	 a ceiling costs what its own limits say whatever it wraps. */
	@Test(
		"A pattern that does not nest unbounded repetitions is accepted",
		arguments: [
			"hello",
			"^[a-z]+$",
			"(cat|dog)",
			"(cat|dog)+",
			"a+b+c+",
			"(abc)+",
			"[+*]+",
			"\\(a+\\)+",
			"(a{2}){2}",
			"(https?://\\S+)",
			"(a+)?",
			"(#\\w+ )+",
			"(\\w+, )+",
			"(\\d{1,3}\\.){1,4}",
			"(a{1,2}){1,2}",
		]
	)
	func ordinaryPatternsAreAccepted(_ pattern: String) {
		#expect(RegularExpression.hasNestedQuantifier(pattern) == false)
	}

	/// Every pattern the heuristic reports on, and every pattern it clears, has
	/// to be one ICU accepts: a warning about a pattern that cannot compile
	/// would be shown instead of the reason it cannot.
	@Test(
		"The patterns the heuristic judges are patterns ICU compiles",
		arguments: ["(a+)+", "(#\\w+ )+", "(\\d{1,3}\\.){1,4}", "(a{1,2}){1,2}", "(?:[a-z]+\\s?)+"]
	)
	func judgedPatternsCompile(_ pattern: String) throws {
		#expect(throws: Never.self) {
			try NSRegularExpression(pattern: pattern)
		}
	}

	@Test("An empty pattern nests nothing")
	func emptyPatternNestsNothing() {
		#expect(RegularExpression.hasNestedQuantifier("") == false)
	}
}
