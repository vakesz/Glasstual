// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** Every declaration in one place, with the registration domain and catalogue
 used by import, export, storage routing, and defaults registration derived
 directly from those declarations. */
nonisolated extension SettingsKeys {
	/// The one list a new setting domain joins.
	private static let allDomains: [[any AnySettingsKey]] = [
		Identity.all, Connection.all, Sessions.all, Commands.all, Messages.all, Logging.all,
		Appearance.all, Theme.all, Badges.all, MainWindow.all, Notifications.all,
		Input.all, Highlights.all, Reactions.all, FileTransfers.all, Rules.all,
		Internals.all, LinkSchemes.all,
	]

	static let allKeys: [any AnySettingsKey] = allDomains.reduce(into: []) { keys, domain in
		keys.append(contentsOf: domain)
	}

	static let allFamilies: [SettingsKeyFamily] = Families.all

	private static let keysByName: [String: any AnySettingsKey] = {
		var result: [String: any AnySettingsKey] = [:]

		for key in allKeys {
			result[key.name] = key
		}

		return result
	}()

	/// The declaration for a stored name, if the name is one the code knows.
	static func key(named name: String) -> (any AnySettingsKey)? {
		keysByName[name]
	}

	/** Validates and coerces an imported value for a stored name, or returns
	 `nil` to reject it.

	 A name the code declares one by one answers for itself. A name made at
	 runtime has no declaration, so its family decides the shape it may hold —
	 without that, a catalogued family name was the one import path that
	 accepted an arbitrary property list. A name the catalogue does not cover
	 at all belongs to something else and travels unchanged. */
	static func coerce(_ value: PropertyListValue, forKey name: String) -> PropertyListValue? {
		if let key = keysByName[name] {
			return key.coerce(value)
		}

		guard let family = allFamilies.first(where: { $0.matches(name) }) else {
			return value
		}

		return family.coerce(name, value)
	}

	/** What of a stored value the declaration still accepts, or `nil` when
	 nothing of it survives.

	 A collection loses only the elements the declaration refuses — one bad
	 highlight word, one malformed colour override — rather than every entry it
	 holds. A payload with independent fields is repaired field by field first,
	 so a rule loses one field instead of the whole rule. */
	static func salvage(_ value: PropertyListValue, forKey name: String) -> PropertyListValue? {
		let repaired = SettingsValueRepair.repairs[name]?(value) ?? value
		let kept: PropertyListValue = switch repaired {
		case let .array(elements):
			.array(elements.filter { coerce(.array([$0]), forKey: name) != nil })
		case let .dictionary(entries):
			.dictionary(entries.filter { coerce(.dictionary([$0.key: $0.value]), forKey: name) != nil })
		default:
			repaired
		}

		return coerce(kept, forKey: name)
	}

	/// The registration domain for one defaults database, built from the
	/// declarations rather than read from a plist.
	static func registrationDomain(for storage: SettingStorage) -> [String: PropertyListValue] {
		var domain: [String: PropertyListValue] = [:]

		for key in allKeys where key.storage == storage {
			guard let value = key.registeredDefault else {
				continue
			}

			domain[key.name] = value
		}

		return domain
	}

	/// Whether a stored name is one this application owns. Names made at
	/// runtime are matched by their family's pattern.
	static func isCatalogued(_ name: String) -> Bool {
		if let key = keysByName[name], key.isCatalogued {
			return true
		}

		// A key declared `.uncatalogued` is still catalogued when a family
		// covers it: the per-event notification settings are declared one by one
		// so they carry defaults, but the catalogue lists them by prefix.
		return allFamilies.contains { $0.isCatalogued && $0.matches(name) }
	}

	/// Whether a stored name is kept out of an exported configuration.
	static func isExcludedFromExport(_ name: String) -> Bool {
		if let key = keysByName[name], key.traits.contains(.excludedFromExport) {
			return true
		}

		if allFamilies.contains(where: { $0.traits.contains(.excludedFromExport) && $0.matches(name) }) {
			return true
		}

		// A name the catalogue does not cover is not ours to export.
		return isCatalogued(name) == false
	}

	/// Which defaults database a stored name belongs in. An unknown name goes to
	/// the container, which is where everything the application owns lives.
	static func storage(for name: String) -> SettingStorage {
		if let key = keysByName[name] {
			return key.storage
		}

		if let family = allFamilies.first(where: { $0.matches(name) }) {
			return family.storage
		}

		return .container
	}
}
