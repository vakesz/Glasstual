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

import Foundation
@testable import Glasstual
import Testing

/// The typed store is what removes the force-unwrapped reads and the
/// integer-read-of-a-boolean class of mistake, so these check that a declared
/// type actually decides what a read and an import produce.
@Suite("Typed preference store", .serialized)
@MainActor
struct TypedPreferenceStoreTests {
	private static let boolKey = PreferenceKey(
		"Tests -> Typed Store -> Flag",
		default: true,
		traits: [.unregistered, .uncatalogued]
	)

	private static let intKey = PreferenceKey(
		"Tests -> Typed Store -> Count",
		default: 7,
		traits: [.unregistered, .uncatalogued]
	)

	private func withScratchKeys(_ body: () -> Void) {
		defer {
			Self.boolKey.reset()
			Self.intKey.reset()
		}

		Self.boolKey.reset()
		Self.intKey.reset()
		body()
	}

	@Test("A read with nothing stored returns the declared default")
	func defaultIsReturnedWhenNothingIsStored() {
		withScratchKeys {
			#expect(Self.boolKey.value == true)
			#expect(Self.intKey.value == 7)
			#expect(Self.boolKey.storedValue == nil)
		}
	}

	@Test("A written value round-trips through the store")
	func writtenValueRoundTrips() {
		withScratchKeys {
			Self.intKey.value = 42
			#expect(Self.intKey.value == 42)
			#expect(Self.intKey.storedValue == 42)
		}
	}

	/// `TextualUserDefaults.set` compared against `object(forKey:)`, which falls
	/// through to the registration domain, so writing a value that happened to
	/// equal the shipped default persisted nothing at all.
	@Test("A value equal to the registered default is still persisted")
	func writingTheDefaultStillPersists() {
		let key = Preferences.Logging.scrollbackSaveLimit
		let original = key.storedValue
		defer { key.storedValue = original }

		key.reset()
		key.value = key.defaultValue

		let defaults = TextualUserDefaults.shared()
		#expect(defaults.persistentDomain(forName: defaults.suiteName)?[key.name] != nil)
	}

	@Test("A stored value of the wrong type reads as the declared default")
	func wrongTypeFallsBackToTheDeclaredDefault() {
		withScratchKeys {
			// The classic mistake this replaces is integer(forKey:) on a key
			// that holds a boolean, which silently reads zero.
			TextualUserDefaults.shared().set(["not": "a number"], forKey: Self.intKey.name)
			#expect(Self.intKey.value == 7)
		}
	}

	@Test("An unknown enumeration case falls back to the declared default")
	func unknownEnumerationCaseFallsBack() {
		let key = Preferences.Input.tabKeyAction
		let original = key.storedValue
		defer { key.storedValue = original }

		TextualUserDefaults.shared().set(9999, forKey: key.name)
		#expect(key.value == key.defaultValue)
	}

	/// Validation is driven by the catalogue, so these use declared keys rather
	/// than the scratch ones above.
	private static let declaredInt = Preferences.Appearance.trackUserAwayStatusMaximumChannelSize
	private static let declaredBool = Preferences.Messages.showJoinLeave

	@Test("Import coerces a number written as a string")
	func importCoercesStringsToNumbers() {
		#expect(
			PreferencesImportExport.validatedValue("1", forKey: Self.declaredInt.name) as? NSNumber
				== NSNumber(value: 1)
		)
		#expect(
			PreferencesImportExport.validatedValue("yes", forKey: Self.declaredBool.name) as? NSNumber
				== NSNumber(value: true)
		)
	}

	@Test("Import rejects a value the declaration cannot represent")
	func importRejectsGarbage() {
		#expect(PreferencesImportExport.validatedValue("banana", forKey: Self.declaredInt.name) == nil)
		#expect(PreferencesImportExport.validatedValue(["a", "b"], forKey: Self.declaredBool.name) == nil)
	}

	@Test("A key the catalogue does not know keeps whatever shape it was written with")
	func importPassesThroughUnknownKeys() {
		let payload: [String: Any] = ["anything": 1]
		let validated = PreferencesImportExport.validatedValue(payload, forKey: "Some Plugin -> Its Own Key")

		#expect((validated as? [String: Any])?["anything"] as? Int == 1)
	}

	@Test("Highlight keywords keep their stored record shape")
	func highlightKeywordsRoundTrip() {
		let key = Preferences.Highlights.matchKeywords
		let original = key.storedValue
		defer { key.storedValue = original }

		key.value = [HighlightKeyword(string: "alpha"), HighlightKeyword(string: "beta")]

		let stored = TextualUserDefaults.shared().object(forKey: key.name) as? [[String: Any]]
		#expect(stored?.compactMap { $0[HighlightKeyword.field] as? String } == ["alpha", "beta"])
		#expect(key.value.map(\.string) == ["alpha", "beta"])
	}
}

/// Export used to filter by name and to read the whole search list. It now reads
/// what the user actually wrote and compares it against the declared default.
@Suite("Preference export contents", .serialized)
@MainActor
struct PreferenceExportContentsTests {
	private func withRestored(_ key: PreferenceKey<some Any>, _ body: () -> Void) {
		let original = key.storedValue
		defer { key.storedValue = original }
		body()
	}

	@Test("A changed value is exported and an unchanged default is not")
	func exportCarriesOnlyChangedValues() {
		let key = Preferences.Appearance.trackUserAwayStatusMaximumChannelSize

		withRestored(key) {
			key.value = key.defaultValue + 11
			var exported = PreferencesImportExport.exportedPreferencesDictionary(true, filterDefaults: true)
			#expect(exported[key.name] as? Int == Int(key.defaultValue) + 11)

			key.value = key.defaultValue
			exported = PreferencesImportExport.exportedPreferencesDictionary(true, filterDefaults: true)
			#expect(exported[key.name] == nil)
		}
	}

	@Test("An excluded key is never exported, however it was written")
	func excludedKeysAreNotExported() {
		let excluded = Preferences.Internals.runCount
		let suppression = "Text Input Prompt Suppression -> tests_export"

		let original = excluded.storedValue
		defer { excluded.storedValue = original }

		excluded.value = 12345
		TextualUserDefaults.shared().set(true, forKey: suppression)
		defer { TextualUserDefaults.shared().removeObject(forKey: suppression) }

		let exported = PreferencesImportExport.exportedPreferencesDictionary(true, filterDefaults: true)

		#expect(exported[excluded.name] == nil)
		#expect(exported[suppression] == nil)
		#expect(exported["Internal Theme Settings Key-value Store -> Lines"] == nil)
	}

	@Test("A key outside the catalogue is not exported")
	func uncataloguedKeysAreNotExported() {
		let name = "Tests -> Not In The Catalogue"
		TextualUserDefaults.shared().set("value", forKey: name)
		defer { TextualUserDefaults.shared().removeObject(forKey: name) }

		let exported = PreferencesImportExport.exportedPreferencesDictionary(true, filterDefaults: true)
		#expect(exported[name] == nil)
	}
}
