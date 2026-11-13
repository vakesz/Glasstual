// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** A range measured before a replacement describes storage the replacement
 shrank. Selecting eleven characters and inserting a shorter nickname then
 recoloured a range past the end of the field and threw. */
@Suite("Menu insertion ranges")
struct MenuInsertionRangePolicyTests {
	@Test("The inserted range covers what was inserted, at the replaced location")
	func insertedRangeCoversTheInsertion() {
		let replaced = NSRange(location: 4, length: 11)

		let inserted = MenuInsertionRangePolicy.insertedRange(replacing: replaced, with: "bob, ")

		#expect(inserted == NSRange(location: 4, length: 5))
	}

	/// The length is in UTF-16 units, which is what `NSTextStorage` counts in.
	@Test("Astral characters count as the storage counts them")
	func lengthIsMeasuredInUTF16() {
		let inserted = MenuInsertionRangePolicy.insertedRange(
			replacing: NSRange(location: 0, length: 3),
			with: "🙂"
		)

		#expect(inserted == NSRange(location: 0, length: 2))
	}

	@Test("An empty insertion collapses the range")
	func emptyInsertionCollapses() {
		let inserted = MenuInsertionRangePolicy.insertedRange(
			replacing: NSRange(location: 7, length: 4),
			with: ""
		)

		#expect(inserted == NSRange(location: 7, length: 0))
	}
}
