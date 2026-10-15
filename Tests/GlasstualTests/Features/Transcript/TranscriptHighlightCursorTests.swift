// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Transcript highlight cursor")
struct TranscriptHighlightCursorTests {
	@Test("A first step forward lands on the first highlight, a first step back on the last")
	func firstStepDirection() {
		var forward = TranscriptHighlightCursor()
		#expect(forward.step(by: 1, through: ["a", "b", "c"]) == "a")
		var backward = TranscriptHighlightCursor()
		#expect(backward.step(by: -1, through: ["a", "b", "c"]) == "c")
	}

	@Test("Steps wrap at either end")
	func stepsWrap() {
		var cursor = TranscriptHighlightCursor()
		#expect(cursor.step(by: -1, through: ["a", "b"]) == "b")
		#expect(cursor.step(by: 1, through: ["a", "b"]) == "a")
		#expect(cursor.step(by: -1, through: ["a", "b"]) == "b")
	}

	@Test("A visited line that is no longer a highlight starts the walk over")
	func vanishedLineRestarts() {
		var cursor = TranscriptHighlightCursor()
		_ = cursor.step(by: 1, through: ["a", "b"])
		#expect(cursor.step(by: 1, through: ["b", "c"]) == "b")
	}

	@Test("No highlights moves nothing")
	func emptyKeepsPosition() {
		var cursor = TranscriptHighlightCursor()
		_ = cursor.step(by: 1, through: ["a"])
		#expect(cursor.step(by: 1, through: []) == nil)
		#expect(cursor.lastVisited == "a")
	}

	@Test("Only removing the visited line forgets it")
	func forgetOnlyVisited() {
		var cursor = TranscriptHighlightCursor()
		_ = cursor.step(by: 1, through: ["a", "b"])
		cursor.forget(["b"])
		#expect(cursor.lastVisited == "a")
		cursor.forget(["a"])
		#expect(cursor.lastVisited == nil)
	}
}
