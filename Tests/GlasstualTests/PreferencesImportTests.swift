/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/** The export side is covered by `PreferencesExportFilterTests`; this is the
 way back in. An imported plist is a file the user was handed, so what matters
 is that a value it carries actually lands in the store, that a value the
 declaration cannot represent does not, and that the keys export deliberately
 withholds are refused on the way in as well as on the way out.

 Every key here routes to the container, which the test scheme redirects to its
 own suite. A `.standard`-storage key would be written to the developer's own
 defaults domain by `importValue`, so none is used. */
@Suite("Preference import", .serialized)
@MainActor
struct PreferencesImportTests {
	private static let integerKey = Preferences.Logging.scrollbackSaveLimit
	private static let booleanKey = Preferences.Messages.showJoinLeave
	private static let excludedKey = Preferences.MainWindow.serverListSelection

	private func withRestoredValues(
		_ keys: [String],
		_ body: () -> Void
	) {
		let defaults = TextualUserDefaults.container
		let originals = keys.map { defaults.object(forKey: $0) }
		defer {
			for (key, original) in zip(keys, originals) {
				if let original {
					defaults.set(original, forKey: key)
				} else {
					defaults.removeObject(forKey: key)
				}
			}
		}

		body()
	}

	@Test("An imported value lands in the store the key is declared against")
	func importedValuesLand() {
		withRestoredValues([Self.integerKey.name, Self.booleanKey.name]) {
			Self.integerKey.reset()
			Self.booleanKey.reset()

			PreferencesImportExport.importContentsOfDictionary(
				[
					Self.integerKey.name: 4321,
					/* `showJoinLeave` ships on, so importing `false` is the case
						that distinguishes a value that landed from one that did not. */
					Self.booleanKey.name: false,
				],
				reloadPreferences: false
			)

			#expect(Self.integerKey.value == 4321)
			#expect(Self.booleanKey.defaultValue)
			#expect(Self.booleanKey.value == false)
		}
	}

	/// A hand-edited plist writes numbers and booleans as strings; the
	/// declaration is what says which of those are the same value.
	@Test("A value written as a string is coerced to the declared type")
	func stringsAreCoercedToTheDeclaredType() {
		withRestoredValues([Self.integerKey.name, Self.booleanKey.name]) {
			Self.integerKey.reset()
			Self.booleanKey.reset()

			PreferencesImportExport.importValue("8765", withKey: Self.integerKey.name)
			PreferencesImportExport.importValue("yes", withKey: Self.booleanKey.name)

			#expect(Self.integerKey.value == 8765)
			#expect(Self.booleanKey.value)
		}
	}

	/// `storedValue` falls through to the registration domain, so what says a
	/// rejected value was not written is the suite's own persistent domain.
	@Test("A value the declaration cannot represent is not written at all")
	func unrepresentableValuesAreNotWritten() {
		withRestoredValues([Self.integerKey.name]) {
			let defaults = TextualUserDefaults.container
			Self.integerKey.reset()

			PreferencesImportExport.importValue(["not": "a number"], withKey: Self.integerKey.name)

			#expect(defaults.persistedObject(forKey: Self.integerKey.name) == nil)
			#expect(Self.integerKey.value == Self.integerKey.defaultValue)
		}
	}

	/** Window position, the selected row and the other restoration state are
	 excluded from an export because they describe this Mac rather than the
	 user's settings. Importing one would move somebody else's window state onto
	 this machine, so the same list is applied in both directions. */
	@Test("A key excluded from export is skipped on the way in")
	func excludedKeysAreSkipped() {
		#expect(PreferencesImportExport.isKeyNameSupposedToBeIgnored(Self.excludedKey.name))
		#expect(PreferencesImportExport.isKeyNameSupposedToBeIgnored(Self.integerKey.name) == false)

		withRestoredValues([Self.excludedKey.name, Self.integerKey.name]) {
			Self.excludedKey.reset()
			Self.integerKey.reset()

			PreferencesImportExport.importContentsOfDictionary(
				[
					Self.excludedKey.name: "someone-elses-row",
					Self.integerKey.name: 2468,
				],
				reloadPreferences: false
			)

			#expect(Self.excludedKey.storedValue == nil)
			/* The rest of the dictionary is imported all the same. */
			#expect(Self.integerKey.value == 2468)
		}
	}

	/// A plugin's own key has no declaration to validate against, so it is
	/// carried across with whatever shape it was written with.
	@Test("A key the catalogue does not know is imported as it stands")
	func unknownKeysAreImportedUnchanged() {
		let name = "Tests -> Import -> Unknown Plugin Key"
		let defaults = TextualUserDefaults.container
		defer { defaults.removeObject(forKey: name) }

		PreferencesImportExport.importValue(["anything": 1], withKey: name)

		#expect(defaults.dictionary(forKey: name)?["anything"] as? Int == 1)
	}
}
