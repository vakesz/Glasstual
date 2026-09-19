// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
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

	/** The renderer already puts a gap either side of the nickname, so a format
	 with nothing after `%n` draws `12:34  @alice  hello`: three columns, and
	 nothing in them saying which one is the speaker. */
	@Test("The default nickname format ends in a separator")
	func defaultNicknameFormatCarriesSeparator() {
		let format = TranscriptTheme.lines.nicknameFormat

		#expect(format.hasPrefix("%@%n"))
		#expect(format.dropFirst("%@%n".count).isEmpty == false)
		#expect(TranscriptTheme.bubbles.nicknameFormat == format)
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
struct TranscriptThemeStoreTests {
	/// Isolated stores: importing and applying persist, and a controller over
	/// the live stores would overwrite whatever theme this Mac is using.
	private func makeController(_ fixture: SettingsTransferFixture) -> ThemeStore {
		ThemeStore(stores: fixture.stores)
	}

	private func encoded(_ theme: TranscriptTheme) throws -> Data {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .xml
		return try encoder.encode(theme)
	}

	@Test("Import and export use the same document")
	func importExportRoundTrip() throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let controller = makeController(fixture)
		var theme = TranscriptTheme.bubbles
		theme.name = "Imported"

		try controller.importTheme(from: encoded(theme))

		#expect(controller.theme == theme)
		#expect(try PropertyListDecoder().decode(TranscriptTheme.self, from: controller.exportTheme()) == theme)
	}

	/// `apply` used to drop an invalid theme without a word, so an out-of-range
	/// edit looked like it had been accepted.
	@Test("An invalid theme is refused rather than applied silently")
	func invalidThemeIsReportedAsRefused() throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let controller = makeController(fixture)
		let unchanged = controller.theme
		var theme = TranscriptTheme.lines
		theme.name = "   "

		#expect(controller.apply(theme) == false)
		#expect(controller.theme == unchanged)
	}

	@Test("Malformed files are refused")
	func malformedFileIsRefused() throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let controller = makeController(fixture)

		#expect(throws: TranscriptThemeCodingError.invalidDocument) {
			try controller.importTheme(from: Data("not a property list".utf8))
		}
	}

	@Test("A newer format version reports its version")
	func newerVersionIsRefused() throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let controller = makeController(fixture)
		var theme = TranscriptTheme.lines
		theme.formatVersion = TranscriptTheme.currentFormatVersion + 1
		let data = try encoded(theme)

		#expect(throws: TranscriptThemeCodingError.unsupportedVersion(theme.formatVersion)) {
			try controller.importTheme(from: data)
		}
	}

	/// An older document is refused outright rather than guessed at.
	@Test("An older format version reports its version", arguments: [1, 2])
	func olderVersionIsRefused(storedVersion: Int) throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let controller = makeController(fixture)
		var theme = TranscriptTheme.lines
		theme.formatVersion = storedVersion
		let data = try encoded(theme)

		#expect(throws: TranscriptThemeCodingError.unsupportedVersion(storedVersion)) {
			try controller.importTheme(from: data)
		}
	}

	/// A stored document this build cannot read leaves the shipped theme in
	/// place, and is left on disk rather than overwritten.
	@Test("A stored document of an older version falls back to the shipped theme")
	func storedOlderDocumentFallsBackToTheShippedTheme() throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let key = SettingsKeys.Theme.transcriptTheme
		var older = TranscriptTheme.lines
		older.formatVersion = 1
		let stored = try encoded(older)
		fixture.stores.set(.data(stored), for: key)

		let controller = makeController(fixture)
		controller.reload()

		#expect(controller.theme == TranscriptTheme.lines)
		#expect(fixture.stores[stored: key] == stored)
	}

	/// A current document is published as it stands, with nothing written back.
	@Test("A stored current document is read without being rewritten")
	func storedCurrentDocumentIsNotRewritten() throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let key = SettingsKeys.Theme.transcriptTheme
		var chosen = TranscriptTheme.lines
		chosen.nicknameFormat = "<%@%n>"
		let stored = try encoded(chosen)
		fixture.stores.set(.data(stored), for: key)

		let controller = makeController(fixture)
		controller.reload()

		#expect(controller.theme.nicknameFormat == "<%@%n>")
		#expect(fixture.stores[stored: key] == stored)
	}

	/// A palette missing a role is not a palette: the document is refused rather
	/// than filled in from another role.
	@Test("A document missing a colour role is refused")
	func aPaletteMissingARoleIsRefused() throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		var document = try #require(
			PropertyListSerialization.propertyList(from: encoded(.lines), format: nil) as? [String: Any]
		)
		var palette = try #require(document["palette"] as? [String: Any])
		palette.removeValue(forKey: "timestampText")
		document["palette"] = palette
		let data = try PropertyListSerialization.data(fromPropertyList: document, format: .xml, options: 0)

		let controller = makeController(fixture)

		#expect(throws: TranscriptThemeCodingError.invalidDocument) {
			try controller.importTheme(from: data)
		}
	}

	@Test("Choosing a colour drops the increased-contrast pair that shipped beside it")
	func editingARoleDropsItsHighContrastVariant() {
		var palette = TranscriptTheme.defaultPalette
		let chosen = TranscriptThemeColor(red: 0.1, green: 0.2, blue: 0.3)
		palette.link.light = chosen

		#expect(palette.link.resolved(isDark: false, increasesContrast: true) == chosen.color)
		// The other appearance keeps what it had; only the edited side is a choice.
		#expect(
			palette.link.resolved(isDark: true, increasesContrast: true)
				== TranscriptTheme.defaultPalette.link.resolved(isDark: true, increasesContrast: true)
		)
	}

	/** `appearanceDidChange()` had no callers, so the snapshot the transcript
	 resolves colours from off the main actor kept whichever appearance was in
	 effect when the theme last changed. */
	@Test("The published snapshot follows the appearance")
	func snapshotFollowsAppearance() throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let controller = makeController(fixture)
		let appearance = AppServices.appearance
		/* The stored value, not the effective one: restoring the effective value
		 writes the declared default into a setting the person never set, and
		 this is the live store the running application reads. */
		let previous = SettingsKeys.Appearance.preferredAppearance.storedValue
		defer {
			SettingsKeys.Appearance.preferredAppearance.storedValue = previous
			appearance.updateAppearance()
			AppServices.theme.appearanceDidChange()
		}

		for preferred in [PreferredAppearance.dark, .light] {
			SettingsKeys.Appearance.preferredAppearance.value = preferred
			appearance.updateAppearance()
			controller.appearanceDidChange()

			#expect(LiveThemeSnapshot.current.isDarkAppearance == (preferred == .dark))
		}
	}
}
