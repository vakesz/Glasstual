// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

// MARK: - Values

/** A value that can round-trip through the property list `UserDefaults` stores.

 `preferenceValue(from:)` coerces across the representations `UserDefaults`
 legitimately hands back — an `NSNumber` for a `Bool`, a string for a number
 written by `defaults write` or carried in an imported plist — and returns `nil`
 when the object cannot represent the type at all. That `nil` is what lets an
 import reject a value instead of silently reading zero. */
protocol PreferenceValue: Equatable, Sendable {
	nonisolated static func preferenceValue(from object: Any) -> Self? // nonisolated: pure

	/// The object written into the defaults store, or `nil` for a value that
	/// has no representation there — an unarchivable colour, say. Nothing is
	/// written for a `nil`: a placeholder would read back as unusable and
	/// shadow the declared default.
	nonisolated var preferenceObject: Any? { get } // nonisolated: pure
}

/** Enumerations whose raw value is the integer stored in the preference.

 An unknown raw value decodes to `nil`, so the typed read falls back to the
 key's declared default rather than trapping. */
protocol PreferenceEnum: PreferenceValue, RawRepresentable where RawValue == UInt {}

extension PreferenceEnum {
	nonisolated static func preferenceValue(from object: Any) -> Self? { // nonisolated: pure
		guard let raw = UInt.preferenceValue(from: object) else {
			return nil
		}

		return Self(rawValue: raw)
	}

