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
	/** A pattern that failed caseless must not answer for the same pattern with
	 case, and neither may be confused with a pattern that does compile. The
	 cache remembers the failure so the pattern is compiled once, which is not
	 observable from outside; what is, is that a remembered failure answers no
	 differently from a fresh one. */
	@Test("Remembering a failure does not answer for another pattern")
	func failureIsScopedToItsKey() {
		let broken = "(\(UUID().uuidString)"

		#expect(RegularExpression.firstMatch(of: broken, in: "hello") == .invalidPattern)
		#expect(RegularExpression.firstMatch(of: broken, in: "hello", withoutCase: true) == .invalidPattern)
		#expect(RegularExpression.firstMatch(of: broken, in: "hello") == .invalidPattern)

		#expect(RegularExpression.firstMatch(of: "hello", in: "HELLO", withoutCase: true) == .matched)
		#expect(RegularExpression.firstMatch(of: "^hello$", in: "hello") == .matched)
	}

	/// Cutting by characters rather than by code units, so a subject never ends
	/// in half of a grapheme — and an unbounded call still sees the whole
	/// subject.
	@Test("The subject is cut to the requested length, on a character boundary")
	func boundedInputCutsTheSubject() {
		#expect(RegularExpression.firstMatch(of: "b", in: "a👩‍👩‍👧b", inputLimit: 2) == .unmatched)
		#expect(RegularExpression.firstMatch(of: "👩‍👩‍👧", in: "a👩‍👩‍👧b", inputLimit: 2) == .matched)
		#expect(RegularExpression.firstMatch(of: "b", in: "a👩‍👩‍👧b") == .matched)
		#expect(RegularExpression.firstMatch(of: "h", in: "hello", inputLimit: 0) == .unmatched)
	}

	@Test("A bounded match never looks past the limit")
	func boundedMatchStopsAtTheLimit() {
		let subject = String(repeating: "x", count: 64) + "needle"

		#expect(RegularExpression.firstMatch(of: "needle", in: subject, inputLimit: 4096) == .matched)
		#expect(
			RegularExpression.firstMatch(of: "needle", in: subject, inputLimit: 64) == .unmatched
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
}
