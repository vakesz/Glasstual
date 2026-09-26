// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** A value that can round-trip through the property list `UserDefaults` stores.

 `settingValue(from:)` coerces across the representations `UserDefaults`
 legitimately hands back — an `NSNumber` for a `Bool`, a string for a number
 written by `defaults write` or carried in an imported plist — and returns `nil`
 when the object cannot represent the type at all. That `nil` is what lets an
 import reject a value instead of silently reading zero. */
protocol SettingValue: Equatable, Sendable {
	nonisolated static func settingValue(from object: Any) -> Self? // nonisolated: pure

	/// The object written into the defaults store, or `nil` for a value that
	/// has no representation there — an unarchivable colour, say. Nothing is
	/// written for a `nil`: a placeholder would read back as unusable and
	/// shadow the declared default.
	nonisolated var settingObject: Any? { get } // nonisolated: pure
}

/** Enumerations whose raw value is the integer stored in the setting.

 An unknown raw value decodes to `nil`, so the typed read falls back to the
 key's declared default rather than trapping. */
protocol SettingEnum: SettingValue, RawRepresentable where RawValue == UInt {}

extension SettingEnum {
	nonisolated static func settingValue(from object: Any) -> Self? { // nonisolated: pure
		guard let raw = UInt.settingValue(from: object) else {
			return nil
		}

		return Self(rawValue: raw)
	}

	nonisolated var settingObject: Any? { // nonisolated: pure
		NSNumber(value: rawValue)
	}
}

/// A number written by `defaults write`, or carried in a hand-edited plist,
/// arrives as a string; anything that is not a number at all is a reject.
private nonisolated func settingNumber(from object: Any) -> NSNumber? { // nonisolated: pure
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
private nonisolated func settingInteger<Value: FixedWidthInteger>( // nonisolated: pure
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

nonisolated extension Bool: SettingValue {
	/// A stored boolean has to be a boolean. The string spellings `defaults
	/// write` accepts -- `"1"`, `"yes"`, `"on"` -- are not read: a hand-edited
	/// or hand-written file that spells a switch as text is a file this build
	/// rejects rather than guesses at.
	static func settingValue(from object: Any) -> Bool? {
		(object as? NSNumber)?.boolValue
	}

	var settingObject: Any? {
		NSNumber(value: self)
	}
}

nonisolated extension Int: SettingValue {
	static func settingValue(from object: Any) -> Int? {
		if let string = object as? String {
			return settingInteger(from: string, as: Self.self)
		}
		return (object as? NSNumber).flatMap { Int(exactly: $0) }
	}

	var settingObject: Any? {
		NSNumber(value: self)
	}
}

nonisolated extension UInt: SettingValue {
	static func settingValue(from object: Any) -> UInt? {
		if let string = object as? String {
			return settingInteger(from: string, as: Self.self)
		}
		return (object as? NSNumber).flatMap { UInt(exactly: $0) }
	}

	var settingObject: Any? {
		NSNumber(value: self)
	}
}

nonisolated extension UInt16: SettingValue {
	static func settingValue(from object: Any) -> UInt16? {
		if let string = object as? String {
			return settingInteger(from: string, as: Self.self)
		}
		return (object as? NSNumber).flatMap { UInt16(exactly: $0) }
	}

	var settingObject: Any? {
		NSNumber(value: self)
	}
}

nonisolated extension Double: SettingValue {
	static func settingValue(from object: Any) -> Double? {
		guard let value = settingNumber(from: object)?.doubleValue, value.isFinite else { return nil }
		return value
	}

	var settingObject: Any? {
		isFinite ? NSNumber(value: self) : nil
	}
}

nonisolated extension String: SettingValue {
	static func settingValue(from object: Any) -> String? {
		object as? String
	}

	var settingObject: Any? {
		self
	}
}

nonisolated extension Data: SettingValue {
	static func settingValue(from object: Any) -> Data? {
		object as? Data
	}

	var settingObject: Any? {
		self
	}
}

nonisolated extension Array: SettingValue where Element: SettingValue {
	static func settingValue(from object: Any) -> [Element]? {
		guard let objects = object as? [Any] else {
			return nil
		}

		var elements: [Element] = []
		elements.reserveCapacity(objects.count)

		for element in objects {
			// One unreadable element makes the whole list a reject rather than a
			// silently shortened list.
			guard let value = Element.settingValue(from: element) else {
				return nil
			}

			elements.append(value)
		}

		return elements
	}

	var settingObject: Any? {
		var objects: [Any] = []
		objects.reserveCapacity(count)

		for element in self {
			// One element with no stored representation makes the whole list
			// unwritable rather than a silently shortened list.
			guard let object = element.settingObject else {
				return nil
			}

			objects.append(object)
		}

		return objects
	}
}
