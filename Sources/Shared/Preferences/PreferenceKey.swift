/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation

// MARK: - Values

/** A value that can round-trip through the property list `UserDefaults` stores.

 `preferenceValue(from:)` coerces across the representations `UserDefaults`
 legitimately hands back — an `NSNumber` for a `Bool`, a string for a number
 written by `defaults write` or carried in an imported plist — and returns `nil`
 when the object cannot represent the type at all. That `nil` is what lets an
 import reject a value instead of silently reading zero. */
public protocol PreferenceValue: Equatable, Sendable {
	nonisolated static func preferenceValue(from object: Any) -> Self? // nonisolated: pure

	nonisolated var preferenceObject: Any { get } // nonisolated: pure
}

/** Enumerations whose raw value is the integer stored in the preference.

 An unknown raw value decodes to `nil`, so the typed read falls back to the
 key's declared default rather than trapping. */
public protocol PreferenceEnum: PreferenceValue, RawRepresentable where RawValue == UInt {}

public nonisolated extension PreferenceEnum { // nonisolated: value
	static func preferenceValue(from object: Any) -> Self? {
		guard let raw = UInt.preferenceValue(from: object) else {
			return nil
		}

		return Self(rawValue: raw)
	}

	var preferenceObject: Any {
		NSNumber(value: rawValue)
	}
}

/// A number written by `defaults write`, or carried in a hand-edited plist,
/// arrives as a string; anything that is not a number at all is a reject.
private nonisolated func preferenceNumber(from object: Any) -> NSNumber? { // nonisolated: pure
	if let number = object as? NSNumber {
		return number
	}

	guard let string = object as? String else {
		return nil
	}

	if let integer = Int64(string) {
		return NSNumber(value: integer)
	}

	return Double(string).map(NSNumber.init(value:))
}

nonisolated extension Bool: PreferenceValue { // nonisolated: value
	public static func preferenceValue(from object: Any) -> Bool? {
		if let number = object as? NSNumber {
			return number.boolValue
		}

		return switch (object as? String)?.lowercased() {
		case "1", "true", "yes", "on": true
		case "0", "false", "no", "off": false
		default: nil
		}
	}

	public var preferenceObject: Any {
		NSNumber(value: self)
	}
}

nonisolated extension Int: PreferenceValue { // nonisolated: value
	public static func preferenceValue(from object: Any) -> Int? {
		preferenceNumber(from: object)?.intValue
	}

	public var preferenceObject: Any {
		NSNumber(value: self)
	}
}

nonisolated extension UInt: PreferenceValue { // nonisolated: value
	public static func preferenceValue(from object: Any) -> UInt? {
		preferenceNumber(from: object)?.uintValue
	}

	public var preferenceObject: Any {
		NSNumber(value: self)
	}
}

nonisolated extension UInt16: PreferenceValue { // nonisolated: value
	public static func preferenceValue(from object: Any) -> UInt16? {
		preferenceNumber(from: object)?.uint16Value
	}

	public var preferenceObject: Any {
		NSNumber(value: self)
	}
}

nonisolated extension Double: PreferenceValue { // nonisolated: value
	public static func preferenceValue(from object: Any) -> Double? {
		preferenceNumber(from: object)?.doubleValue
	}

	public var preferenceObject: Any {
		NSNumber(value: self)
	}
}

nonisolated extension String: PreferenceValue { // nonisolated: value
	public static func preferenceValue(from object: Any) -> String? {
		object as? String
	}

	public var preferenceObject: Any {
		self
	}
}

nonisolated extension Data: PreferenceValue { // nonisolated: value
	public static func preferenceValue(from object: Any) -> Data? {
		object as? Data
	}

	public var preferenceObject: Any {
		self
	}
}

nonisolated extension Array: PreferenceValue where Element: PreferenceValue { // nonisolated: value
	public static func preferenceValue(from object: Any) -> [Element]? {
		guard let objects = object as? [Any] else {
			return nil
		}

		var elements: [Element] = []
		elements.reserveCapacity(objects.count)

		for element in objects {
			// One unreadable element makes the whole list a reject rather than a
			// silently shortened list.
			guard let value = Element.preferenceValue(from: element) else {
				return nil
			}

			elements.append(value)
		}

		return elements
	}

	public var preferenceObject: Any {
		map(\.preferenceObject)
	}
}

// MARK: - Keys

/// Which defaults database a preference lives in.
public nonisolated enum PreferenceStorage: Sendable { // nonisolated: value
	/// The application-group container shared with the XPC connection host.
	case container
	/// `UserDefaults.standard`, for keys AppKit or a vendored library reads out
	/// of the application's own domain.
	case standard
}