	nonisolated var preferenceObject: Any? { // nonisolated: pure
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

/// Parse integral numeric strings without rounding them through Double first.
private nonisolated func preferenceInteger<Value: FixedWidthInteger>( // nonisolated: pure
	from string: String, as _: Value.Type
) -> Value? {
	let sign: Substring
	var digits: String
	let fractionCount: Int
	let exponentText: Substring
	let radix: Int
	if let match = string.wholeMatch(of: /([+-]?)([0-9]*)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?/) {
		let fraction = match.3 ?? ""
		sign = match.1
		digits = String(match.2) + fraction
		fractionCount = fraction.count
		exponentText = match.4 ?? "0"
		radix = 10
	} else if let match = string
		.wholeMatch(of: /([+-]?)0[xX]([0-9a-fA-F]*)(?:\.([0-9a-fA-F]*))?(?:[pP]([+-]?[0-9]+))?/)
	{
		// Double accepted hexadecimal strings too. Expand nibbles so their binary exponent stays exact.
		let fraction = match.3 ?? ""
		let bits = (String(match.2) + fraction).compactMap(\.hexDigitValue).map { value in
			let bits = String(value, radix: 2)
			return String(repeating: "0", count: 4 - bits.count) + bits
		}.joined()
		sign = match.1
		digits = bits
		fractionCount = fraction.count * 4
		exponentText = match.4 ?? "0"
		radix = 2
	} else {
		return nil
	}
	guard !digits.isEmpty else { return nil }
	digits = String(digits.drop(while: { $0 == "0" }))
	if digits.isEmpty {
		return 0
	}
	guard let exponent = Int(exponentText) else { return nil }
	let (shift, overflow) = exponent.subtractingReportingOverflow(fractionCount)
	guard !overflow else { return nil }
	if shift >= 0 {
		let limit = radix == 10 ? 20 : 64
		guard shift <= limit, digits.count <= limit - shift else { return nil }
		digits += String(repeating: "0", count: shift)
	} else {
		guard shift > -digits.count else { return nil }
		let removedCount = -shift
		guard digits.suffix(removedCount).allSatisfy({ $0 == "0" }) else { return nil }
		digits.removeLast(removedCount)
	}
	return Value(String(sign) + digits, radix: radix)
}

nonisolated extension Bool: PreferenceValue {
	static func preferenceValue(from object: Any) -> Bool? {
		if let number = object as? NSNumber {
			return number.boolValue
		}

		return switch (object as? String)?.lowercased() {
		case "1", "true", "yes", "on": true
		case "0", "false", "no", "off": false
		default: nil
		}
	}

	var preferenceObject: Any? {
		NSNumber(value: self)
	}
}

nonisolated extension Int: PreferenceValue {
	static func preferenceValue(from object: Any) -> Int? {
		if let string = object as? String {
			return preferenceInteger(from: string, as: Self.self)
		}
		return (object as? NSNumber).flatMap { Int(exactly: $0) }
	}

	var preferenceObject: Any? {
		NSNumber(value: self)
	}
}

nonisolated extension UInt: PreferenceValue {
	static func preferenceValue(from object: Any) -> UInt? {
		if let string = object as? String {
			return preferenceInteger(from: string, as: Self.self)
		}
		return (object as? NSNumber).flatMap { UInt(exactly: $0) }
	}

	var preferenceObject: Any? {
		NSNumber(value: self)
	}
}

nonisolated extension UInt16: PreferenceValue {
	static func preferenceValue(from object: Any) -> UInt16? {
		if let string = object as? String {
			return preferenceInteger(from: string, as: Self.self)
		}
		return (object as? NSNumber).flatMap { UInt16(exactly: $0) }
	}

	var preferenceObject: Any? {
		NSNumber(value: self)
	}
}

nonisolated extension Double: PreferenceValue {
	static func preferenceValue(from object: Any) -> Double? {
		guard let value = preferenceNumber(from: object)?.doubleValue, value.isFinite else { return nil }
		return value
	}

	var preferenceObject: Any? {
		isFinite ? NSNumber(value: self) : nil
	}
}

nonisolated extension String: PreferenceValue {
	static func preferenceValue(from object: Any) -> String? {
		object as? String
	}

	var preferenceObject: Any? {
		self
	}
}

nonisolated extension Data: PreferenceValue {
	static func preferenceValue(from object: Any) -> Data? {
		object as? Data
	}

	var preferenceObject: Any? {
		self
	}
}

nonisolated extension Array: PreferenceValue where Element: PreferenceValue {
	static func preferenceValue(from object: Any) -> [Element]? {
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

	var preferenceObject: Any? {
		var objects: [Any] = []
		objects.reserveCapacity(count)

		for element in self {
			// One element with no stored representation makes the whole list
			// unwritable rather than a silently shortened list.
			guard let object = element.preferenceObject else {
				return nil
			}

			objects.append(object)
		}

		return objects
	}
}

// MARK: - Keys

/// Which defaults database a preference lives in.
nonisolated enum PreferenceStorage: CaseIterable, Sendable {
	/// The application-group container shared with the XPC connection host.
	case container
	/// `UserDefaults.standard`, for keys AppKit or a vendored library reads out
	/// of the application's own domain.
	case standard
}

nonisolated struct PreferenceTraits: OptionSet, Sendable {
	let rawValue: UInt

	/// Never written to an exported preference file, and ignored on import.
	static let excludedFromExport = Self(rawValue: 1 << 0)
	/// Absent from the preference catalogue, which also excludes it from export.
	static let uncatalogued = Self(rawValue: 1 << 1)
	/// Read with a default that is never contributed to the registration domain.
	static let unregistered = Self(rawValue: 1 << 2)
}

/// The type-erased face of a declaration, for registration and cataloguing.
protocol AnyPreferenceKey: Sendable {
	nonisolated var name: String { get } // nonisolated: pure
	nonisolated var storage: PreferenceStorage { get } // nonisolated: pure
	nonisolated var traits: PreferenceTraits { get } // nonisolated: pure

	/// The registration-domain entry, or `nil` for an unregistered key.
	nonisolated var registeredDefault: PropertyListValue? { get } // nonisolated: pure

	/// Validates and coerces an imported value, or returns `nil` to reject it.
	nonisolated func coerce(_ value: PropertyListValue) -> PropertyListValue? // nonisolated: pure
	nonisolated func isValid( // nonisolated: pure
		_ value: PropertyListValue, in values: [String: PropertyListValue]
	) -> Bool
}

extension AnyPreferenceKey {
	nonisolated func isValid( // nonisolated: pure
		_ value: PropertyListValue, in _: [String: PropertyListValue]
	) -> Bool {
		coerce(value) != nil
	}

	nonisolated var isCatalogued: Bool { // nonisolated: pure
		traits.contains(.uncatalogued) == false
	}
}

/** One preference, declared once: its name, its type, its default, where it is
 stored, and how export and the catalogue treat it.

 The registration domain and the three catalogue plists are derived from these
 declarations, so a key cannot exist in the code without existing in the
 registration domain — which is what removes the force-unwrapped reads that used
 to depend on a plist staying in sync by hand. */
nonisolated struct PreferenceKey<Value: PreferenceValue>: AnyPreferenceKey {
	let name: String
	let defaultValue: Value
	let storage: PreferenceStorage
	let traits: PreferenceTraits
	private let validation: @Sendable (Value) -> Bool
	private let relatedValidation: @Sendable (Value, [String: PropertyListValue]) -> Bool

	init(
		_ name: String,
		default defaultValue: Value,
		storage: PreferenceStorage = .container,
		traits: PreferenceTraits = [],
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
		guard traits.contains(.unregistered) == false, let object = defaultValue.preferenceObject else {
			return nil
		}

		return PropertyListValue(propertyList: object)
	}

	func coerce(_ value: PropertyListValue) -> PropertyListValue? {
		guard let coerced = Value.preferenceValue(from: value.propertyListObject),
		      validation(coerced),
		      let object = coerced.preferenceObject
		else {
			return nil
		}

		return PropertyListValue(propertyList: object)
	}

	func isValid(_ value: PropertyListValue, in values: [String: PropertyListValue]) -> Bool {
		guard let coerced = Value.preferenceValue(from: value.propertyListObject) else { return false }
		return validation(coerced) && relatedValidation(coerced, values)
	}

	/** Whether the declaration accepts this typed value, including the rules it
	 shares with other keys.

	 A field checks what an imported file is checked against, so a count the
	 importer would refuse is a count the field refuses too. */
	func accepts(_ value: Value, alongside others: [String: PropertyListValue] = [:]) -> Bool {
		guard let object = value.preferenceObject,
		      let candidate = PropertyListValue(propertyList: object)
		else {
			return false
		}

		return isValid(candidate, in: others)
	}
}

/** A key whose value is a property-list container owned by the subsystem that
 writes it — a client list, a policy dictionary. It is declared here so the key
 is catalogued and registered like any other; decoding stays with that
 subsystem. */
nonisolated struct UntypedPreferenceKey: AnyPreferenceKey {
	enum RegisteredDefault: Sendable {
		case none
		case emptyDictionary
		case emptyArray
	}

	let name: String
	let storage: PreferenceStorage
	let traits: PreferenceTraits
	private let registration: RegisteredDefault
	private let validation: @Sendable (PropertyListValue) -> Bool

	init(
		_ name: String,
		default registration: RegisteredDefault = .none,
		storage: PreferenceStorage = .container,
		traits: PreferenceTraits = [],
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
nonisolated struct PreferenceKeyFamily: Sendable {
	enum Match: UInt, Sendable {
		case exact = 0
		case prefix = 1
		case suffix = 2
	}

	let pattern: String
	let match: Match
	let storage: PreferenceStorage
	let traits: PreferenceTraits
	private let coercion: @Sendable (String, PropertyListValue) -> PropertyListValue?

	init(
		_ pattern: String,
		match: Match = .prefix,
		storage: PreferenceStorage = .container,
		traits: PreferenceTraits = [],
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

/// Namespace for the preference declarations, grouped by area.
nonisolated enum Preferences {}

// MARK: - Typed access

nonisolated extension UserDefaults { // nonisolated: guarded
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

			guard let object = newValue.preferenceObject else {
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
	func registerDefault<Value>(_ value: Value, for key: PreferenceKey<Value>) {
		guard let object = value.preferenceObject else {
			return
		}

		store(for: key.storage).register(defaults: [key.name: object])
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

extension Preferences {
	/** The shared store, which the main actor keeps for the lifetime of the
	 process so bindings observe one object and a read costs nothing. */
	@MainActor
	static var defaults: GlasstualUserDefaults {
		GlasstualUserDefaults.container
	}
}

extension PreferenceKey {
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
}

/** ``PreferenceKey/value`` and ``PreferenceKey/storedValue`` through a private
 handle on the store, for code that runs outside the main actor.

 Every access builds a handle, and there is no shared one to hand out instead:
 `UserDefaults` is not `Sendable`, so nothing outside an actor may hold one for
 the process. Code that reads in a loop — a sort comparator, a rendered line, a
 member row — takes one `GlasstualUserDefaults.suite()` into a local and
 subscripts that with the keys it needs.

 An extension of its own, marked as a whole, rather than two unmarked members
 beside the main-actor ones above: the key is a value type, and every access
 here goes through `GlasstualUserDefaults`, a handle on a suite Foundation
 synchronizes. `UntypedPreferenceKey` carries the same pair below for the same
 reason. */
nonisolated extension PreferenceKey {
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

extension AnyPreferenceKey {
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

/** ``AnyPreferenceKey/propertyListValue`` through the private handle on the
 store, for code that runs outside the main actor.

 It lives on the untyped key rather than on the `AnyPreferenceKey` extension
 above, whose members are main-actor: a lone `nonisolated` member there would be
 an isolation claim about a protocol requirement, where `UntypedPreferenceKey` is
 a value type whose extension is nonisolated as a whole — as the typed key's
 detached pair is. Every access goes through `GlasstualUserDefaults`, a handle on
 a suite Foundation synchronizes. */
nonisolated extension UntypedPreferenceKey {
	var detachedPropertyListValue: PropertyListValue? {
		get { GlasstualUserDefaults.suite().propertyListValue(for: self) }
		nonmutating set { GlasstualUserDefaults.suite().setPropertyListValue(newValue, for: self) }
	}
}
