// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreText
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Settings font picker")
struct SettingsFontPickerTests {
	@Test("The default font is named System and remains selectable after choosing another font")
	func systemFontChoice() throws {
		let defaultName = TranscriptTheme.lines.fontName
		let choices = SettingsFontPicker.choices.filter { $0.id == defaultName }
		let choice = try #require(choices.first)
		#expect(choices.count == 1)
		#expect(choice.displayName == String(localized: .Settings.styleFontSystem))
		#expect(SettingsFontPicker.displayName(for: defaultName) == choice.displayName)
		#expect(choice.displayName.hasPrefix(".") == false)
	}

	@Test("Named fonts show their readable face name while preserving the PostScript selection identifier")
	func namedFontChoice() throws {
		let choice = try #require(SettingsFontPicker.choices.first { $0.id == "Helvetica-Bold" })
		let font = CTFontCreateWithName(choice.id as CFString, 13, nil)
		#expect(choice.displayName == CTFontCopyDisplayName(font) as String)
		#expect(choice.displayName == "Helvetica Bold")
	}
}
