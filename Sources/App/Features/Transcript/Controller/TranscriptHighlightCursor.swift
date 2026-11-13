// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Where the reader stands among a transcript's highlights, for the commands
 that step through them.

 Only the line last visited is kept. The highlights themselves are read from
 the view on each step, so a line trimmed or added since is accounted for. */
nonisolated struct TranscriptHighlightCursor: Sendable, Equatable {
	/// The highlight the reader last jumped to.
	private(set) var lastVisited: String?

	/** Steps `offset` highlights from the one last visited, wrapping at either
	 end, and returns the line to jump to.

	 With nothing visited yet, or with the line visited no longer among
	 `highlights`, a step forward starts at the first highlight and a step back
	 at the last. Returns `nil`, and moves nothing, when there are none. */
	mutating func step(by offset: Int, through highlights: [String]) -> String? {
		guard highlights.isEmpty == false else { return nil }
		let current = lastVisited.flatMap(highlights.firstIndex(of:))
		let index = current.map { ($0 + offset + highlights.count) % highlights.count }
			?? (offset > 0 ? 0 : highlights.count - 1)
		let target = highlights[index]
		lastVisited = target
		return target
	}

	/// The view dropped these lines. Only the highlight last visited is
	/// addressed by line number, so it is the only cursor a removal can leave
	/// pointing at nothing.
	mutating func forget(_ removedLineNumbers: [String]) {
		if let lastVisited, removedLineNumbers.contains(lastVisited) {
			self.lastVisited = nil
		}
	}

	mutating func reset() {
		lastVisited = nil
	}
}