public nonisolated struct PreferenceTraits: OptionSet, Sendable { // nonisolated: value
	public let rawValue: UInt

	public init(rawValue: UInt) {
		self.rawValue = rawValue
	}

	/// Never written to an exported preference file, and ignored on import.
	public static let excludedFromExport = Self(rawValue: 1 << 0)
	/// Absent from the preference catalogue, which also excludes it from export.
	public static let uncatalogued = Self(rawValue: 1 << 1)
	/// Read with a default that is never contributed to the registration domain.
	public static let unregistered = Self(rawValue: 1 << 2)
}

/// The type-erased face of a declaration, for registration and cataloguing.
public protocol AnyPreferenceKey: Sendable {
	nonisolated var name: String { get } // nonisolated: pure
	nonisolated var storage: PreferenceStorage { get } // nonisolated: pure
	nonisolated var traits: PreferenceTraits { get } // nonisolated: pure

	/// The registration-domain entry, or `nil` for an unregistered key.
	nonisolated var registeredDefault: PropertyListValue? { get } // nonisolated: pure

	/// Validates and coerces an imported value, or returns `nil` to reject it.
	nonisolated func coerce(_ value: PropertyListValue) -> PropertyListValue? // nonisolated: pure
}

public nonisolated extension AnyPreferenceKey { // nonisolated: value
	var isCatalogued: Bool {
		traits.contains(.uncatalogued) == false
	}
}

/** One preference, declared once: its name, its type, its default, where it is
 stored, and how export and the catalogue treat it.

 The registration domain and the three catalogue plists are derived from these
 declarations, so a key cannot exist in the code without existing in the
 registration domain — which is what removes the force-unwrapped reads that used
 to depend on a plist staying in sync by hand. */
public nonisolated struct PreferenceKey<Value: PreferenceValue>: AnyPreferenceKey { // nonisolated: value
	public let name: String
	public let defaultValue: Value
	public let storage: PreferenceStorage
	public let traits: PreferenceTraits

	public init(
		_ name: String,
		default defaultValue: Value,
		storage: PreferenceStorage = .container,
		traits: PreferenceTraits = []
	) {
		self.name = name
		self.defaultValue = defaultValue
		self.storage = storage
		self.traits = traits
	}

	public var registeredDefault: PropertyListValue? {
		traits.contains(.unregistered) ? nil : PropertyListValue(propertyList: defaultValue.preferenceObject)
	}

	public func coerce(_ value: PropertyListValue) -> PropertyListValue? {
		guard let coerced = Value.preferenceValue(from: value.propertyListObject) else {
			return nil
		}

		return PropertyListValue(propertyList: coerced.preferenceObject)
	}
}

/** A key whose value is a property-list container owned by the subsystem that
 writes it — a client list, a policy dictionary. It is declared here so the key
 is catalogued and registered like any other; decoding stays with that
 subsystem. */
public nonisolated struct UntypedPreferenceKey: AnyPreferenceKey { // nonisolated: value
	public enum RegisteredDefault: Sendable {
		case none
		case emptyDictionary
		case emptyArray
	}

	public let name: String
	public let storage: PreferenceStorage
	public let traits: PreferenceTraits
	private let registration: RegisteredDefault

	public init(
		_ name: String,
		default registration: RegisteredDefault = .none,
		storage: PreferenceStorage = .container,
		traits: PreferenceTraits = []
	) {
		self.name = name
		self.registration = registration
		self.storage = storage

		switch registration {
		case .none: self.traits = traits.union(.unregistered)
		case .emptyDictionary, .emptyArray: self.traits = traits
		}
	}

	public var registeredDefault: PropertyListValue? {
		switch registration {
		case .none: nil
		case .emptyDictionary: .dictionary([:])
		case .emptyArray: .array([])
		}
	}

	/// A ``PropertyListValue`` is a property list by construction, so a key with
	/// no declared type has nothing left to check.
	public func coerce(_ value: PropertyListValue) -> PropertyListValue? {
		value
	}
}

/** A family of keys sharing a prefix or suffix — per-notification settings,
 per-window frames, per-theme setting stores. The individual names are made at
 runtime, so the catalogue matches them by pattern. */
public nonisolated struct PreferenceKeyFamily: Sendable { // nonisolated: value
	public enum Match: UInt, Sendable {
		case exact = 0
		case prefix = 1
		case suffix = 2
	}

	public let pattern: String
	public let match: Match
	public let storage: PreferenceStorage
	public let traits: PreferenceTraits

	public init(
		_ pattern: String,
		match: Match = .prefix,
		storage: PreferenceStorage = .container,
		traits: PreferenceTraits = []
	) {
		self.pattern = pattern
		self.match = match
		self.storage = storage
		self.traits = traits
	}

	public func matches(_ name: String) -> Bool {
		switch match {
		case .exact: name == pattern
		case .prefix: name.hasPrefix(pattern)
		case .suffix: name.hasSuffix(pattern)
		}
	}

	public var isCatalogued: Bool {
		traits.contains(.uncatalogued) == false
	}
}

