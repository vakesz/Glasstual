// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The two defaults databases a settings operation reads and writes: the
 application-group container and the application's own domain.

 The standard store is an explicit dependency, including in tests. No suite
 override changes process-global `UserDefaults.standard` or the user's
 registration domain. */
struct SettingsStores {
	let container: UserDefaults
	let containerDomain: String
	let standard: UserDefaults
	let standardDomain: String

	static var live: Self {
		Self(container: GlasstualUserDefaults.container, containerDomain: GlasstualUserDefaults.container.suiteName,
		     standard: .standard,
		     standardDomain: Bundle.main.bundleIdentifier ?? ApplicationInfo.applicationBundleIdentifier())
	}

	func store(for key: some AnySettingsKey) -> UserDefaults {
		key.storage == .standard ? standard : container
	}

	/// What a store actually holds, without the registration domain that
	/// `object(forKey:)` falls back to. `nil` means nothing is persisted, which
	/// is a different answer from "the registered default".
	func persistedValue(for key: some AnySettingsKey) -> PropertyListValue? {
		persistentDomain(for: key.storage)[key.name].flatMap(PropertyListValue.init(propertyList:))
	}

	/** Everything a domain has persisted, read from the current-user, any-host
	 source a suite writes to.

	 `persistentDomain(forName:)` answers the same question, but it also opens
	 the any-user, by-host source, which cfprefsd refuses for an application
	 group container: it detaches from the domain and logs "Using
	 kCFPreferencesAnyUser with a container is only allowed for System
	 Containers" every time it is asked. */
	func persistentDomain(for storage: SettingStorage) -> [String: Any] {
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

	subscript<Value>(key: SettingsKey<Value>) -> Value {
		self[stored: key] ?? key.defaultValue
	}

	subscript<Value>(stored key: SettingsKey<Value>) -> Value? {
		store(for: key).object(forKey: key.name).flatMap(Value.settingValue(from:))
	}

	func set(_ value: PropertyListValue?, for key: some AnySettingsKey) {
		let store = store(for: key)
		if let value {
			store.set(value.propertyListObject, forKey: key.name)
		} else {
			store.removeObject(forKey: key.name)
		}
	}
}
