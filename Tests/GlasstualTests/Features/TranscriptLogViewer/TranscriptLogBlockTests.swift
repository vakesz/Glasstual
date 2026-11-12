// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Transcript log blocks")
struct TranscriptLogBlockTests {
	private func lines(_ count: Int) -> [TranscriptLogLine] {
		(0 ..< count).map { TranscriptLogLine(offset: $0 * 10, bytes: Data("line \($0)".utf8)) }
	}

	@Test("Without matches, lines are set in blocks of the most a block holds")
	func blocksAreBounded() {
		let all = lines(TranscriptLogBlock.maximumLines * 2 + 1)
		let blocks = TranscriptLogBlock.blocks(of: all, startingAt: [])
		#expect(blocks.map(\.lines.count) == [TranscriptLogBlock.maximumLines, TranscriptLogBlock.maximumLines, 1])
		#expect(blocks.flatMap(\.lines) == all)
	}

	@Test("Each match begins a block named after its line, which is what a search scrolls to")
	func matchesStartBlocks() {
		let all = lines(10)
		let blocks = TranscriptLogBlock.blocks(of: all, startingAt: [0, 30, 70])
		#expect(blocks.map(\.id) == [0, 30, 70])
		#expect(blocks.map(\.lines.count) == [3, 4, 3])
		#expect(blocks.flatMap(\.lines) == all)
	}

	@Test("No lines make no blocks")
	func emptyLog() {
		#expect(TranscriptLogBlock.blocks(of: [], startingAt: [1]).isEmpty)
	}
}
