/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// A keyword in Regular Expression mode used to be compiled once per keyword
/// per rendered line, failures included.
@Suite("Transcript highlight expressions")
struct TranscriptHighlightExpressionsTests {
	@Test("A pattern is compiled once and answered from the cache afterwards")
	func compiledPatternsAreReused() {
		let cache = TranscriptHighlightExpressions()
		let first = cache.expression(for: "gl[a]sstual")
		let second = cache.expression(for: "gl[a]sstual")
		#expect(first != nil)
		#expect(first === second)
	}

	@Test("A pattern that cannot compile answers nil rather than throwing it away twice")
	func failuresAreRemembered() {
		let cache = TranscriptHighlightExpressions()
		#expect(cache.expression(for: "unclosed[") == nil)
		#expect(cache.expression(for: "unclosed[") == nil)
	}

	@Test("The store keeps a bounded number of patterns")
	func theStoreIsBounded() {
		let cache = TranscriptHighlightExpressions()
		for index in 0 ..< 200 {
			#expect(cache.expression(for: "keyword\(index)") != nil)
		}
		/* The most recent pattern is still the one a new line asks for. */
		let recent = cache.expression(for: "keyword199")
		#expect(recent === cache.expression(for: "keyword199"))
	}
}
