// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

nonisolated extension UserDefaults { // nonisolated: guarded
	/// The defaults database a declaration is stored in.
	func store(for storage: SettingStorage) -> UserDefaults {
		switch storage {
		case .container: self
		case .standard: .standard
		}
	}

	/// The effective value: what the user chose, or the declared default.
	subscript<Value>(key: SettingsKey<Value>) -> Value {
		get { self[stored: key] ?? key.defaultValue }
		set { self[stored: key] = newValue }
	}

	/// Reads persisted or registered values without substituting the declaration's default.
	subscript<Value>(stored key: SettingsKey<Value>) -> Value? {
		get {
			guard let object = store(for: key.storage).object(forKey: key.name) else {
				return nil
			}

			return Value.settingValue(from: object)
		}
		set {
			let store = store(for: key.storage)

			guard let newValue else {
				store.removeObject(forKey: key.name)
				return
			}

			guard let object = newValue.settingObject else {
				// Keep the existing value when conversion cannot produce a storable value.
				return
			}

			store.set(object, forKey: key.name)
		}
	}

	/// Writes the default into the registration domain rather than the
	/// persistent one, for settings a theme recomputes at every launch.
	func registerDefault<Value>(_ value: Value, for key: SettingsKey<Value>) {
		guard let object = value.settingObject else {
			return
		}

		store(for: key.storage).register(defaults: [key.name: object])
	}

	func removeValue(for key: some AnySettingsKey) {
		store(for: key.storage).removeObject(forKey: key.name)
	}

	/// Reads a property-list value whose structure is defined by its owning subsystem.
	func propertyListValue(for key: some AnySettingsKey) -> PropertyListValue? {
		store(for: key.storage).object(forKey: key.name)
			.flatMap(PropertyListValue.init(propertyList:))
	}

	func setPropertyListValue(_ value: PropertyListValue?, for key: some AnySettingsKey) {
		store(for: key.storage).set(value?.propertyListObject, forKey: key.name)
	}
}

extension SettingsKey {
	/// The effective value in the shared store: what the user chose, or the
	/// declared default.
	@MainActor
	var value: Value {
		get { GlasstualUserDefaults.container[self] }
		nonmutating set { GlasstualUserDefaults.container[self] = newValue }
	}

	/// The stored value, or `nil` when nothing has been written and no default
	/// was registered.
	@MainActor
	var storedValue: Value? {
		get { GlasstualUserDefaults.container[stored: self] }
		nonmutating set { GlasstualUserDefaults.container[stored: self] = newValue }
	}
}

/// Accesses the Foundation-synchronized suite through a new handle per call.
/// For repeated reads, keep one local `GlasstualUserDefaults.suite()` handle.
nonisolated extension SettingsKey {
	var detachedValue: Value {
		get { GlasstualUserDefaults.suite()[self] }
		nonmutating set { GlasstualUserDefaults.suite()[self] = newValue }
	}

	/// Reads persisted or registered values without substituting the declaration's default.
	var detachedStoredValue: Value? {
		get { GlasstualUserDefaults.suite()[stored: self] }
		nonmutating set { GlasstualUserDefaults.suite()[stored: self] = newValue }
	}
}

extension AnySettingsKey {
	/// The property-list value defined by the key's owning subsystem.
	@MainActor
	var propertyListValue: PropertyListValue? {
		get { GlasstualUserDefaults.container.propertyListValue(for: self) }
		nonmutating set { GlasstualUserDefaults.container.setPropertyListValue(newValue, for: self) }
	}

	@MainActor
	func reset() {
		GlasstualUserDefaults.container.removeValue(for: self)
	}
}

/// Reads subsystem-defined property-list values through a new local suite handle.
nonisolated extension UntypedSettingsKey {
	var detachedPropertyListValue: PropertyListValue? {
		get { GlasstualUserDefaults.suite().propertyListValue(for: self) }
		nonmutating set { GlasstualUserDefaults.suite().setPropertyListValue(newValue, for: self) }
	}
}
