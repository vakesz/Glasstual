// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// Which defaults database a setting lives in.
nonisolated enum SettingStorage: CaseIterable, Sendable {
	/// The application-group defaults container.
	case container
	/// `UserDefaults.standard`, for keys AppKit or a vendored library reads out
	/// of the application's own domain.
	case standard
}

nonisolated struct SettingTraits: OptionSet, Sendable {
	let rawValue: UInt

	/// Never written to an exported settings file, and ignored on import.
	static let excludedFromExport = Self(rawValue: 1 << 0)
	/// Absent from the settings catalogue, which also excludes it from export.
	static let uncatalogued = Self(rawValue: 1 << 1)
	/// Read with a default that is never contributed to the registration domain.
	static let unregistered = Self(rawValue: 1 << 2)
}

/// The type-erased face of a declaration, for registration and cataloguing.
protocol AnySettingsKey: Sendable {
	nonisolated var name: String { get } // nonisolated: pure
	nonisolated var storage: SettingStorage { get } // nonisolated: pure
	nonisolated var traits: SettingTraits { get } // nonisolated: pure

	/// The registration-domain entry, or `nil` for an unregistered key.
	nonisolated var registeredDefault: PropertyListValue? { get } // nonisolated: pure

	/// Validates and coerces an imported value, or returns `nil` to reject it.
	nonisolated func coerce(_ value: PropertyListValue) -> PropertyListValue? // nonisolated: pure
	nonisolated func isValid( // nonisolated: pure
		_ value: PropertyListValue, in values: [String: PropertyListValue]
	) -> Bool
}

extension AnySettingsKey {
	nonisolated func isValid( // nonisolated: pure
		_ value: PropertyListValue, in _: [String: PropertyListValue]
	) -> Bool {
		coerce(value) != nil
	}

	nonisolated var isCatalogued: Bool { // nonisolated: pure
		traits.contains(.uncatalogued) == false
	}
}

/** One setting, declared once: its name, its type, its default, where it is
 stored, and how export and the catalogue treat it.

 Registration, storage routing and import/export filtering derive from these
 declarations. No separate property-list catalogue needs to stay in sync. */
nonisolated struct SettingsKey<Value: SettingValue>: AnySettingsKey {
	let name: String
	let defaultValue: Value
	let storage: SettingStorage
	let traits: SettingTraits
	private let validation: @Sendable (Value) -> Bool
	private let relatedValidation: @Sendable (Value, [String: PropertyListValue]) -> Bool

	init(
		_ name: String,
		default defaultValue: Value,
		storage: SettingStorage = .container,
		traits: SettingTraits = [],
		validation: @escaping @Sendable (Value) -> Bool = { _ in true },
		relatedValidation: @escaping @Sendable (Value, [String: PropertyListValue]) -> Bool = { _, _ in true }
	) {
		self.name = name
		self.defaultValue = defaultValue
		self.storage = storage
		self.traits = traits
		self.validation = validation
		self.relatedValidation = relatedValidation
	}

	var registeredDefault: PropertyListValue? {
		guard traits.contains(.unregistered) == false, let object = defaultValue.settingObject else {
			return nil
		}

		return PropertyListValue(propertyList: object)
	}

	func coerce(_ value: PropertyListValue) -> PropertyListValue? {
		guard let coerced = Value.settingValue(from: value.propertyListObject),
		      validation(coerced),
		      let object = coerced.settingObject
		else {
			return nil
		}

		return PropertyListValue(propertyList: object)
	}

	func isValid(_ value: PropertyListValue, in values: [String: PropertyListValue]) -> Bool {
		guard let coerced = Value.settingValue(from: value.propertyListObject) else { return false }
		return validation(coerced) && relatedValidation(coerced, values)
	}

	/** Whether the declaration accepts this typed value, including the rules it
	 shares with other keys.

	 A field checks what an imported file is checked against, so a count the
	 importer would refuse is a count the field refuses too. */
	func accepts(_ value: Value, alongside others: [String: PropertyListValue] = [:]) -> Bool {
		guard let object = value.settingObject,
		      let candidate = PropertyListValue(propertyList: object)
		else {
			return false
		}

		return isValid(candidate, in: others)
	}
}

