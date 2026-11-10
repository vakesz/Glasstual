// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

struct TranscriptHistoryMergeTests {
	@Test("A fetch outcome maps to entries, failure and success")
	func fetchOutcomeMapping() {
		let page = TranscriptHistoryMerge.fetched(.page([]))
		#expect(page.entries.isEmpty && page.failure == nil && page.succeeded)
		let failed = TranscriptHistoryMerge.fetched(.failed(.unavailable))
		#expect(failed.entries.isEmpty && failed.failure == .unavailable && !failed.succeeded)
		let cancelled = TranscriptHistoryMerge.fetched(.cancelled)
		#expect(cancelled.entries.isEmpty && cancelled.failure == nil && !cancelled.succeeded)
	}

	@Test("A replayed line is claimed once and later duplicates render fresh")
	func replayedLinesAreClaimedOnce() {
		let result = TranscriptHistoryMerge.assign(
			identifiers: ["a", "b", "a", "c"],
			replayedLineNumbers: ["a", "c", "z"]
		)
		#expect(result.slots == [.replayed(lineNumber: "a"), .fresh, .fresh, .replayed(lineNumber: "c")])
		#expect(result.consumed == ["a", "c"])
	}

	@Test("Nothing is claimed when no replay overlaps the stored page")
	func noOverlapRendersFresh() {
		let result = TranscriptHistoryMerge.assign(identifiers: ["a", "b"], replayedLineNumbers: [])
		#expect(result.slots == [.fresh, .fresh])
		#expect(result.consumed.isEmpty)
	}
}
