/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import ObjectiveC.runtime
import XCTest

@MainActor
final class PreferencesControllerMigrationTests: XCTestCase {
	/// A pane the sidebar cannot reach is a pane nobody can open.
	func testPaneCatalogCoversEveryDeclaredPane() {
		XCTAssertEqual(Set(PreferencesPaneCatalog.panes.map(\.identifier)), Set(PreferencesPaneIdentifier.allCases))
	}

	func testPluginIdentifiersRoundTripAndRejectMalformedValues() {
		XCTAssertEqual(PreferencesPaneCatalog.pluginIdentifier(at: 7), "plugin-7")
		XCTAssertEqual(PreferencesPaneCatalog.pluginIndex(from: "plugin-7"), 7)
		XCTAssertNil(PreferencesPaneCatalog.pluginIndex(from: "plugin-seven"))
		XCTAssertNil(PreferencesPaneCatalog.pluginIndex(from: "general"))
	}

	func testNumericValidationKeepsEstablishedBounds() {
		XCTAssertEqual(PreferencesValueValidation.clamped(1, to: PreferencesValueValidation.scrollbackSaveRange), 100)
		XCTAssertEqual(
			PreferencesValueValidation.clamped(80000, to: PreferencesValueValidation.scrollbackSaveRange),
			50000
		)
		XCTAssertEqual(
			PreferencesValueValidation
				.clamped(0, to: PreferencesValueValidation.scrollbackVisibleRange, allowingZero: true),
			0
		)
		XCTAssertEqual(PreferencesValueValidation.clamped(1, to: PreferencesValueValidation.inlineMediaWidthRange), 40)
		XCTAssertEqual(
			PreferencesValueValidation.clamped(70000, to: PreferencesValueValidation.fileTransferPortRange),
			65535
		)
	}
}
