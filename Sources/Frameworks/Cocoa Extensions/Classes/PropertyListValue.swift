/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

/** One value a property list can hold.

 A preferences file, a theme's `design.plist`, a network catalogue and an
 exported configuration are all property lists, and the framework hands them
 over as `[String: Any]`. `Any` is neither `Sendable` nor checkable, so it stops
 at the boundary: `init(propertyList:)` narrows what the framework returns into
 this closed set of cases, `propertyListObject` widens it again for the one call
 that needs it, and everything between the two is typed.

 The `boolean` and `integer` cases stay apart because a property list keeps them
 apart. `<true/>` and `<integer>1</integer>` are different on disk, and a build
 that collapsed them would rewrite every flag in the user's preferences the
 first time it saved. */
public enum PropertyListValue: Hashable, Sendable {
	case string(String)
	case boolean(Bool)
	case integer(Int)
	case double(Double)
	case date(Date)
	case data(Data)
	case array([PropertyListValue])
	case dictionary([String: PropertyListValue])
}

// MARK: - Reading

public extension PropertyListValue {
	var string: String? {
		guard case let .string(value) = self else {
			return nil
		}

		return value
	}

	var boolean: Bool? {
		switch self {
		case let .boolean(value): value
		/* A flag written by an older build, or by a plist editor, arrives as a
		 number; reading it as one is what keeps that file working. */
		case let .integer(value): value != 0
		default: nil
		}
	}

	var integer: Int? {
		switch self {
		case let .integer(value): value
		case let .boolean(value): value ? 1 : 0
		case let .double(value): Int(value)
		default: nil
		}
	}

	var double: Double? {
		switch self {
		case let .double(value): value
		case let .integer(value): Double(value)
		default: nil
		}
	}

	var date: Date? {
		guard case let .date(value) = self else {
			return nil
		}

		return value
	}

	var data: Data? {
		guard case let .data(value) = self else {
			return nil
		}

		return value
	}

	var array: [PropertyListValue]? {
		guard case let .array(value) = self else {
			return nil
		}

		return value
	}

	var dictionary: [String: PropertyListValue]? {
		guard case let .dictionary(value) = self else {
			return nil
		}

		return value
	}

	/// The strings in an array of strings, or `nil` if the value is not one.
	var stringArray: [String]? {
		guard let array else {
			return nil
		}

		let strings = array.compactMap(\.string)

		return strings.count == array.count ? strings : nil
	}
}

// MARK: - Writing

public extension PropertyListValue {
	init(_ value: String) {
		self = .string(value)
	}

	init(_ value: Bool) {
		self = .boolean(value)
	}

	init(_ value: some BinaryInteger) {
		self = .integer(Int(value))
	}

	init(_ value: Double) {
		self = .double(value)
	}

	init(_ value: Date) {
		self = .date(value)
	}

	init(_ value: Data) {
		self = .data(value)
	}

	init(_ value: [String]) {
		self = .array(value.map(PropertyListValue.string))
	}
}

extension PropertyListValue: ExpressibleByStringLiteral {
	public init(stringLiteral value: String) {
		self = .string(value)
	}
}

extension PropertyListValue: ExpressibleByBooleanLiteral {
	public init(booleanLiteral value: Bool) {
		self = .boolean(value)
	}
}

extension PropertyListValue: ExpressibleByIntegerLiteral {
	public init(integerLiteral value: Int) {
		self = .integer(value)
	}
}

extension PropertyListValue: ExpressibleByFloatLiteral {
	public init(floatLiteral value: Double) {
		self = .double(value)
	}
}

extension PropertyListValue: ExpressibleByArrayLiteral {
	public init(arrayLiteral elements: PropertyListValue...) {
		self = .array(elements)
	}
}

extension PropertyListValue: ExpressibleByDictionaryLiteral {
	public init(dictionaryLiteral elements: (String, PropertyListValue)...) {
		self = .dictionary(Dictionary(elements) { _, last in last })
	}
}

// MARK: - The framework boundary

public extension PropertyListValue {
	/** Narrows one value the property-list machinery handed back.

	 `nil` means the object is not a property list — a class the serializer
	 would refuse, or `NSNull` — and the caller drops it rather than carrying an
	 `Any` any further. */
	init?(propertyList object: Any) {
		switch object {
		case let value as String:
			self = .string(value)
		case let value as Date:
			self = .date(value)
		case let value as Data:
			self = .data(value)
		case let value as NSNumber:
			self = Self(number: value)
		case let value as [Any]:
			self = .array(value.compactMap { PropertyListValue(propertyList: $0) })
		case let value as [String: Any]:
			self = .dictionary(value.compactMapValues { PropertyListValue(propertyList: $0) })
		default:
			return nil
		}
	}

	/// A number tells the truth about itself through Core Foundation: a boolean
	/// is `CFBoolean`, and the floating-point types are named by `CFNumberType`.
	private init(number: NSNumber) {
		if CFGetTypeID(number) == CFBooleanGetTypeID() {
			self = .boolean(number.boolValue)

			return
		}

		switch CFNumberGetType(number as CFNumber) {
		case .float32Type, .float64Type, .floatType, .doubleType, .cgFloatType:
			self = .double(number.doubleValue)
		default:
			self = .integer(number.intValue)
		}
	}

	/// The value in the shape `PropertyListSerialization`, `UserDefaults` and
	/// `WKWebView` take. The one place `Any` is the right answer.
	var propertyListObject: Any {
		switch self {
		case let .string(value): value
		case let .boolean(value): value
		case let .integer(value): value
		case let .double(value): value
		case let .date(value): value
		case let .data(value): value
		case let .array(value): value.map(\.propertyListObject)
		case let .dictionary(value): value.propertyListObject
		}
	}
}

public extension [String: PropertyListValue] {
	/// Narrows a dictionary the property-list machinery handed back, dropping
	/// the entries that are not property lists.
	init?(propertyList object: Any) {
		guard let dictionary = object as? [String: Any] else {
			return nil
		}

		self = dictionary.compactMapValues { PropertyListValue(propertyList: $0) }
	}

	/// The dictionary in the shape the framework takes.
	var propertyListObject: [String: Any] {
		mapValues(\.propertyListObject)
	}
}

public extension [PropertyListValue] {
	/// Narrows an array the property-list machinery handed back, dropping the
	/// elements that are not property lists.
	init?(propertyList object: Any) {
		guard let array = object as? [Any] else {
			return nil
		}

		self = array.compactMap { PropertyListValue(propertyList: $0) }
	}

	/// The array in the shape the framework takes.
	var propertyListObject: [Any] {
		map(\.propertyListObject)
	}
}
