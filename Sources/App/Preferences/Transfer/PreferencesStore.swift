// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private let repairLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Glasstual", category: "Preferences")

/// What the launch repair changed, and where the values it replaced were kept.
struct PreferencesStoredValueRepair: Equatable {
	/// Keys that kept the elements their declaration still accepts.
	var repaired: Set<String> = []
	/// Keys whose stored value was removed, leaving the registered default.
	var removed: Set<String> = []
	/// The private file holding every replaced value as it was stored.
	var backup: URL?
}

/// The standard store is an explicit dependency, including in tests. No suite override
/// changes process-global UserDefaults.standard or the user's registration domain.
struct PreferencesTransferStores {
	let container: UserDefaults
	let containerDomain: String
	let standard: UserDefaults
	let standardDomain: String

	static var live: Self {
		Self(container: GlasstualUserDefaults.container, containerDomain: GlasstualUserDefaults.container.suiteName,
		     standard: .standard,
		     standardDomain: Bundle.main.bundleIdentifier ?? ApplicationInfo.applicationBundleIdentifier())
	}

	func store(for key: some AnyPreferenceKey) -> UserDefaults {
		key.storage == .standard ? standard : container
	}

	/// What a store actually holds, without the registration domain that
	/// `object(forKey:)` falls back to. `nil` means nothing is persisted, which
	/// is a different answer from "the registered default".
	func persistedValue(for key: some AnyPreferenceKey) -> PropertyListValue? {
		persistentDomain(for: key.storage)[key.name].flatMap(PropertyListValue.init(propertyList:))
	}

	/** Everything a domain has persisted, read from the current-user, any-host
	 source a suite writes to.

	 `persistentDomain(forName:)` answers the same question, but it also opens
	 the any-user, by-host source, which cfprefsd refuses for an application
	 group container: it detaches from the domain and logs "Using
	 kCFPreferencesAnyUser with a container is only allowed for System
	 Containers" every time it is asked. */
	func persistentDomain(for storage: PreferenceStorage) -> [String: Any] {
		let domain = (storage == .standard ? standardDomain : containerDomain) as CFString
		guard let names = CFPreferencesCopyKeyList(
			domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
		) as? [String] else { return [:] }
		var values: [String: Any] = [:]
		values.reserveCapacity(names.count)
		for name in names {
			if let value = CFPreferencesCopyValue(
				name as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
			) {
				values[name] = value
			}
		}
		return values
	}

	subscript<Value>(key: PreferenceKey<Value>) -> Value {
		self[stored: key] ?? key.defaultValue
	}

	subscript<Value>(stored key: PreferenceKey<Value>) -> Value? {
		store(for: key).object(forKey: key.name).flatMap(Value.preferenceValue(from:))
	}

	func set(_ value: PropertyListValue?, for key: some AnyPreferenceKey) {
		let store = store(for: key)
		if let value {
			store.set(value.propertyListObject, forKey: key.name)
		} else {
			store.removeObject(forKey: key.name)
		}
	}

	/** Repairs or removes every persisted value a declaration would refuse.

	 Bounds arrive after values do: a count or port stored before its range was
	 declared, or by an older build, reads back exactly as it was stored.
	 Everything downstream holds values to the declarations — the Settings
	 fields, an export, the recovery backup taken before an import, the import
	 plan itself — so one stale value would make all of them fail on this
	 Mac's own state.

	 A collection keeps every element the declaration still accepts; only a
	 value with nothing left to keep is removed, which leaves the registered
	 default in its place. Before anything is written, the values as they were
	 stored are saved to a private file in `backupDirectory`, and if that save
	 fails nothing is changed. Runs once at launch, before anything reads. */
	@discardableResult
	func repairValuesDeclarationsRefuse(backupDirectory: URL) -> PreferencesStoredValueRepair {
		let persisted: [PreferenceStorage: [String: Any]] = [
			.container: persistentDomain(for: .container),
			.standard: persistentDomain(for: .standard),
		]
		var values: [String: PropertyListValue] = [:]
		var repaired: [String: PropertyListValue] = [:]
		var removed: Set<String> = []
		var originals: [String: Any] = [:]
		for key in Preferences.allKeys {
			guard let object = persisted[key.storage]?[key.name] else { continue }
			let value = PropertyListValue(propertyList: object)
			if let value, let coerced = Preferences.coerce(value, forKey: key.name) {
				values[key.name] = coerced
				continue
			}
			originals[key.name] = object
			if let value, let salvaged = Preferences.salvage(value, forKey: key.name) {
				values[key.name] = salvaged
				repaired[key.name] = salvaged
			} else {
				removed.insert(key.name)
			}
		}
		// A value that is fine on its own can still contradict its partner.
		for key in Preferences.allKeys {
			if let value = values[key.name], !key.isValid(value, in: values) {
				originals[key.name] = persisted[key.storage]?[key.name]
				repaired.removeValue(forKey: key.name)
				removed.insert(key.name)
			}
		}
		guard originals.isEmpty == false else { return PreferencesStoredValueRepair() }

		let backup: URL
		do {
			let data = try PropertyListSerialization.data(fromPropertyList: originals, format: .xml, options: 0)
			backup = try PreferencesProtectedFolder(url: backupDirectory)
				.write(data, named: "Repaired-Settings-\(UUID().uuidString).plist")
		} catch {
			repairLogger.error("""
			Left \(originals.count, privacy: .public) refused stored settings unchanged: \
			their backup could not be written: \(error.localizedDescription, privacy: .public)
			""")
			return PreferencesStoredValueRepair()
		}
		for (name, value) in repaired {
			set(value, for: UntypedPreferenceKey(name, storage: Preferences.storage(for: name)))
			repairLogger.notice("Dropped refused entries from \(name, privacy: .public).")
		}
		for name in removed {
			set(nil, for: UntypedPreferenceKey(name, storage: Preferences.storage(for: name)))
			repairLogger.notice("Removed the refused stored value of \(name, privacy: .public).")
		}
		repairLogger.notice("Saved the settings as they were stored to \(backup.path, privacy: .private).")
		return PreferencesStoredValueRepair(repaired: Set(repaired.keys), removed: removed, backup: backup)
	}

	func snapshot(clients: [ClientConfig]) -> PreferencesArchive {
		var values: [String: PropertyListValue] = [:]
		var unset: Set<String> = []
		for key in Preferences.allKeys where !Preferences.isExcludedFromExport(key.name)
			&& key.name != Preferences.Connection.clientList.name
		{
			if let value = store(for: key).object(forKey: key.name).flatMap(PropertyListValue.init(propertyList:))
				?? key.registeredDefault
			{
				values[key.name] = value
			} else {
				unset.insert(key.name)
			}
		}
		for storage in PreferenceStorage.allCases {
			for (name, object) in persistentDomain(for: storage)
				where Preferences.key(named: name) == nil && !Preferences.isExcludedFromExport(name)
			{
				guard Preferences.storage(for: name) == storage else { continue }
				values[name] = PropertyListValue(propertyList: object)
			}
		}
		return PreferencesArchive(values: values, unset: unset,
		                          clients: clients.map(PreferencesClientArchive.withoutPendingSecrets),
		                          source: .localRecovery)
	}

	func apply(_ plan: PreferencesTransferPlan, persistClients: Bool = true) {
		for name in plan.changedKeys {
			let key = UntypedPreferenceKey(name, storage: Preferences.storage(for: name))
			set(plan.result.values[name], for: key)
		}
		if persistClients {
			set(
				.array((plan.result.clients ?? []).map { .dictionary($0.dictionaryValue) }),
				for: Preferences.Connection.clientList
			)
		}
	}
}
