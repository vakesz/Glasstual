/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import ObjectiveC.runtime
import XCTest

@MainActor
final class PreferencesControllerMigrationTests: XCTestCase {
	func testObjectiveCRuntimeNamesRemainStable() {
		XCTAssertEqual(NSStringFromClass(PreferencesController.self), "TDCPreferencesController")
		XCTAssertEqual(NSStringFromProtocol(PreferencesControllerDelegate.self), "TDCPreferencesControllerDelegate")
	}

	func testCallerAndNibSelectorsRemainAvailable() {
		let selectors = [
			"show:", "settingsSidebarCatalog", "viewForSettingsPaneIdentifier:", "windowWillClose:",
			"onAddExcludeKeyword:", "onAddHighlightKeyword:", "onChangedAppearance:",
			"onChangedChannelViewArrangement:", "onChangedDisableNicknameColorHashing:",
			"onChangedForwardNoticeTo:", "onChangedHighlightLogging:", "onChangedHighlightType:",
			"onChangedInlineMediaOption:", "onChangedInputHistoryScheme:",
			"onChangedMainInputTextViewFontSize:", "onChangedScrollbackSaveLimit:",
			"onChangedScrollbackVisibleLimit:", "onChangedServerListUnreadBadgeColor:",
			"onChangedTheme:", "onChangedThemeSelection:", "onChangedTranscriptFolder:",
			"onChangedUserListModeColor:", "onChangedUserListModeSortOrder:",
			"onFileTransferDownloadDestinationFolderChanged:",
			"onFileTransferIPAddressDetectionMethodChanged:", "onModifyUserStyleSheetRules:",
			"onOpenPathToScripts:", "onOpenPathToTheme:",
			"onResetServerListUnreadBadgeColorsToDefault:",
			"onResetUserListModeColorsToDefaults:", "onSelectNewFont:",
		]
		for selector in selectors {
			XCTAssertTrue(PreferencesController.instancesRespond(to: NSSelectorFromString(selector)), selector)
		}

		let metaClass: AnyClass? = try? XCTUnwrap(object_getClass(PreferencesController.self))
		XCTAssertTrue(metaClass.map { class_respondsToSelector(
			$0,
			NSSelectorFromString("openProxySettingsInSystemPreferences")
		) } ?? false)
	}

	func testPaneCatalogKeepsEveryBuiltInPaneAndCompatibilityEntry() {
		XCTAssertEqual(PreferencesPaneCatalog.panes.count, 19)
		XCTAssertEqual(PreferencesPaneCatalog.descriptor(for: "general")?.group, .main)
		XCTAssertEqual(PreferencesPaneCatalog.descriptor(for: "addons")?.group, .addOns)
		XCTAssertEqual(
			PreferencesPaneCatalog.descriptor(for: "compatibility")?.contentViewKey,
			"contentViewCompatibility"
		)
		XCTAssertEqual(PreferencesPaneCatalog.descriptor(for: "hidden")?.group, .advanced)
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
