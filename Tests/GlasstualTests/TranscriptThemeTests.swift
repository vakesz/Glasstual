/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

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
struct TranscriptThemeControllerTests {
	/// Isolated stores: importing and applying persist, and a controller over
	/// the live stores would overwrite whatever theme this Mac is using.
	private func makeController(_ fixture: PreferencesTransferFixture) -> ThemeController {
		ThemeController(stores: fixture.stores)
	}

	private func encoded(_ theme: TranscriptTheme) throws -> Data {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .xml
		return try encoder.encode(theme)
	}

	@Test("Import and export use the same document")
	func importExportRoundTrip() throws {
		let fixture = try PreferencesTransferFixture()
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
		let fixture = try PreferencesTransferFixture()
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
		let fixture = try PreferencesTransferFixture()
		defer { fixture.cleanUp() }
		let controller = makeController(fixture)

		#expect(throws: TranscriptThemeCodingError.invalidDocument) {
			try controller.importTheme(from: Data("not a property list".utf8))
		}
	}

	@Test("A newer format version reports its version")
	func newerVersionIsRefused() throws {
		let fixture = try PreferencesTransferFixture()
		defer { fixture.cleanUp() }
		let controller = makeController(fixture)
		var theme = TranscriptTheme.lines
		theme.formatVersion = TranscriptTheme.currentFormatVersion + 1
		let data = try encoded(theme)

		#expect(throws: TranscriptThemeCodingError.unsupportedVersion(theme.formatVersion)) {
			try controller.importTheme(from: data)
		}
	}

	/// Version 1 themes all carried `<%@%n>` because it was the default, not a
	/// choice; a version 2 theme saying the same thing has chosen it.
	@Test("The bracketed default of a version 1 theme is migrated once")
	func legacyBracketsAreMigratedOnce() throws {
		let fixture = try PreferencesTransferFixture()
		defer { fixture.cleanUp() }
		let controller = makeController(fixture)
		var legacy = TranscriptTheme.lines
		legacy.formatVersion = 1
		legacy.nicknameFormat = TranscriptTheme.legacyBracketedNicknameFormat
		try controller.importTheme(from: encoded(legacy))
		#expect(controller.theme.nicknameFormat == TranscriptTheme.lines.nicknameFormat)
		#expect(controller.theme.formatVersion == TranscriptTheme.currentFormatVersion)

		var chosen = TranscriptTheme.lines
		chosen.nicknameFormat = TranscriptTheme.legacyBracketedNicknameFormat
		try controller.importTheme(from: encoded(chosen))
		#expect(controller.theme.nicknameFormat == TranscriptTheme.legacyBracketedNicknameFormat)
	}

	/** The migration used to be published but never stored, so the stored
	 document stayed at version 1: it was migrated again at every launch, an
	 export carried the old version out, and the day the brackets became a
	 choice again the stored theme would have lost them a second time. */
	@Test("A stored version 1 theme is rewritten once, and a later choice of the brackets survives")
	func storedLegacyThemeIsRewrittenOnce() throws {
		let fixture = try PreferencesTransferFixture()
		defer { fixture.cleanUp() }
		let key = Preferences.Theme.transcriptTheme
		var legacy = TranscriptTheme.lines
		legacy.formatVersion = 1
		legacy.nicknameFormat = TranscriptTheme.legacyBracketedNicknameFormat
		try fixture.stores.set(.data(encoded(legacy)), for: key)

		let controller = makeController(fixture)
		controller.reload()
		#expect(controller.theme.nicknameFormat == TranscriptTheme.lines.nicknameFormat)
		let rewritten = try #require(fixture.stores[stored: key])
		#expect(try TranscriptTheme.decoded(from: rewritten).formatVersion == TranscriptTheme.currentFormatVersion)

		// The next launch reads a current document and has nothing to write.
		makeController(fixture).reload()
		#expect(fixture.stores[stored: key] == rewritten)

		// The brackets are a choice now, so they outlive the launch that made it.
		var chosen = controller.theme
		chosen.nicknameFormat = TranscriptTheme.legacyBracketedNicknameFormat
		#expect(controller.apply(chosen))
		let restarted = makeController(fixture)
		restarted.reload()
		#expect(restarted.theme.nicknameFormat == TranscriptTheme.legacyBracketedNicknameFormat)
	}

	@Test("A theme written before the timestamp role decodes it as its secondary text")
	func timestampRoleDefaultsToSecondaryText() throws {
		let fixture = try PreferencesTransferFixture()
		defer { fixture.cleanUp() }
		var theme = TranscriptTheme.lines
		theme.palette.secondaryText = AdaptiveTranscriptColor(
			light: TranscriptThemeColor(red: 0.1, green: 0.2, blue: 0.3),
			dark: TranscriptThemeColor(red: 0.4, green: 0.5, blue: 0.6)
		)
		var document = try #require(
			PropertyListSerialization.propertyList(from: encoded(theme), format: nil) as? [String: Any]
		)
		var palette = try #require(document["palette"] as? [String: Any])
		palette.removeValue(forKey: "timestampText")
		document["palette"] = palette
		let data = try PropertyListSerialization.data(fromPropertyList: document, format: .xml, options: 0)

		let controller = makeController(fixture)
		try controller.importTheme(from: data)
		#expect(controller.theme.palette.timestampText == theme.palette.secondaryText)
	}

	/** `appearanceDidChange()` had no callers, so the snapshot the transcript
	 resolves colours from off the main actor kept whichever appearance was in
	 effect when the theme last changed. */
	@Test("The published snapshot follows the appearance")
	func snapshotFollowsAppearance() throws {
		let fixture = try PreferencesTransferFixture()
		defer { fixture.cleanUp() }
		let controller = makeController(fixture)
		let appearance = SharedApplication.sharedAppearance()
		/* The stored value, not the effective one: restoring the effective value
		 writes the declared default into a preference the person never set, and
		 this is the live store the running application reads. */
		let previous = Preferences.Appearance.preferredAppearance.storedValue
		defer {
			Preferences.Appearance.preferredAppearance.storedValue = previous
			appearance.updateAppearance()
			SharedApplication.sharedThemeController().appearanceDidChange()
		}

		for preferred in [PreferredAppearance.dark, .light] {
			Preferences.Appearance.preferredAppearance.value = preferred
			appearance.updateAppearance()
			controller.appearanceDidChange()

			#expect(ThemeSnapshotStore.current.isDarkAppearance == (preferred == .dark))
		}
	}
}
