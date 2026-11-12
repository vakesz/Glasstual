// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Where recovered lines go among the lines a transcript already draws.

 Recovered lines are older than the live end, so each one belongs between two
 drawn lines rather than after them. A line goes directly after the last drawn
 line that is not later than it. Measuring from that side is what keeps a
 line the app stamped itself, such as the reader's own join, from pulling
 older messages above it: those lines carry the local clock and sit above
 server history that is older than they are.

 A line older than every drawn line is held back. It stays in the store, and
 the reader reaches it by loading older history, in order with whatever else
 is stored around it. */
nonisolated struct TranscriptRecoveredPlacement: Equatable, Sendable {
	/// Recovered lines that go in together, oldest first.
	struct Run: Equatable, Sendable {
		/// The index among the drawn lines the run is put in front of. The
		/// count of drawn lines names the end.
		let index: Int
		/// Indexes into the recovered lines, oldest first.
		let members: [Int]
	}

	/// The runs in the order they appear in the transcript.
	let runs: [Run]
	/// Indexes of the recovered lines that are older than every drawn line.
	let heldBack: [Int]

	/** Places `recovered` among `drawn`, both given as the times the lines
	 carry. Lines with the same time keep the order they arrived in. At most
	 `room` lines are placed, and the newest are the ones kept. */
	init(drawn: [Date], recovered: [Date], room: Int = .max) {
		let oldestFirst = recovered.indices.sorted {
			recovered[$0] == recovered[$1] ? $0 < $1 : recovered[$0] < recovered[$1]
		}
		/* The last drawn line that is not later moves towards the end as the
		 recovered time grows, so one pass from the newest of both finds it
		 for every line. */
		var positions: [(member: Int, index: Int)] = []
		var heldBack: [Int] = []
		var candidate = drawn.count - 1
		for member in oldestFirst.reversed() {
			while candidate >= 0, drawn[candidate] > recovered[member] {
				candidate -= 1
			}
			if candidate < 0, drawn.isEmpty == false {
				heldBack.append(member)
			} else {
				positions.append((member, candidate + 1))
			}
		}
		var runs: [Run] = []
		for position in positions.prefix(max(0, room)).reversed() {
			if let last = runs.last, last.index == position.index {
				runs[runs.count - 1] = Run(index: last.index, members: last.members + [position.member])
			} else {
				runs.append(Run(index: position.index, members: [position.member]))
			}
		}
		self.runs = runs
		self.heldBack = heldBack.reversed()
	}
}
