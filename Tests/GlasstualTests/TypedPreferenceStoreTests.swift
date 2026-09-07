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

		let defaults = TextualUserDefaults.container
		#expect(defaults.persistedObject(forKey: key.name) != nil)
	}

	@Test("A stored value of the wrong type reads as the declared default")
	func wrongTypeFallsBackToTheDeclaredDefault() {
		withScratchKeys {
			// The classic mistake this replaces is integer(forKey:) on a key
			// that holds a boolean, which silently reads zero.
			TextualUserDefaults.container.set(["not": "a number"], forKey: Self.intKey.name)
			#expect(Self.intKey.value == 7)
		}
	}

	@Test("An unknown enumeration case falls back to the declared default")
	func unknownEnumerationCaseFallsBack() {
		let key = Preferences.Input.tabKeyAction
		let original = key.storedValue
		defer { key.storedValue = original }

		TextualUserDefaults.container.set(9999, forKey: key.name)
		#expect(key.value == key.defaultValue)
	}

	/// Validation is driven by the catalogue, so these use declared keys rather
	/// than the scratch ones above.
	private static let declaredInt = Preferences.Appearance.trackUserAwayStatusMaximumChannelSize
	private static let declaredBool = Preferences.Messages.showJoinLeave

	@Test("Import coerces a number written as a string")
	func importCoercesStringsToNumbers() {
		#expect(
			Preferences.coerce("1", forKey: Self.declaredInt.name) == .integer(1)
		)
		#expect(
			Preferences.coerce("yes", forKey: Self.declaredBool.name) == .boolean(true)
		)
	}

	@Test("Import rejects a value the declaration cannot represent")
	func importRejectsGarbage() {
		#expect(Preferences.coerce("banana", forKey: Self.declaredInt.name) == nil)
		#expect(Preferences.coerce(["a", "b"], forKey: Self.declaredBool.name) == nil)
	}

	@Test("Integer preferences reject fractions, negative unsigned values and overflow")
	func integerConversionsAreExact() {
		for object: Any in [NSNumber(value: -1), NSNumber(value: 1.5), "-1", "1.5", "18446744073709551616"] {
			#expect(UInt.preferenceValue(from: object) == nil)
			#expect(UInt16.preferenceValue(from: object) == nil)
		}
		for object: Any in [NSNumber(value: UInt.max), NSNumber(value: 1.5), "9223372036854775808",
		                    "-9223372036854775809", "1.00000000000000000001"]
		{
			#expect(Int.preferenceValue(from: object) == nil)
		}
		#expect(UInt16.preferenceValue(from: 65536) == nil)
		#expect(UInt16.preferenceValue(from: "65536") == nil)
		#expect(Preferences.coerce("1.5", forKey: Self.declaredInt.name) == nil)
	}

	@Test("Legacy integral numbers and numeric strings retain their exact values")
	func legacyNumbersRemainReadable() {
		#expect(Int.preferenceValue(from: NSNumber(value: Int.max)) == Int.max)
		#expect(Int.preferenceValue(from: String(Int.min)) == Int.min)
		#expect(UInt.preferenceValue(from: NSNumber(value: UInt.max)) == UInt.max)
		#expect(UInt.preferenceValue(from: String(UInt.max)) == UInt.max)
		#expect(UInt.preferenceValue(from: "18446744073709551615.0") == UInt.max)
		#expect(Int.preferenceValue(from: "9007199254740993.0") == 9_007_199_254_740_993)
		for object: Any in [NSNumber(value: 42.0), "42", "42.0", "4.2e1", "+42", "420e-1"] {
			#expect(Int.preferenceValue(from: object) == 42)
			#expect(UInt.preferenceValue(from: object) == 42)
			#expect(UInt16.preferenceValue(from: object) == 42)
		}
		#expect(UInt16.preferenceValue(from: "65535") == 65535)
		#expect(Double.preferenceValue(from: "1.25e2") == 125)
		#expect(UInt16.preferenceValue(from: "0xFF") == 255)
		#expect(Int.preferenceValue(from: "0x1.5p5") == 42)
		#expect(UInt.preferenceValue(from: "0x20000000000001") == 9_007_199_254_740_993)
		#expect(UInt.preferenceValue(from: "0xFFFFFFFFFFFFFFFF") == UInt.max)
		#expect(Int.preferenceValue(from: "0x1.0000000000000001") == nil)
	}

	@Test("Non-finite preferences are rejected and invalid stored numbers use the declared default")
	func invalidNumbersPreserveDefaults() {
		for object: Any in [NSNumber(value: Double.nan), NSNumber(value: Double.infinity),
		                    NSNumber(value: -Double.infinity), "nan", "inf", "-inf", "1e999"]
		{
			#expect(Int.preferenceValue(from: object) == nil)
			#expect(UInt.preferenceValue(from: object) == nil)
			#expect(UInt16.preferenceValue(from: object) == nil)
			#expect(Double.preferenceValue(from: object) == nil)
		}
		withScratchKeys {
			TextualUserDefaults.container.set("7.5", forKey: Self.intKey.name)
			#expect(Self.intKey.value == 7)
			#expect(Self.intKey.storedValue == nil)
			TextualUserDefaults.container.set("4.2e1", forKey: Self.intKey.name)
			#expect(Self.intKey.value == 42)
		}
	}

	@Test("Writing a non-finite double leaves the previous preference intact")
	func nonFiniteDoubleIsNotStored() {
		let key = PreferenceKey("Tests -> Typed Store -> Double", default: 2.5,
		                        traits: [.unregistered, .uncatalogued])
		defer { key.reset() }
		key.value = 4.5
		for value in [Double.nan, .infinity, -.infinity] {
			key.value = value
			#expect(key.value == 4.5)
		}
	}

	@Test("A key the catalogue does not know keeps whatever shape it was written with")
	func importPassesThroughUnknownKeys() {
		let payload: PropertyListValue = ["anything": 1]
		let validated = Preferences.coerce(payload, forKey: "Some Plugin -> Its Own Key")

		#expect(validated?.dictionary?["anything"]?.integer == 1)
	}

	@Test("Highlight keywords keep their stored record shape")
	func highlightKeywordsRoundTrip() {
		let key = Preferences.Highlights.matchKeywords
		let original = key.storedValue
		defer { key.storedValue = original }

		key.value = [HighlightKeyword(string: "alpha"), HighlightKeyword(string: "beta")]

		let stored = PropertyListValue(
			propertyList: TextualUserDefaults.container.object(forKey: key.name) ?? []
		)?.array
		#expect(
			stored?.compactMap { $0.dictionary?[HighlightKeyword.field]?.string } == ["alpha", "beta"]
		)
		#expect(key.value.map(\.string) == ["alpha", "beta"])
	}
}

