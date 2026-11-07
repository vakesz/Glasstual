// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("Multi-line batch planning")
struct MultilineBatchPlannerTests {
	private func line(_ text: String, continues: Bool = false) -> MultilineWireLine {
		MultilineWireLine(text: text, continuesPrevious: continues)
	}

	@Test("Lines join with a line break and a continuation joins with nothing")
	func joinsLines() {
		let lines = [line("one"), line("two"), line(" and more", continues: true), line("three")]

		#expect(MultilineBatchPlanner.joinedText(of: lines) == "one\ntwo and more\nthree")
		#expect(MultilineBatchPlanner.logicalLineCount(of: lines) == 3)
	}

	@Test("Each line break counts as a byte")
	func countsBreaks() {
		let lines = [line("ab"), line("cd"), line("ef", continues: true)]

		#expect(MultilineBatchPlanner.payloadByteCount(of: lines) == 7)
	}

	@Test("Multi-byte text is counted in bytes")
	func countsBytesNotCharacters() {
		#expect(MultilineBatchPlanner.payloadByteCount(of: [line("\u{e9}\u{e9}"), line("x")]) == 6)
	}

	@Test("Lines over the line limit are reported before bytes")
	func reportsLinesFirst() {
		let lines = [line("aaaa"), line("bbbb"), line("cccc")]

		#expect(MultilineBatchPlanner.fit(of: lines, within: MultilineLimits(maximumBytes: 1000, maximumLines: 3)) == .fits)
		#expect(MultilineBatchPlanner.fit(of: lines, within: MultilineLimits(maximumBytes: 1000, maximumLines: 2)) == .tooManyLines)
		#expect(MultilineBatchPlanner.fit(of: lines, within: MultilineLimits(maximumBytes: 10, maximumLines: 2)) == .tooManyLines)
		#expect(MultilineBatchPlanner.fit(of: lines, within: MultilineLimits(maximumBytes: 10)) == .tooManyBytes)
	}

	@Test("Exactly the byte limit fits")
	func byteLimitIsInclusive() {
		let lines = [line("aaaa"), line("bbbb")]

		#expect(MultilineBatchPlanner.fit(of: lines, within: MultilineLimits(maximumBytes: 9)) == .fits)
		#expect(MultilineBatchPlanner.fit(of: lines, within: MultilineLimits(maximumBytes: 8)) == .tooManyBytes)
	}

	@Test("Blank lines at either end are dropped and the ones between stay")
	func trimsBlankEdges() {
		let lines = [line(""), line("a"), line(""), line("b"), line(""), line("")]

		#expect(MultilineBatchPlanner.trimmingBlankEdges(lines) == [line("a"), line(""), line("b")])
		#expect(MultilineBatchPlanner.trimmingBlankEdges([line(""), line("")]).isEmpty)
	}

	@Test("Truncating keeps the lines that fit")
	func truncatesToTheLineLimit() {
		let lines = [line("one"), line("two"), line("three")]
		let kept = MultilineBatchPlanner.truncated(lines, to: MultilineLimits(maximumBytes: 1000, maximumLines: 2))

		#expect(kept == [line("one"), line("two")])
	}

	@Test("Truncating by bytes stops before the line that would overflow")
	func truncatesToTheByteLimit() {
		let lines = [line("aaaa"), line("bbbb"), line("cccc")]
		let kept = MultilineBatchPlanner.truncated(lines, to: MultilineLimits(maximumBytes: 9))

		#expect(kept == [line("aaaa"), line("bbbb")])
	}

	@Test("A line cut into several wire lines is kept whole or dropped")
	func truncationDoesNotSplitALogicalLine() {
		let lines = [line("first"), line("second-a"), line("second-b", continues: true)]
		let kept = MultilineBatchPlanner.truncated(lines, to: MultilineLimits(maximumBytes: 16))

		#expect(kept == [line("first")])
	}

	@Test("Text whose first line alone is too long keeps nothing")
	func firstLineTooLong() {
		let kept = MultilineBatchPlanner.truncated([line("abcdefgh")], to: MultilineLimits(maximumBytes: 4))

		#expect(kept.isEmpty)
	}
}
