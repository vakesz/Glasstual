/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@Suite("Native transcript themes")
struct TranscriptThemeTests {
	@Test("The portable theme model round-trips through an XML property list")
	func propertyListRoundTrip() throws {
		var theme = TranscriptTheme.bubbles
		theme.name = "Ocean"
		theme.palette.link.light = TranscriptThemeColor(red: 0.1, green: 0.2, blue: 0.8)
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .xml
		let data = try encoder.encode(theme)

		#expect(String(bytes: data.prefix(64), encoding: .utf8)?.contains("<?xml") == true)
		#expect(try PropertyListDecoder().decode(TranscriptTheme.self, from: data) == theme)
	}

	@Test("Every built-in theme satisfies the format contract")
	func builtInsAreValid() {
		#expect(TranscriptTheme.lines.isValid)
		#expect(TranscriptTheme.bubbles.isValid)
		#expect(TranscriptTheme.defaultPalette.isValid)
	}

	@Test("Out-of-range components and geometry are rejected")
	func invalidValuesAreRejected() {
		var theme = TranscriptTheme.lines
		theme.fontSize = 100
		theme.palette.background.light.red = 2

		#expect(theme.isValid == false)
	}

	/// The font picker used to offer 6...72 while only 9...36 could be applied,
	/// so the sizes outside it dismissed the sheet and changed nothing.
	@Test("The offered font sizes are exactly the ones a theme accepts")
	func fontSizeRangeMatchesValidation() {
		var theme = TranscriptTheme.lines

		for size in [TranscriptTheme.fontSizeRange.lowerBound, TranscriptTheme.fontSizeRange.upperBound] {
			theme.fontSize = size
			#expect(theme.isValid)
		}

		for size in [
			TranscriptTheme.fontSizeRange.lowerBound - 1,
			TranscriptTheme.fontSizeRange.upperBound + 1,
		] {
			theme.fontSize = size
			#expect(theme.isValid == false)
		}
	}
}

@MainActor
@Suite("Transcript theme import and export")
struct TranscriptThemeControllerTests {
	@Test("Import and export use the same document")
	func importExportRoundTrip() throws {
		let previous = Preferences.Theme.transcriptTheme.value
		defer {
			Preferences.Theme.transcriptTheme.value = previous
			ThemeController().reload()
		}
		let controller = ThemeController()
		var theme = TranscriptTheme.bubbles
		theme.name = "Imported"
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .xml

		try controller.importTheme(from: encoder.encode(theme))

		#expect(controller.theme == theme)
		#expect(try PropertyListDecoder().decode(TranscriptTheme.self, from: controller.exportTheme()) == theme)
	}

	/// `apply` used to drop an invalid theme without a word, so an out-of-range
	/// edit looked like it had been accepted.
	@Test("An invalid theme is refused rather than applied silently")
	func invalidThemeIsReportedAsRefused() {
		let controller = ThemeController()
		let unchanged = controller.theme
		var theme = TranscriptTheme.lines
		theme.name = "   "

		#expect(controller.apply(theme) == false)
		#expect(controller.theme == unchanged)
	}

	@Test("Malformed files are refused")
	func malformedFileIsRefused() {
		let controller = ThemeController()

		#expect(throws: TranscriptThemeCodingError.invalidDocument) {
			try controller.importTheme(from: Data("not a property list".utf8))
		}
	}

	@Test("A newer format version reports its version")
	func newerVersionIsRefused() throws {
		let controller = ThemeController()
		var theme = TranscriptTheme.lines
		theme.formatVersion = TranscriptTheme.currentFormatVersion + 1
		let data = try PropertyListEncoder().encode(theme)

		#expect(throws: TranscriptThemeCodingError.unsupportedVersion(theme.formatVersion)) {
			try controller.importTheme(from: data)
		}
	}
}
