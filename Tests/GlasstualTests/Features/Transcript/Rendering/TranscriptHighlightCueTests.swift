// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

struct TranscriptHighlightCueTests {
	@Test("A highlighted plain run is underlined only when colour is not enough")
	func underlinesOnlyWithoutColor() {
		#expect(TranscriptHighlightCue.underlinesRun(isHighlighted: true, differentiatesWithoutColor: true, action: nil))
		#expect(!TranscriptHighlightCue.underlinesRun(isHighlighted: true, differentiatesWithoutColor: false, action: nil))
		#expect(!TranscriptHighlightCue.underlinesRun(isHighlighted: false, differentiatesWithoutColor: true, action: nil))
	}

	@Test("A highlighted run that carries an action keeps its own styling")
	func actionRunsAreNotUnderlined() {
		let action = TranscriptRunAction.channel("#swift")
		#expect(!TranscriptHighlightCue.underlinesRun(
			isHighlighted: true, differentiatesWithoutColor: true, action: action
		))
	}

	@Test("The spoken prefix leads and does not duplicate")
	func spokenPrefixComposes() {
		#expect(TranscriptHighlightCue.spokenText(prefix: "Highlighted", existing: []) == ["Highlighted"])
		#expect(TranscriptHighlightCue.spokenText(prefix: "Highlighted", existing: ["Sent"]) == ["Highlighted", "Sent"])
		#expect(TranscriptHighlightCue.spokenText(prefix: "Highlighted", existing: ["Highlighted", "Sent"])
			== ["Highlighted", "Sent"])
	}
}
