// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private let repairLogger = Logger(subsystem: LogSubsystem.current, category: "SettingsLaunchRepair")

/// What the launch repair changed, and where the values it replaced were kept.
struct SettingsStoredValueRepair: Equatable {
	/// Keys that kept the elements their declaration still accepts.
	var repaired: Set<String> = []
	/// Keys whose stored value was removed, leaving the registered default.
	var removed: Set<String> = []
	/// The private file holding every replaced value as it was stored.
	var backup: URL?
}

/// The launch step that holds what is already stored to what the declarations
/// now accept. A step, not a store operation: it runs once, before anything reads.
enum SettingsLaunchRepair {
	/** Repairs or removes every persisted value a declaration would refuse.

	 Bounds arrive after values do: a count or port stored before its range was
	 declared, or by a hand edit of the plist, reads back exactly as it was stored.
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
	static func run(stores: SettingsStores, backupDirectory: URL) -> SettingsStoredValueRepair {
		let persisted: [SettingStorage: [String: Any]] = [
			.container: stores.persistentDomain(for: .container),
			.standard: stores.persistentDomain(for: .standard),
		]
		var values: [String: PropertyListValue] = [:]
		var repaired: [String: PropertyListValue] = [:]
		var removed: Set<String> = []
		var originals: [String: Any] = [:]
		for key in SettingsKeys.allKeys {
			guard let object = persisted[key.storage]?[key.name] else { continue }
			let value = PropertyListValue(propertyList: object)
			if let value, let coerced = SettingsKeys.coerce(value, forKey: key.name) {
				values[key.name] = coerced
				continue
			}
			originals[key.name] = object
			if let value, let salvaged = SettingsKeys.salvage(value, forKey: key.name) {
				values[key.name] = salvaged
				repaired[key.name] = salvaged
			} else {
				removed.insert(key.name)
			}
		}
		// A value that is fine on its own can still contradict its partner.
		for key in SettingsKeys.allKeys {
			if let value = values[key.name], !key.isValid(value, in: values) {
				originals[key.name] = persisted[key.storage]?[key.name]
				repaired.removeValue(forKey: key.name)
				removed.insert(key.name)
			}
		}
		guard originals.isEmpty == false else { return SettingsStoredValueRepair() }

		let backup: URL
		do {
			let data = try PropertyListSerialization.data(fromPropertyList: originals, format: .xml, options: 0)
			backup = try SettingsProtectedFolder(url: backupDirectory)
				.write(data, named: "Repaired-Settings-\(UUID().uuidString).plist")
		} catch {
			repairLogger.error("""
			Left \(originals.count, privacy: .public) refused stored settings unchanged: \
			their backup could not be written: \(error.localizedDescription, privacy: .public)
			""")
			return SettingsStoredValueRepair()
		}
		for (name, value) in repaired {
			stores.set(value, for: UntypedSettingsKey(name, storage: SettingsKeys.storage(for: name)))
			repairLogger.notice("Dropped refused entries from \(name, privacy: .public).")
		}
		for name in removed {
			stores.set(nil, for: UntypedSettingsKey(name, storage: SettingsKeys.storage(for: name)))
			repairLogger.notice("Removed the refused stored value of \(name, privacy: .public).")
		}
		repairLogger.notice("Saved the settings as they were stored to \(backup.path, privacy: .private).")
		return SettingsStoredValueRepair(repaired: Set(repaired.keys), removed: removed, backup: backup)
	}
}
