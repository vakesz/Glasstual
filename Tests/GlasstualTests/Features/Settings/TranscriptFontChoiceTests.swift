// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript font choice")
struct TranscriptFontChoiceTests {
	@Test("The system font keeps the name the theme stores for it and is called System")
	func systemFont() {
		let font = NSFont.systemFont(ofSize: 13)
		let choice = TranscriptFontChoice(font)
		#expect(choice.name == TranscriptTheme.lines.fontName)
		#expect(TranscriptFontChoice.displayName(for: choice.name) == String(localized: .Settings.styleFontSystem))
	}

	@Test("A named font is stored by its PostScript name and shown by its face name")
	func namedFont() throws {
		let font = try #require(NSFont(name: "Helvetica-Bold", size: 14))
		let choice = TranscriptFontChoice(font)
		#expect(choice == TranscriptFontChoice(name: "Helvetica-Bold", size: 14))
		#expect(TranscriptFontChoice.displayName(for: choice.name) == "Helvetica Bold")
	}

	@Test("A size the Fonts panel offers but the theme refuses is held to the theme's bounds")
	func sizeIsClamped() {
		let range = TranscriptTheme.fontSizeRange
		#expect(TranscriptFontChoice(name: "Helvetica", size: 288).size == range.upperBound)
		#expect(TranscriptFontChoice(name: "Helvetica", size: 4).size == range.lowerBound)
		#expect(TranscriptFontChoice(name: "Helvetica", size: 12.5).size == 12.5)
	}
}
