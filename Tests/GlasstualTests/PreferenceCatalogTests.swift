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

/** The registration domain and the three catalogue plists are generated from the
 key declarations. `scripts/generate-preference-plists.sh` writes the five files
 -- it runs as a build phase of the application and as `make
 generate-preference-plists` -- by compiling the very declarations these tests
 read, so what the bundle carries is that script's output and never a hand edit.

 These tests are what makes the checked-in copies safe to keep for the tools
 that read them: a declaration added, removed or re-typed without the generator
 having been re-run fails here rather than at launch. */
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

	// MARK: - Generated resources

	enum Catalogue: String, CaseIterable, Sendable {
		case keyCatalog = "PreferenceKeyMasterList"
		case excludedFromContainer = "KeysExcludedFromContainer"
		case excludedFromExport = "KeysExcludedFromExport"

		var generated: [String: PropertyListValue] {
			switch self {
			case .keyCatalog: Preferences.GeneratedResources.keyCatalog
			case .excludedFromContainer: Preferences.GeneratedResources.keysExcludedFromContainer
			case .excludedFromExport: Preferences.GeneratedResources.keysExcludedFromExport
			}
		}
	}

	@Test("The checked-in catalogue plists match the declarations", arguments: Catalogue.allCases)
	func cataloguePlistsMatchDeclarations(catalogue: Catalogue) throws {
		let name = catalogue.rawValue
		let generated = catalogue.generated
		let storedValues = try #require(Self.plist(named: name))

		let generatedNames = Set(generated.keys)
		let storedNames = Set(storedValues.keys)

		#expect(
			generatedNames.subtracting(storedNames).sorted() == [],
			"\(name).plist is missing declared entries"
		)
		#expect(
			storedNames.subtracting(generatedNames).sorted() == [],
			"\(name).plist has entries no declaration produces"
		)

		for (key, value) in storedValues {
			guard let expected = generated[key] else {
				continue
			}

			#expect(value == expected, "\(name).plist stores comparator \(value) for \(key)")
		}
	}

	@Test(
		"The checked-in registration plists match the declarations",
		arguments: [
			("RegisteredUserDefaults", PreferenceStorage.standard),
			("RegisteredUserDefaultsInContainer", PreferenceStorage.container),
		]
	)
	func registrationPlistsMatchDeclarations(name: String, storage: PreferenceStorage) throws {
		let stored = try #require(Self.plist(named: name))
		let generated = Preferences.registrationDomain(for: storage)

		#expect(
			Set(generated.keys).subtracting(stored.keys).sorted() == [],
			"\(name).plist is missing declared defaults"
		)
		#expect(
			Set(stored.keys).subtracting(generated.keys).sorted() == [],
			"\(name).plist declares defaults no key produces"
		)

		for (key, value) in stored {
			guard let declared = generated[key] else {
				continue
			}

			#expect(Self.valuesMatch(value, declared), "\(name).plist stores a different default for \(key)")
		}
	}

	/** The generator writes five files and only those five. A sixth plist in
	 the directory is one nothing derives, which is exactly the hand-maintained
	 state the generator replaced -- and the drift tests above would not see it,
	 because they only look at names they already know. */
	@Test("The Preferences resource directory holds only generated plists")
	func preferencesDirectoryHoldsOnlyGeneratedPlists() throws {
		let generated = Set(
			Catalogue.allCases.map(\.rawValue) + ["RegisteredUserDefaults", "RegisteredUserDefaultsInContainer"]
		)

		let directory = try #require(
			Bundle.main.url(forResource: "PreferenceKeyMasterList", withExtension: "plist", subdirectory: "Preferences")
		).deletingLastPathComponent()

		let contents = try FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: nil
		)

		let names = Set(contents.map { $0.deletingPathExtension().lastPathComponent })

		#expect(
			names.subtracting(generated).sorted() == [],
			"the Preferences resource directory carries files the generator does not write"
		)
		#expect(generated.subtracting(names).sorted() == [], "a generated plist is missing from the bundle")
	}

	// MARK: - Catalogue membership

	@Test("A name made at runtime is matched by its family")
	func familiesCoverRuntimeNames() {
		#expect(Preferences.isCatalogued("NotificationType -> Highlight -> Enabled"))
		#expect(Preferences.isCatalogued("Text Input Prompt Suppression -> some_prompt"))
		#expect(Preferences.isCatalogued("Something Glasstual Never Wrote") == false)
	}

	@Test("The theme key-value store and the window frames stay out of an export")
	func excludedFamiliesAreExcluded() {
		#expect(Preferences.isExcludedFromExport("Internal Theme Settings Key-value Store -> Lines"))
		#expect(Preferences.isExcludedFromExport("NSWindow Frame -> Internal (v3) -> Main Window"))
		#expect(Preferences.isExcludedFromExport("TextFieldSmartQuotes"))
		#expect(Preferences.isExcludedFromExport("Theme -> Name") == false)
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

	private static func plist(named name: String) -> [String: PropertyListValue]? {
		guard let url = Bundle.main.url(
			forResource: name,
			withExtension: "plist",
			subdirectory: "Preferences"
		),
			let contents = try? Data(contentsOf: url),
			let plist = try? PropertyListSerialization.propertyList(from: contents, format: nil)
		else {
			return nil
		}

		return [String: PropertyListValue](propertyList: plist)
	}

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
