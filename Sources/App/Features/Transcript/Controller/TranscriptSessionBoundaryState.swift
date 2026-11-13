// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Tracks the one visual boundary between restored scrollback and lines from
/// this process. The boundary may be known during the initial replay or may
/// have to wait for the first live line that arrives afterwards.
nonisolated struct TranscriptSessionBoundaryState: Sendable {
	private(set) var newestPreviousSessionLineNumber: String?
	private(set) var firstCurrentSessionLineNumber: String?
	private var markerIsPending = false

	mutating func prepareInitialHistory(
		_ scrollbackLines: [ChatLine],
		renderedLines: [TranscriptRenderResult]
	) -> String? {
		newestPreviousSessionLineNumber = scrollbackLines.last { $0.fromCurrentSession == false }?
			.uniqueIdentifier
		firstCurrentSessionLineNumber = nil
		guard newestPreviousSessionLineNumber != nil else {
			markerIsPending = false
			return nil
		}
		guard let firstCurrent = renderedLines.first(where: \.fromCurrentSession) else {
			markerIsPending = true
			return nil
		}
		markerIsPending = false
		firstCurrentSessionLineNumber = firstCurrent.lineNumber
		return firstCurrent.lineNumber
	}

	mutating func consumePendingMarker(for line: TranscriptRenderResult) -> Bool {
		guard markerIsPending, line.fromCurrentSession else {
			return false
		}
		markerIsPending = false
		firstCurrentSessionLineNumber = line.lineNumber
		return true
	}

	mutating func reset() {
		newestPreviousSessionLineNumber = nil
		firstCurrentSessionLineNumber = nil
		markerIsPending = false
	}
}
