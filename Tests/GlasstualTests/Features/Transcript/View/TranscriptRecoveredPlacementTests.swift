// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Transcript recovered placement")
struct TranscriptRecoveredPlacementTests {
	private typealias Run = TranscriptRecoveredPlacement.Run

	private func dates(_ seconds: [Double]) -> [Date] {
		seconds.map { Date(timeIntervalSince1970: $0) }
	}

	private func placement(drawn: [Double], recovered: [Double], room: Int = .max) -> TranscriptRecoveredPlacement {
		TranscriptRecoveredPlacement(drawn: dates(drawn), recovered: dates(recovered), room: room)
	}

	@Test("Recovered lines go between the lines they fall between, oldest first")
	func linesFallBetweenTheirNeighbours() {
		let placed = placement(drawn: [10, 20, 50, 60], recovered: [40, 30])
		#expect(placed.runs == [Run(index: 2, members: [1, 0])])
		#expect(placed.heldBack.isEmpty)
	}

	@Test("Lines that fall in different places go in as separate runs, in transcript order")
	func separateRuns() {
		let placed = placement(drawn: [10, 20, 30], recovered: [25, 15, 35, 16])
		#expect(placed.runs == [
			Run(index: 1, members: [1, 3]),
			Run(index: 2, members: [0]),
			Run(index: 3, members: [2]),
		])
	}

	@Test("A recovered line goes after a drawn line of the same time, and equal recovered lines keep their order")
	func equalTimesKeepArrivalOrder() {
		let placed = placement(drawn: [10, 20, 30], recovered: [20, 20])
		#expect(placed.runs == [Run(index: 2, members: [0, 1])])
	}

	@Test("A line older than everything drawn is held back for the older history")
	func olderThanEverythingIsHeldBack() {
		let placed = placement(drawn: [10, 20], recovered: [5, 15, 3])
		#expect(placed.runs == [Run(index: 1, members: [1])])
		#expect(placed.heldBack == [2, 0])
	}

	@Test("An empty transcript takes every recovered line, in order")
	func emptyTranscriptTakesEverything() {
		let placed = placement(drawn: [], recovered: [30, 10, 20])
		#expect(placed.runs == [Run(index: 0, members: [1, 2, 0])])
		#expect(placed.heldBack.isEmpty)
	}

	/** The reader's own join carries the local clock and sits above the
	 server history a catch-up drew after it. Messages from the gap belong
	 after that history, not above the join. */
	@Test("A locally stamped line above older server history does not pull recovered lines above it")
	func locallyStampedLineDoesNotAnchor() {
		let placed = placement(drawn: [10, 900, 20, 30, 80, 90], recovered: [40, 50])
		#expect(placed.runs == [Run(index: 4, members: [0, 1])])
	}

	@Test("Only the newest lines are placed when there is not room for all of them")
	func roomKeepsTheNewest() {
		let placed = placement(drawn: [10, 50], recovered: [20, 30, 60], room: 2)
		#expect(placed.runs == [Run(index: 1, members: [1]), Run(index: 2, members: [2])])
		#expect(placement(drawn: [10], recovered: [20], room: 0).runs.isEmpty)
	}
}