/// Export used to filter by name and to read the whole search list. It now reads
/// the declarations: a complete snapshot of every exportable key, and nothing
/// that describes this Mac rather than the user's settings.
@Suite("Preference export contents", .serialized)
@MainActor
struct PreferenceExportContentsTests {
	private var snapshot: PreferencesArchive {
		PreferencesTransferStores.live.snapshot(clients: [])
	}

	private func withRestored(_ key: PreferenceKey<some Any>, _ body: () -> Void) {
		let original = key.storedValue
		defer { key.storedValue = original }
		body()
	}

	@Test("A changed value is exported, and so is one left at its default")
	func exportCarriesEveryExportableValue() {
		let key = Preferences.Appearance.trackUserAwayStatusMaximumChannelSize

		withRestored(key) {
			key.value = key.defaultValue + 11
			#expect(snapshot.values[key.name]?.integer == Int(key.defaultValue) + 11)

			key.reset()
			#expect(snapshot.values[key.name] == key.registeredDefault)
			#expect(snapshot.unset.contains(key.name) == false)
		}
	}

	@Test("An excluded key is never exported, however it was written")
	func excludedKeysAreNotExported() {
		let excluded = Preferences.Internals.runCount
		let suppression = "Text Input Prompt Suppression -> tests_export"
		let themeStore = "Internal Theme Settings Key-value Store -> Lines"

		let original = excluded.storedValue
		defer { excluded.storedValue = original }

		excluded.value = 12345
		TextualUserDefaults.container.set(true, forKey: suppression)
		TextualUserDefaults.container.set(["setting": true], forKey: themeStore)
		defer {
			TextualUserDefaults.container.removeObject(forKey: suppression)
			TextualUserDefaults.container.removeObject(forKey: themeStore)
		}

		let exported = snapshot
		for name in [excluded.name, suppression, themeStore] {
			#expect(exported.values[name] == nil)
			#expect(exported.unset.contains(name) == false)
		}
	}

	@Test("A key outside the catalogue is not exported")
	func uncataloguedKeysAreNotExported() {
		let name = "Tests -> Not In The Catalogue"
		TextualUserDefaults.container.set("value", forKey: name)
		defer { TextualUserDefaults.container.removeObject(forKey: name) }

		#expect(snapshot.values[name] == nil)
		#expect(snapshot.unset.contains(name) == false)
	}
}
