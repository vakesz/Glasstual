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

/// Registration, import/export filtering, and storage routing are derived
/// directly from typed key declarations. No bundled catalogue mirrors them.
@Suite("Preference catalogue")
struct PreferenceCatalogTests {
	// MARK: - Declarations

	@Test("No preference name is declared twice")
	func namesAreUnique() {
		var seen: Set<String> = []

		for key in Preferences.allKeys {
			#expect(seen.insert(key.name).inserted, "\(key.name) is declared more than once")
		}
	}

	@Test("Every registered declaration reaches the registration domain with its default")
	func registeredDefaultsAreRegistered() {
		TextualPreferences.registerDefaults()

		let container = TextualUserDefaults.container
			.volatileDomain(forName: UserDefaults.registrationDomain)
		let standard = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)

		for key in Preferences.allKeys {
			// The default nickname is re-registered at launch with a random
			// suffix, so the domain deliberately does not hold the declaration.
			guard key.name != Preferences.Identity.nickname.name else {
				continue
			}

			guard let declared = key.registeredDefault else {
				continue
			}

			let domain = key.storage == .container ? container : standard

			guard let registered = domain[key.name].flatMap(PropertyListValue.init(propertyList:)) else {
				Issue.record("\(key.name) has a declared default but is not in the registration domain")
				continue
			}

			#expect(
				Self.valuesMatch(registered, declared),
				"\(key.name) registers \(registered) but declares \(declared)"
			)
		}
	}

	@Test("An unregistered declaration still reads back its declared default")
	func unregisteredDeclarationsFallBackToTheirDefault() {
		// "Notification Sound Is Muted" ships no registration-domain entry, so
		// the declared default is the only thing standing between a read and a
		// zero value.
		let key = Preferences.Notifications.soundIsMuted
		let original = key.storedValue
		defer { key.storedValue = original }

		key.reset()
		#expect(key.value == key.defaultValue)
	}

	// MARK: - Catalogue membership

	@Test("A name made at runtime is matched by its family")
	func familiesCoverRuntimeNames() {
		#expect(Preferences.isCatalogued("NotificationType -> Highlight -> Enabled"))
		#expect(Preferences.isCatalogued("Text Input Prompt Suppression -> some_prompt"))
		#expect(Preferences.isCatalogued("Something Glasstual Never Wrote") == false)
	}

	@Test("Internal state stays out of exports while the portable transcript theme stays in")
	func excludedFamiliesAreExcluded() {
		#expect(Preferences.isExcludedFromExport("Internal Theme Settings Key-value Store -> Lines"))
		#expect(Preferences.isExcludedFromExport("NSWindow Frame -> Internal (v3) -> Main Window"))
		#expect(Preferences.isExcludedFromExport("TextFieldSmartQuotes"))
		#expect(Preferences.isExcludedFromExport(Preferences.Theme.transcriptTheme.name) == false)
	}

	@Test("Storage follows the declaration, not the call site")
	func storageFollowsDeclarations() {
		#expect(Preferences.storage(for: "com.adiumX.AutoHyperlinks.permittedSchemes") == .standard)
		#expect(Preferences.storage(for: "NSWindow Frame -> Internal (v3) -> Main Window") == .standard)
		// Both of these used to read and write UserDefaults.standard while the
		// catalogue said they belonged in the container, so an imported value
		// never took effect.
		#expect(Preferences.storage(for: "Server Properties Window Sheet -> Include Advanced Encodings") == .container)
		#expect(Preferences.storage(for: "Optimizations -> Load History Lazily") == .container)
	}

	// MARK: - Helpers

	/** Archived colours are not byte-identical between two archives of the same
	 colour, and a number that was written as a real compares equal to the same
	 number written as an integer, so equality here is by value rather than by
	 representation. */
	private static func valuesMatch(_ lhs: PropertyListValue, _ rhs: PropertyListValue) -> Bool {
		if let lhs = PreferenceColor.preferenceValue(from: lhs.propertyListObject),
		   let rhs = PreferenceColor.preferenceValue(from: rhs.propertyListObject)
		{
			let components = [
				(lhs.red, rhs.red), (lhs.green, rhs.green),
				(lhs.blue, rhs.blue), (lhs.alpha, rhs.alpha),
			]

			return components.allSatisfy { abs($0.0 - $0.1) < 0.001 }
		}

		return (lhs.propertyListObject as AnyObject).isEqual(rhs.propertyListObject)
	}
}
