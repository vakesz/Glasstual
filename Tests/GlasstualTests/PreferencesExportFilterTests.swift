/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// Export used to strip every key that merely *had* a registered default,
/// which is 118 of the 167 exportable keys -- so an exported plist contained
/// almost nothing the user had chosen.
@Suite("Preference export filtering", .serialized)
@MainActor
struct PreferencesExportFilterTests {
	private static let key = "ScrollbackMaximumSavedLineCount"

	private func withRestoredValue(_ body: () -> Void) {
		let defaults = TextualUserDefaults.container
		let original = defaults.object(forKey: Self.key)
		defer {
			if let original {
				defaults.set(original, forKey: Self.key)
			} else {
				defaults.removeObject(forKey: Self.key)
			}
		}
		body()
	}

	@Test("A value the user changed is exported")
	func changedValueIsExported() {
		withRestoredValue {
			let registered = TextualPreferences.defaultPreferences()[Self.key]?.integer ?? 0
			TextualUserDefaults.container.set(registered + 1234, forKey: Self.key)

			let exported = PreferencesImportExport.exportedPreferencesDictionary(true, filterDefaults: true)
			#expect(exported[Self.key]?.integer == registered + 1234)
		}
	}

	@Test("A value equal to the registered default is not exported")
	func unchangedValueIsNotExported() {
		withRestoredValue {
			guard let registered = TextualPreferences.defaultPreferences()[Self.key] else {
				Issue.record("\(Self.key) has no registered default")
				return
			}
			TextualUserDefaults.container.set(registered.propertyListObject, forKey: Self.key)

			let exported = PreferencesImportExport.exportedPreferencesDictionary(true, filterDefaults: true)
			#expect(exported[Self.key] == nil)
		}
	}

	@Test("Without the defaults filter the value is exported either way")
	func unfilteredExportKeepsDefaults() {
		withRestoredValue {
			guard let registered = TextualPreferences.defaultPreferences()[Self.key] else {
				Issue.record("\(Self.key) has no registered default")
				return
			}
			TextualUserDefaults.container.set(registered.propertyListObject, forKey: Self.key)

			let exported = PreferencesImportExport.exportedPreferencesDictionary(false, filterDefaults: false)
			#expect(exported[Self.key] != nil)
		}
	}

	@Test("Comparison is by value, not by presence")
	func valueMatchesDefaultComparesValues() {
		#expect(PreferencesImportExport.valueMatchesDefault(42, 42))
		#expect(PreferencesImportExport.valueMatchesDefault(42, 43) == false)
		#expect(PreferencesImportExport.valueMatchesDefault("a", "a"))
		#expect(PreferencesImportExport.valueMatchesDefault(nil, 42) == false)
	}

	/// The theme key-value store's exclusion entry used the "equal" comparator
	/// while the real keys carry a store name suffix, so nothing ever matched.
	@Test("The theme key-value store is excluded from export")
	func themeKeyValueStoreIsExcluded() {
		#expect(
			TextualUserDefaults.keyIsExcludedFromExportImport(
				"Internal Theme Settings Key-value Store -> Some Theme"
			)
		)
	}
}