/// Namespace for the preference declarations, grouped by area.
public nonisolated enum Preferences {} // nonisolated: value

// MARK: - Typed access

public nonisolated extension TextualUserDefaults { // nonisolated: pure
	/// The defaults database a declaration is stored in.
	func store(for storage: PreferenceStorage) -> UserDefaults {
		switch storage {
		case .container: self
		case .standard: .standard
		}
	}

	/// The effective value: what the user chose, or the declared default.
	subscript<Value>(key: PreferenceKey<Value>) -> Value {
		get { self[stored: key] ?? key.defaultValue }
		set { self[stored: key] = newValue }
	}

	/** The stored value, or `nil` when nothing has been written and no default
	 was registered. Reading through this is how a setting whose "unset" state is
	 meaningful keeps it distinguishable from its default. */
	subscript<Value>(stored key: PreferenceKey<Value>) -> Value? {
		get {
			guard let object = store(for: key.storage).object(forKey: key.name) else {
				return nil
			}

			return Value.preferenceValue(from: object)
		}
		set {
			let store = store(for: key.storage)

			guard let newValue else {
				store.removeObject(forKey: key.name)
				return
			}

			store.set(newValue.preferenceObject, forKey: key.name)
		}
	}

	/// Writes the default into the registration domain rather than the
	/// persistent one, for settings a theme recomputes at every launch.
	func registerDefault<Value>(_ value: Value, for key: PreferenceKey<Value>) {
		store(for: key.storage).register(defaults: [key.name: value.preferenceObject])
	}

	func removeValue(for key: some AnyPreferenceKey) {
		store(for: key.storage).removeObject(forKey: key.name)
	}

	/** The stored value of a key whose shape belongs to the subsystem that
	 writes it, narrowed out of the `Any` `UserDefaults` returns. */
	func propertyListValue(for key: some AnyPreferenceKey) -> PropertyListValue? {
		store(for: key.storage).object(forKey: key.name)
			.flatMap(PropertyListValue.init(propertyList:))
	}

	func setPropertyListValue(_ value: PropertyListValue?, for key: some AnyPreferenceKey) {
		store(for: key.storage).set(value?.propertyListObject, forKey: key.name)
	}
}

public extension Preferences {
	/** The shared store, which the main actor keeps for the lifetime of the
	 process so bindings observe one object and a read costs nothing. */
	@MainActor
	static var defaults: TextualUserDefaults {
		TextualUserDefaults.container
	}

	/** A private handle on the same store, for code that runs outside the main
	 actor. Reads and writes land in the same file; only KVO identity differs,
	 and nothing off the main actor observes it. */
	nonisolated static var detachedDefaults: TextualUserDefaults { // nonisolated: pure
		TextualUserDefaults.suite()
	}
}

public extension PreferenceKey {
	/// The effective value in the shared store: what the user chose, or the
	/// declared default.
	@MainActor
	var value: Value {
		get { Preferences.defaults[self] }
		nonmutating set { Preferences.defaults[self] = newValue }
	}

	/// The stored value, or `nil` when nothing has been written and no default
	/// was registered.
	@MainActor
	var storedValue: Value? {
		get { Preferences.defaults[stored: self] }
		nonmutating set { Preferences.defaults[stored: self] = newValue }
	}

	/// ``value``, read through a private handle on the store, for code that
	/// runs outside the main actor.
	nonisolated var detachedValue: Value { // nonisolated: pure
		get { Preferences.detachedDefaults[self] }
		nonmutating set { Preferences.detachedDefaults[self] = newValue }
	}

	/// ``storedValue`` through the same private handle.
	nonisolated var detachedStoredValue: Value? { // nonisolated: pure
		get { Preferences.detachedDefaults[stored: self] }
		nonmutating set { Preferences.detachedDefaults[stored: self] = newValue }
	}
}

public extension AnyPreferenceKey {
	/// The stored value, for the handful of keys whose value shape belongs to
	/// the subsystem that writes it.
	@MainActor
	var propertyListValue: PropertyListValue? {
		get { Preferences.defaults.propertyListValue(for: self) }
		nonmutating set { Preferences.defaults.setPropertyListValue(newValue, for: self) }
	}

	@MainActor
	func reset() {
		Preferences.defaults.removeValue(for: self)
	}
}
