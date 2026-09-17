// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
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
		PreferenceRegistration.registerDefaults()

		let container = GlasstualUserDefaults.container
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
		#expect(Preferences.isExcludedFromExport(Preferences.Theme.transcriptTheme.name) == false)
	}

	/// A `TextField` family used to exclude all nine text-system settings from
	/// export, and `isExcludedFromExport` gates import too, so three checkboxes
	/// in Settings -> Controls neither left nor entered a configuration file.
	@Test("The input text-system settings are portable")
	func textSystemSettingsAreExported() {
		for key in [
			Preferences.Input.automaticSpellCheck,
			Preferences.Input.automaticGrammarCheck,
			Preferences.Input.automaticSpellCorrection,
			Preferences.Input.smartCopyPaste,
			Preferences.Input.smartQuotes,
			Preferences.Input.smartDashes,
			Preferences.Input.smartLinks,
			Preferences.Input.dataDetectors,
			Preferences.Input.textReplacement,
		] {
			#expect(Preferences.isExcludedFromExport(key.name) == false)
		}
	}

	/// The IRCv3 pane writes this one, so a user who switched a capability off
	/// expects it switched off on the machine they import the file into.
	@Test("The list of switched-off IRCv3 capabilities is catalogued and portable")
	func disabledCapabilitiesAreCataloguedAndExported() {
		let key = Preferences.Connection.disabledCapabilities

		#expect(Preferences.key(named: key.name) != nil)
		#expect(Preferences.isCatalogued(key.name))
		#expect(Preferences.isExcludedFromExport(key.name) == false)
		#expect(key.defaultValue.isEmpty)
	}

	@Test("Storage follows the declaration, not the call site")
	func storageFollowsDeclarations() {
		#expect(Preferences.storage(for: "Link Schemes -> Permitted") == .standard)
		#expect(Preferences.storage(for: "NSWindow Frame -> Internal (v3) -> Main Window") == .standard)
		// Both of these used to read and write UserDefaults.standard while the
		// catalogue said they belonged in the container, so an imported value
		// never took effect.
		#expect(Preferences.storage(for: "Server Properties Window Sheet -> Include Advanced Encodings") == .container)
		#expect(Preferences.storage(for: "Optimizations -> Load History Lazily") == .container)
	}

	// MARK: - Helpers

	@Test("Legacy NSColor preferences become versioned Codable colors when saved")
	func legacyColorsRemainReadable() throws {
		let original = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
		let legacy = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true)
		let color = try #require(PreferenceColor.preferenceValue(from: legacy))
		let rewritten = try #require(color.preferenceObject as? Data)
		let propertyList = try #require(PropertyListSerialization.propertyList(from: rewritten, format: nil) as? [String: Any])
		#expect(propertyList["version"] as? Int == 1)
		#expect(propertyList["$archiver"] == nil)
		#expect(PreferenceColor.preferenceValue(from: rewritten) == color)
		#expect(abs(color.red - 0.2) < 0.001)
		#expect(abs(color.green - 0.4) < 0.001)
		#expect(abs(color.blue - 0.6) < 0.001)
		#expect(abs(color.alpha - 0.8) < 0.001)
	}

	@Test("Colors reject unsupported payload versions and nonfinite components")
	func invalidStoredColorsAreRejected() throws {
		let color = PreferenceColor(red: 0.2, green: 0.4, blue: 0.6)
		let data = try #require(color.preferenceObject as? Data)
		var propertyList = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
		propertyList["version"] = 2
		let unsupported = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .binary, options: 0)
		#expect(PreferenceColor.preferenceValue(from: unsupported) == nil)
		#expect(PreferenceColor(red: .nan, green: 0, blue: 0).preferenceObject == nil)
		propertyList["version"] = 1
		propertyList["color"] = ["red": Double.infinity, "green": 0, "blue": 0, "alpha": 1]
		let nonfinite = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .binary, options: 0)
		#expect(PreferenceColor.preferenceValue(from: nonfinite) == nil)
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