/** A key whose value is a property-list container owned by the subsystem that
 writes it — a session list, a policy dictionary. It is declared here so the key
 is catalogued and registered like any other; decoding stays with that
 subsystem. */
nonisolated struct UntypedSettingsKey: AnySettingsKey {
	enum RegisteredDefault: Sendable {
		case none
		case emptyDictionary
		case emptyArray
	}

	let name: String
	let storage: SettingStorage
	let traits: SettingTraits
	private let registration: RegisteredDefault
	private let validation: @Sendable (PropertyListValue) -> Bool

	init(
		_ name: String,
		default registration: RegisteredDefault = .none,
		storage: SettingStorage = .container,
		traits: SettingTraits = [],
		validation: @escaping @Sendable (PropertyListValue) -> Bool = { _ in true }
	) {
		self.name = name
		self.registration = registration
		self.validation = validation
		self.storage = storage

		switch registration {
		case .none: self.traits = traits.union(.unregistered)
		case .emptyDictionary, .emptyArray: self.traits = traits
		}
	}

	var registeredDefault: PropertyListValue? {
		switch registration {
		case .none: nil
		case .emptyDictionary: .dictionary([:])
		case .emptyArray: .array([])
		}
	}

	func coerce(_ value: PropertyListValue) -> PropertyListValue? {
		guard validation(value) else { return nil }
		switch registration {
		case .emptyArray: guard value.array != nil else { return nil }
		case .emptyDictionary: guard value.dictionary != nil else { return nil }
		case .none: break
		}
		return value
	}
}

/** A family of keys sharing a prefix or suffix — per-notification settings,
 per-window frames, per-theme setting stores. The individual names are made at
 runtime, so the catalogue matches them by pattern.

 A family carries the same import contract a declaration does: `coerce` decides
 what shape a name in the family may hold, so an imported file cannot write an
 arbitrary property list under a name nothing declares one by one. The default
 refuses every container, which is what a family of scalar settings wants. */
nonisolated struct SettingsKeyFamily: Sendable {
	enum Match: UInt, Sendable {
		case exact = 0
		case prefix = 1
		case suffix = 2
	}

	let pattern: String
	let match: Match
	let storage: SettingStorage
	let traits: SettingTraits
	private let coercion: @Sendable (String, PropertyListValue) -> PropertyListValue?

	init(
		_ pattern: String,
		match: Match = .prefix,
		storage: SettingStorage = .container,
		traits: SettingTraits = [],
		coerce: @escaping @Sendable (String, PropertyListValue) -> PropertyListValue? = Self.scalar
	) {
		self.pattern = pattern
		self.match = match
		self.storage = storage
		self.traits = traits
		coercion = coerce
	}

	func matches(_ name: String) -> Bool {
		switch match {
		case .exact: name == pattern
		case .prefix: name.hasPrefix(pattern)
		case .suffix: name.hasSuffix(pattern)
		}
	}

	/// Validates and coerces an imported value for one name in the family, or
	/// returns `nil` to reject it.
	func coerce(_ name: String, _ value: PropertyListValue) -> PropertyListValue? {
		guard matches(name) else { return nil }
		return coercion(name, value)
	}

	/// The default shape: one scalar, never a container or an opaque blob.
	static let scalar: @Sendable (String, PropertyListValue) -> PropertyListValue? = { _, value in
		switch value {
		case .string, .boolean, .integer, .double: value
		case .date, .data, .array, .dictionary: nil
		}
	}

	var isCatalogued: Bool {
		traits.contains(.uncatalogued) == false
	}
}

/// Namespace for the settings declarations, grouped by area.
nonisolated enum SettingsKeys {}
