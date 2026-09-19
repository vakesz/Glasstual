// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// Registration, import/export filtering, and storage routing are derived
/// directly from typed key declarations. No bundled catalogue mirrors them.
@Suite("Settings catalogue")
struct SettingsCatalogTests {
	// MARK: - Declarations

	@Test("No preference name is declared twice")
	func namesAreUnique() {
		var seen: Set<String> = []

		for key in SettingsKeys.allKeys {
			#expect(seen.insert(key.name).inserted, "\(key.name) is declared more than once")
		}
	}

	@Test("Every registered declaration reaches the registration domain with its default")
	func registeredDefaultsAreRegistered() {
		SettingsRegistration.registerDefaults()

		let container = GlasstualUserDefaults.container
			.volatileDomain(forName: UserDefaults.registrationDomain)
		let standard = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)

		for key in SettingsKeys.allKeys {
			// The default nickname is re-registered at launch with a random
			// suffix, so the domain deliberately does not hold the declaration.
			guard key.name != SettingsKeys.Identity.nickname.name else {
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
		// "Notifications -> Sound Is Muted" ships no registration-domain entry,
		// so the declared default is the only thing standing between a read and
		// a zero value.
		let key = SettingsKeys.Notifications.soundIsMuted
		let original = key.storedValue
		defer { key.storedValue = original }

		key.reset()
		#expect(key.value == key.defaultValue)
	}

	// MARK: - Catalogue membership

	@Test("A name made at runtime is matched by its family")
	func familiesCoverRuntimeNames() {
		#expect(SettingsKeys.isCatalogued(SettingsKeys.Notifications.notifyAboutMentions.name))
		#expect(SettingsKeys.isCatalogued(SettingsKeys.Families.alertSuppression.pattern + "Some Prompt"))
		#expect(SettingsKeys.isCatalogued("Something Glasstual Never Wrote") == false)
	}

	/** The window-frame family is the one AppKit writes itself, so the spelling
	 asserted here is the live one: `saveFrame(usingName:)` writes
	 `NSWindow Frame ` followed by the autosave name. A family that matched a
	 spelling nothing writes excluded nothing. */
	@Test("Internal state stays out of exports while the portable transcript theme stays in")
	func excludedFamiliesAreExcluded() {
		#expect(SettingsKeys.isExcludedFromExport("NSWindow Frame Main Window"))
		#expect(SettingsKeys.isExcludedFromExport(SettingsKeys.Families.alertSuppression.pattern + "Some Prompt"))
		#expect(SettingsKeys.isExcludedFromExport(SettingsKeys.Theme.transcriptTheme.name) == false)
	}

	/// A `TextField` family used to exclude all nine text-system settings from
	/// export, and `isExcludedFromExport` gates import too, so three checkboxes
	/// in Settings -> Controls neither left nor entered a configuration file.
	@Test("The input text-system settings are portable")
	func textSystemSettingsAreExported() {
		for key in [
			SettingsKeys.Input.automaticSpellCheck,
			SettingsKeys.Input.automaticGrammarCheck,
			SettingsKeys.Input.automaticSpellCorrection,
			SettingsKeys.Input.smartCopyPaste,
			SettingsKeys.Input.smartQuotes,
			SettingsKeys.Input.smartDashes,
			SettingsKeys.Input.smartLinks,
			SettingsKeys.Input.dataDetectors,
			SettingsKeys.Input.textReplacement,
		] {
			#expect(SettingsKeys.isExcludedFromExport(key.name) == false)
		}
	}

	/// The IRCv3 pane writes this one, so a user who switched a capability off
	/// expects it switched off on the machine they import the file into.
	@Test("The list of switched-off IRCv3 capabilities is catalogued and portable")
	func disabledCapabilitiesAreCataloguedAndExported() {
		let key = SettingsKeys.Connection.disabledCapabilities

		#expect(SettingsKeys.key(named: key.name) != nil)
		#expect(SettingsKeys.isCatalogued(key.name))
		#expect(SettingsKeys.isExcludedFromExport(key.name) == false)
		#expect(key.defaultValue.isEmpty)
	}

	@Test("Storage follows the declaration, not the call site")
	func storageFollowsDeclarations() {
		#expect(SettingsKeys.storage(for: SettingsKeys.LinkSchemes.permitted.name) == .standard)
		#expect(SettingsKeys.storage(for: "NSWindow Frame Main Window") == .standard)
		// This one used to read and write UserDefaults.standard while the
		// catalogue said it belonged in the container, so an imported value
		// never took effect.
		#expect(SettingsKeys.storage(for: SettingsKeys.Logging.loadHistoryLazily.name) == .container)
	}

	// MARK: - Helpers

	/// A colour is stored as its own versioned document, not as an `NSColor`
	/// keyed archive: the components come back comparable, and nothing has to
	/// unarchive a class out of the defaults store to read a setting.
	@Test("A colour round-trips as a versioned property list, not a keyed archive")
	func colorsAreStoredAsVersionedDocuments() throws {
		let color = try #require(SettingsColor(NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)))
		let stored = try #require(color.settingObject as? Data)
		let propertyList = try #require(PropertyListSerialization.propertyList(from: stored, format: nil) as? [String: Any])
		#expect(propertyList["version"] as? Int == 1)
		#expect(propertyList["$archiver"] == nil)
		#expect(SettingsColor.settingValue(from: stored) == color)
		#expect(abs(color.red - 0.2) < 0.001)
		#expect(abs(color.green - 0.4) < 0.001)
		#expect(abs(color.blue - 0.6) < 0.001)
		#expect(abs(color.alpha - 0.8) < 0.001)

		// An NSColor keyed archive is no longer a colour setting.
		let archive = try NSKeyedArchiver.archivedData(withRootObject: color.color, requiringSecureCoding: true)
		#expect(SettingsColor.settingValue(from: archive) == nil)
	}

	@Test("Colors reject unsupported payload versions and nonfinite components")
	func invalidStoredColorsAreRejected() throws {
		let color = SettingsColor(red: 0.2, green: 0.4, blue: 0.6)
		let data = try #require(color.settingObject as? Data)
		var propertyList = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
		propertyList["version"] = 2
		let unsupported = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .binary, options: 0)
		#expect(SettingsColor.settingValue(from: unsupported) == nil)
		#expect(SettingsColor(red: .nan, green: 0, blue: 0).settingObject == nil)
		propertyList["version"] = 1
		propertyList["color"] = ["red": Double.infinity, "green": 0, "blue": 0, "alpha": 1]
		let nonfinite = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .binary, options: 0)
		#expect(SettingsColor.settingValue(from: nonfinite) == nil)
	}

	/** Archived colours are not byte-identical between two archives of the same
	 colour, and a number that was written as a real compares equal to the same
	 number written as an integer, so equality here is by value rather than by
	 representation. */
	private static func valuesMatch(_ lhs: PropertyListValue, _ rhs: PropertyListValue) -> Bool {
		if let lhs = SettingsColor.settingValue(from: lhs.propertyListObject),
		   let rhs = SettingsColor.settingValue(from: rhs.propertyListObject)
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

/** Each domain lists the keys it declares, and `SettingsKeys.allDomains` lists
 the domains. Swift cannot enumerate static members, so what would otherwise be
 an unchecked hand-kept list is checked here against the declarations
 themselves: the source of the `Keys` directory is read back and every declared
 key has to reach its domain's list, and every domain has to reach the
 catalogue. */
@Suite("Settings declaration lists")
struct SettingsDeclarationListTests {
	/// One domain as its source file declares it.
	private struct Domain {
		let name: String
		/// The properties declared as keys, in declaration order.
		let declared: [String]
		/// The text of the `all` list, or `nil` for a domain that has none.
		let registration: String?
	}

	private static let keysDirectory = RepositoryPaths.appSources.appending(path: "SettingsKeys")

	private static func domains() throws -> [Domain] {
		let names = try FileManager.default.contentsOfDirectory(atPath: keysDirectory.path())
			.filter { $0.hasPrefix("SettingsKeys+") && $0.hasSuffix(".swift") }
			.sorted()
		try #require(names.isEmpty == false, "no settings declarations at \(keysDirectory.path())")

		return try names.flatMap { name -> [Domain] in
			let source = try String(contentsOf: keysDirectory.appending(path: name), encoding: .utf8)
			return source.components(separatedBy: "\n\tenum ").dropFirst().compactMap { block in
				guard let name = block.prefix(while: { $0 != " " }).nilIfEmpty else { return nil }
				let halves = block.components(separatedBy: "\n\t\tstatic let all: [any AnySettingsKey]")
				return Domain(
					name: String(name),
					declared: declaredKeys(in: halves[0]),
					registration: halves.count > 1 ? halves[1] : nil
				)
			}
		}
	}

	/// The properties a block declares as settings keys, by the shape of the
	/// declaration rather than by its type, which the source does not spell.
	private static func declaredKeys(in block: String) -> [String] {
		block.components(separatedBy: "\n\t\tstatic let ").dropFirst().compactMap { declaration in
			let parts = declaration.components(separatedBy: " = ")
			guard parts.count > 1,
			      parts[1].hasPrefix("SettingsKey(") || parts[1].hasPrefix("UntypedSettingsKey(")
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
					"SettingsKeys.\(domain.name).\(key) is declared but is in no list"
				)
			}
		}
	}

	@Test("Every domain that declares keys reaches the catalogue")
	func everyDomainIsCatalogued() throws {
		let catalogue = try String(
			contentsOf: Self.keysDirectory.appending(path: "SettingsCatalog.swift"),
			encoding: .utf8
		)
		for domain in try Self.domains() where domain.registration != nil {
			#expect(
				catalogue.contains("\(domain.name).all"),
				"SettingsKeys.\(domain.name) is not in SettingsKeys.allDomains"
			)
		}
	}

	/// Every key the code declares is one the catalogue can answer for, which
	/// is what the two source checks above add up to at runtime.
	@Test("The catalogue answers for every key it lists")
	func catalogueAnswersForEveryKey() {
		for key in SettingsKeys.allKeys {
			#expect(SettingsKeys.key(named: key.name) != nil, "\(key.name) is not reachable by name")
		}
	}
}