/** Each domain lists the keys it declares, and `Preferences.allDomains` lists
 the domains. Swift cannot enumerate static members, so what would otherwise be
 an unchecked hand-kept list is checked here against the declarations
 themselves: the source of the `Keys` directory is read back and every declared
 key has to reach its domain's list, and every domain has to reach the
 catalogue. */
@Suite("Preference declaration lists")
struct PreferenceDeclarationListTests {
	/// One domain as its source file declares it.
	private struct Domain {
		let name: String
		/// The properties declared as keys, in declaration order.
		let declared: [String]
		/// The text of the `all` list, or `nil` for a domain that has none.
		let registration: String?
	}

	private static let keysDirectory = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.appending(path: "Sources/App/Preferences/Keys")

	private static func domains() throws -> [Domain] {
		let names = try FileManager.default.contentsOfDirectory(atPath: keysDirectory.path())
			.filter { $0.hasPrefix("Preferences+") && $0.hasSuffix(".swift") }
			.sorted()
		try #require(names.isEmpty == false, "no preference declarations at \(keysDirectory.path())")

		return try names.flatMap { name -> [Domain] in
			let source = try String(contentsOf: keysDirectory.appending(path: name), encoding: .utf8)
			return source.components(separatedBy: "\n\tenum ").dropFirst().compactMap { block in
				guard let name = block.prefix(while: { $0 != " " }).nilIfEmpty else { return nil }
				let halves = block.components(separatedBy: "\n\t\tstatic let all: [any AnyPreferenceKey]")
				return Domain(
					name: String(name),
					declared: declaredKeys(in: halves[0]),
					registration: halves.count > 1 ? halves[1] : nil
				)
			}
		}
	}

	/// The properties a block declares as preference keys, by the shape of the
	/// declaration rather than by its type, which the source does not spell.
	private static func declaredKeys(in block: String) -> [String] {
		block.components(separatedBy: "\n\t\tstatic let ").dropFirst().compactMap { declaration in
			let parts = declaration.components(separatedBy: " = ")
			guard parts.count > 1,
			      parts[1].hasPrefix("PreferenceKey(") || parts[1].hasPrefix("UntypedPreferenceKey(")
			else { return nil }
			return parts[0].split(separator: ":", maxSplits: 1).first?.nilIfEmpty.map(String.init)
		}
	}

	@Test("Every declared key reaches its own domain's list")
	func declaredKeysAreRegistered() throws {
		for domain in try Self.domains() where domain.declared.isEmpty == false {
			let registration = try #require(
				domain.registration,
				"\(domain.name) declares keys but has no list of them"
			)
			for key in domain.declared {
				#expect(
					registration.contains(key),
					"Preferences.\(domain.name).\(key) is declared but is in no list"
				)
			}
		}
	}

	@Test("Every domain that declares keys reaches the catalogue")
	func everyDomainIsCatalogued() throws {
		let catalogue = try String(
			contentsOf: Self.keysDirectory.appending(path: "PreferenceCatalog.swift"),
			encoding: .utf8
		)
		for domain in try Self.domains() where domain.registration != nil {
			#expect(
				catalogue.contains("\(domain.name).all"),
				"Preferences.\(domain.name) is not in Preferences.allDomains"
			)
		}
	}

	/// Every key the code declares is one the catalogue can answer for, which
	/// is what the two source checks above add up to at runtime.
	@Test("The catalogue answers for every key it lists")
	func catalogueAnswersForEveryKey() {
		for key in Preferences.allKeys {
			#expect(Preferences.key(named: key.name) != nil, "\(key.name) is not reachable by name")
		}
	}
}

private extension String {
	var nilIfEmpty: Self? {
		isEmpty ? nil : self
	}
}

private extension Substring {
	var nilIfEmpty: Self? {
		isEmpty ? nil : self
	}
}
