/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Preferences pane catalog and validation")
struct PreferencesControllerMigrationTests {
	/// A pane the sidebar cannot reach is a pane nobody can open.
	@Test("The catalog covers every declared pane")
	func paneCatalogCoversEveryDeclaredPane() {
		#expect(Set(PreferencesPaneCatalog.panes.map(\.identifier)) == Set(PreferencesPaneIdentifier.allCases))
	}

	@Test("A plugin identifier round trips, and a malformed one is rejected")
	func pluginIdentifiersRoundTripAndRejectMalformedValues() {
		#expect(PreferencesPaneCatalog.pluginIdentifier(at: 7) == "plugin-7")
		#expect(PreferencesPaneCatalog.pluginIndex(from: "plugin-7") == 7)
		#expect(PreferencesPaneCatalog.pluginIndex(from: "plugin-seven") == nil)
		#expect(PreferencesPaneCatalog.pluginIndex(from: "general") == nil)
	}

	@Test("Numeric preferences are clamped to their established bounds")
	func numericValidationKeepsEstablishedBounds() {
		#expect(PreferencesValueValidation.clamped(1, to: PreferencesValueValidation.scrollbackSaveRange) == 100)
		#expect(
			PreferencesValueValidation.clamped(80000, to: PreferencesValueValidation.scrollbackSaveRange)
				== 50000
		)
		#expect(
			PreferencesValueValidation
				.clamped(0, to: PreferencesValueValidation.scrollbackVisibleRange, allowingZero: true)
				== 0
		)
		#expect(PreferencesValueValidation.clamped(1, to: PreferencesValueValidation.inlineMediaWidthRange) == 40)
		#expect(
			PreferencesValueValidation.clamped(70000, to: PreferencesValueValidation.fileTransferPortRange)
				== 65535
		)
	}
}