/** One shape for every name this application stores a setting under:
 `Group -> Name`, in Title Case words, with the group naming the domain the key
 is declared in. Two of the declarations carry a name that belongs to the
 framework that reads it rather than to us, and AppKit writes the window frames
 itself, so those three are spelled the way those frameworks spell them. */
@Suite("Settings key naming")
struct SettingsKeyNamingTests {
	/// The group of every `SettingsKeys` domain, plus the one key family whose
	/// names are made at runtime rather than declared in a domain.
	private static let groups: Set<String> = [
		"Identity", "Connection", "Sessions", "Commands", "Messages", "Logging",
		"Appearance", "Theme", "Badges", "Main Window", "Notifications", "Input",
		"Highlights", "Reactions", "File Transfers", "Rules", "Internals",
		"Link Schemes", "Alerts",
	]

	/// Names Foundation and AppKit read out of the application's own domain
	/// under their own spelling.
	private static let systemOwned: Set<String> = ["AppleLanguages", "NSAppSleepDisabled"]

	@Test("Every declared key is named Group -> Name")
	func declaredNamesAreGrouped() {
		for key in SettingsKeys.allKeys where Self.systemOwned.contains(key.name) == false {
			let parts = key.name.components(separatedBy: " -> ")
			guard parts.count >= 2, parts.allSatisfy({ $0.isEmpty == false }) else {
				Issue.record("\(key.name) is not named \"Group -> Name\"")
				continue
			}

			#expect(Self.groups.contains(parts[0]), "\(key.name) is under no declared group")
			#expect(Self.isTitleCase(key.name), "\(key.name) is not in Title Case words")
		}
	}

