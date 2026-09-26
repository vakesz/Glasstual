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

	/** The stored value, or `nil` when nothing has been written and no default
	 was registered. Reading through this is how a setting whose "unset" state is
	 meaningful keeps it distinguishable from its default. */
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
				/* A value with no stored representation leaves what is already
				 there alone. Writing a placeholder would discard the setting
				 and shadow the declared default with something unreadable. */
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

	/** The stored value of a key whose shape belongs to the subsystem that
	 writes it, narrowed out of the `Any` `UserDefaults` returns. */
	func propertyListValue(for key: some AnySettingsKey) -> PropertyListValue? {
		store(for: key.storage).object(forKey: key.name)
			.flatMap(PropertyListValue.init(propertyList:))
	}

	func setPropertyListValue(_ value: PropertyListValue?, for key: some AnySettingsKey) {
		store(for: key.storage).set(value?.propertyListObject, forKey: key.name)
	}
}

extension SettingsKeys {
	/** The shared store, which the main actor keeps for the lifetime of the
	 process so bindings observe one object and a read costs nothing. */
	@MainActor
	static var defaults: GlasstualUserDefaults {
		GlasstualUserDefaults.container
	}
}

extension SettingsKey {
	/// The effective value in the shared store: what the user chose, or the
	/// declared default.
	@MainActor
	var value: Value {
		get { SettingsKeys.defaults[self] }
		nonmutating set { SettingsKeys.defaults[self] = newValue }
	}

	/// The stored value, or `nil` when nothing has been written and no default
	/// was registered.
	@MainActor
	var storedValue: Value? {
		get { SettingsKeys.defaults[stored: self] }
		nonmutating set { SettingsKeys.defaults[stored: self] = newValue }
	}
}

/** ``SettingsKey/value`` and ``SettingsKey/storedValue`` through a private
 handle on the store, for code that runs outside the main actor.

 Every access builds a handle, and there is no shared one to hand out instead:
 `UserDefaults` is not `Sendable`, so nothing outside an actor may hold one for
 the process. Code that reads in a loop — a sort comparator, a rendered line, a
 member row — takes one `GlasstualUserDefaults.suite()` into a local and
 subscripts that with the keys it needs.

 An extension of its own, marked as a whole, rather than two unmarked members
 beside the main-actor ones above: the key is a value type, and every access
 here goes through `GlasstualUserDefaults`, a handle on a suite Foundation
 synchronizes. `UntypedSettingsKey` carries the same pair below for the same
 reason. */
nonisolated extension SettingsKey {
	var detachedValue: Value {
		get { GlasstualUserDefaults.suite()[self] }
		nonmutating set { GlasstualUserDefaults.suite()[self] = newValue }
	}

	/// ``detachedValue``, but `nil` where nothing has been written.
	var detachedStoredValue: Value? {
		get { GlasstualUserDefaults.suite()[stored: self] }
		nonmutating set { GlasstualUserDefaults.suite()[stored: self] = newValue }
	}
}

extension AnySettingsKey {
	/// The stored value, for the handful of keys whose value shape belongs to
	/// the subsystem that writes it.
	@MainActor
	var propertyListValue: PropertyListValue? {
		get { SettingsKeys.defaults.propertyListValue(for: self) }
		nonmutating set { SettingsKeys.defaults.setPropertyListValue(newValue, for: self) }
	}

	@MainActor
	func reset() {
		SettingsKeys.defaults.removeValue(for: self)
	}
}

/** ``AnySettingsKey/propertyListValue`` through the private handle on the
 store, for code that runs outside the main actor.

 It lives on the untyped key rather than on the `AnySettingsKey` extension
 above, whose members are main-actor: a lone `nonisolated` member there would be
 an isolation claim about a protocol requirement, where `UntypedSettingsKey` is
 a value type whose extension is nonisolated as a whole — as the typed key's
 detached pair is. Every access goes through `GlasstualUserDefaults`, a handle on
 a suite Foundation synchronizes. */
nonisolated extension UntypedSettingsKey {
	var detachedPropertyListValue: PropertyListValue? {
		get { GlasstualUserDefaults.suite().propertyListValue(for: self) }
		nonmutating set { GlasstualUserDefaults.suite().setPropertyListValue(newValue, for: self) }
	}
}
