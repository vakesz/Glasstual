// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("XDCC pack range")
struct XDCCPackRangeTests {
	@Test("Numbers and ranges expand in the order written, without duplicates", arguments: [
		("1-5,7,#9", [1, 2, 3, 4, 5, 7, 9]),
		("#3", [3]),
		("3, 1 2", [3, 1, 2]),
		("1-3,2-4,1", [1, 2, 3, 4]),
		("#4-#6", [4, 5, 6]),
		("  7 ,, 8  ", [7, 8]),
		("999999", [999_999]),
	] as [(String, [Int])])
	func expands(text: String, expected: [Int]) throws {
		#expect(try XDCCPackRange.expand(text, limit: 20).get() == expected)
	}

	@Test("Malformed, reversed, zero and oversized lists are refused", arguments: [
		("", XDCCPackRangeError.empty),
		(" , ", .empty),
		("5-1", .reversed(5, 1)),
		("0", .outOfRange(0)),
		("0-3", .outOfRange(0)),
		("1000000", .outOfRange(1_000_000)),
		("abc", .malformed("abc")),
		("1-2-3", .malformed("1-2-3")),
		("1-", .malformed("1-")),
		("#", .malformed("#")),
		("\u{0663}", .malformed("\u{0663}")),
		("12345678", .malformed("12345678")),
	] as [(String, XDCCPackRangeError)])
	func refuses(text: String, expected: XDCCPackRangeError) {
		#expect(XDCCPackRange.expand(text, limit: 20) == .failure(expected))
	}

	@Test("More packs than the limit are refused without expanding a huge range")
	func limit() {
		#expect(XDCCPackRange.expand("1-20", limit: 20) == .success(Array(1 ... 20)))
		#expect(XDCCPackRange.expand("1-21", limit: 20) == .failure(.tooMany(limit: 20)))
		#expect(XDCCPackRange.expand("1-999999", limit: 20) == .failure(.tooMany(limit: 20)))
		#expect(XDCCPackRange.expand("1-20,5,20", limit: 20) == .success(Array(1 ... 20)))
	}
}