	@Test("Every key family is named the same way")
	func familyPatternsAreGrouped() {
		for family in SettingsKeys.allFamilies {
			// AppKit writes a saved frame itself, under its own prefix plus the
			// window's autosave name.
			guard family.pattern != "NSWindow Frame " else { continue }

			let group = family.pattern.components(separatedBy: " -> ")[0]
			#expect(Self.groups.contains(group), "\(family.pattern) is under no declared group")
			#expect(Self.isTitleCase(family.pattern), "\(family.pattern) is not in Title Case words")
		}
	}

	/// Two names spelled out, so the scheme is legible here and a shell script
	/// or a plist fixture that has to hold a literal has something to check
	/// itself against.
	@Test("The scheme reads the way the shipped names do")
	func namesReadAsGroupThenName() {
		#expect(SettingsKeys.Connection.confirmQuit.name == "Connection -> Confirm Quit")
		#expect(SettingsKeys.Sessions.serverSessions.name == "Sessions -> Server Sessions")
	}

	// MARK: - The plist fixture that holds literals

	/// Read from the source tree rather than bundled, so the file a reviewer
	/// edits is the file the test reads.
	private static var startupFixture: URL {
		RepositoryPaths.corpora.appending(path: "E2E/Startup.plist")
	}

	/** The E2E startup fixture spells its keys and its enumerated values out as
	 literals, so nothing in it is compiler-checked.

	 A key the declarations no longer name would be ignored at launch, and an
	 integer whose case was renumbered would quietly mean a different setting --
	 the fixture's address source is what stops a DCC scenario from asking a
	 router for an address. Both are checked here rather than in the real-app
	 gate, which needs a signed app and Accessibility. */
	@Test("Every key and enumerated value the startup fixture names is declared")
	func startupFixtureNamesDeclaredKeysAndCases() throws {
		let object = try PropertyListSerialization.propertyList(
			from: Data(contentsOf: Self.startupFixture), options: [], format: nil
		)
		let fixture = try #require(object as? [String: Any])

		for (name, value) in fixture {
			#expect(SettingsKeys.isCatalogued(name), "\(name) is not declared")

			let stored = try #require(PropertyListValue(propertyList: value), "\(name) is not a property list")
			#expect(
				SettingsKeys.coerce(stored, forKey: name) != nil,
				"\(name) holds a value its declaration refuses"
			)
		}

		#expect(
			fixture[SettingsKeys.FileTransfers.ipAddressDetectionMethod.name] as? UInt
				== FileTransferIPAddressSource.manual.rawValue
		)
		#expect(
			fixture[SettingsKeys.FileTransfers.requestReplyAction.name] as? UInt
				== FileTransferRequestBehavior.openDialog.rawValue
		)
	}

	/// A word may start with a digit or a symbol -- a mode badge is `+y`, a
	/// shortcut is `Command+W` -- but never with a lower-case letter.
	private static func isTitleCase(_ name: String) -> Bool {
		name.split(separator: " ").allSatisfy { word in
			word == "->" || word.first?.isLowercase == false
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
