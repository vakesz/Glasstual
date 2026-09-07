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

/** Export used to strip every key that merely *had* a registered default,
 which is most of the exportable ones — so an exported plist contained almost
 nothing the user had chosen. It is now a complete snapshot: what a setting
 *is*, plus the names deliberately left unset, so a restore can tell "the
 shipped default" from "the user cleared this". */
@Suite("Preference export scope", .serialized)
@MainActor
struct PreferencesExportFilterTests {
	private static let key = Preferences.Logging.scrollbackSaveLimit

	private var snapshot: PreferencesArchive {
		PreferencesTransferStores.live.snapshot(clients: [])
	}

	private func withRestoredValue(_ body: () -> Void) {
		let original = Self.key.storedValue
		defer { Self.key.storedValue = original }
		body()
	}

	@Test("A value the user changed is exported")
	func changedValueIsExported() {
		withRestoredValue {
			Self.key.value = Self.key.defaultValue + 1234

			#expect(snapshot.values[Self.key.name]?.integer == Int(Self.key.defaultValue) + 1234)
			#expect(snapshot.unset.contains(Self.key.name) == false)
		}
	}

	@Test("A value equal to the registered default is exported too")
	func unchangedValueIsExportedAsWell() {
		withRestoredValue {
			Self.key.reset()

			#expect(snapshot.values[Self.key.name] == Self.key.registeredDefault)
			#expect(snapshot.unset.contains(Self.key.name) == false)
		}
	}

	/// A key that ships with no registered default at all has nothing to fall
	/// back to, so its absence is what the file has to carry.
	@Test("A key with nothing written and nothing registered is listed as unset")
	func unwrittenKeysAreListedAsUnset() {
		let key = Preferences.FileTransfers.manuallyEnteredIPAddress
		let original = key.storedValue
		defer { key.storedValue = original }
		key.reset()

		#expect(key.registeredDefault == nil)
		#expect(snapshot.values[key.name] == nil)
		#expect(snapshot.unset.contains(key.name))
	}

	/// The theme key-value store's exclusion entry used the "equal" comparator
	/// while the real keys carry a store name suffix, so nothing ever matched.
	@Test("The theme key-value store is excluded from export")
	func themeKeyValueStoreIsExcluded() {
		let name = "Internal Theme Settings Key-value Store -> Some Theme"
		TextualUserDefaults.container.set(["setting": true], forKey: name)
		defer { TextualUserDefaults.container.removeObject(forKey: name) }

		#expect(Preferences.isExcludedFromExport(name))
		#expect(snapshot.values[name] == nil)
		#expect(snapshot.unset.contains(name) == false)
	}
}
