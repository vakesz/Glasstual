// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@Suite("Onboarding preview palette")
struct OnboardingPreviewPaletteTests {
	@Test("A preview draws in the theme's font, and in the system font where that is missing")
	func fontFollowsTheme() {
		#expect(OnboardingPreviewPalette.font(named: "Menlo", size: 14).fontName == NSFont(name: "Menlo", size: 14)?.fontName)
		let fallback = OnboardingPreviewPalette.font(named: "No Such Font", size: 14)
		#expect(fallback.familyName == NSFont.systemFont(ofSize: 14).familyName)
		#expect(fallback.pointSize == 14)
	}

	@Test("Nicknames and times are two points smaller, never below the smallest theme size")
	func secondarySize() {
		#expect(OnboardingPreviewPalette.secondarySize(for: 15) == 13)
		#expect(OnboardingPreviewPalette.secondarySize(for: TranscriptTheme.fontSizeRange.lowerBound)
			== TranscriptTheme.fontSizeRange.lowerBound)
	}
}
