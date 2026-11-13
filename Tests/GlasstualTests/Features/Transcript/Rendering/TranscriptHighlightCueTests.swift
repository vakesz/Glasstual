// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

struct TranscriptHighlightCueTests {
	@Test("A highlighted run is underlined only when colour is not enough")
	func underlinesOnlyWithoutColor() {
		#expect(TranscriptHighlightCue.underlinesRun(isHighlighted: true, differentiatesWithoutColor: true))
		#expect(!TranscriptHighlightCue.underlinesRun(isHighlighted: true, differentiatesWithoutColor: false))
		#expect(!TranscriptHighlightCue.underlinesRun(isHighlighted: false, differentiatesWithoutColor: true))
	}

	@Test("An action colours its run only outside a highlight")
	func highlightKeepsItsOwnTextColour() {
		#expect(TranscriptHighlightCue.actionColorsRun(isHighlighted: false))
		#expect(!TranscriptHighlightCue.actionColorsRun(isHighlighted: true))
	}

	@Test("The spoken prefix leads and does not duplicate")
	func spokenPrefixComposes() {
		#expect(TranscriptHighlightCue.spokenText(prefix: "Highlighted", existing: []) == ["Highlighted"])
		#expect(TranscriptHighlightCue.spokenText(prefix: "Highlighted", existing: ["Sent"]) == ["Highlighted", "Sent"])
		#expect(TranscriptHighlightCue.spokenText(prefix: "Highlighted", existing: ["Highlighted", "Sent"])
			== ["Highlighted", "Sent"])
	}
}
