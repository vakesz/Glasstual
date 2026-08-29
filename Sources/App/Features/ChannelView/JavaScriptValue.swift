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

/** One value the WebKit bridge converts between Swift and the page.

 `callAsyncJavaScript(_:arguments:…)` takes `[String: Any]` and throws on the
 whole call if one value in it is a type it cannot convert, so an argument has
 to be reduced to what JavaScript has before it is handed over. That reduction
 used to hand back `Any` and hope; this is the closed set it reduces to, with
 `bridging` narrowing what a caller passed and ``bridgedObject`` widening it
 again for the one call that needs it.

 A value the page has no equivalent for becomes ``null`` rather than travelling
 as itself, which is what keeps one unsupported argument from failing the call
 it was part of. */
public nonisolated enum JavaScriptValue: Hashable, Sendable { // nonisolated: value
	case null
	case string(String)
	case boolean(Bool)
	case integer(Int)
	case double(Double)
	case array([JavaScriptValue])
	case object([String: JavaScriptValue])
}

public nonisolated extension JavaScriptValue { // nonisolated: value
	var string: String? {
		guard case let .string(value) = self else {
			return nil
		}

		return value
	}

	var boolean: Bool? {
		guard case let .boolean(value) = self else {
			return nil
		}

		return value
	}

	var integer: Int? {
		switch self {
		case let .integer(value): value
		case let .double(value): Int(value)
		default: nil
		}
	}

	var array: [JavaScriptValue]? {
		guard case let .array(value) = self else {
			return nil
		}

		return value
	}

	var object: [String: JavaScriptValue]? {
		guard case let .object(value) = self else {
			return nil
		}

		return value
	}

	var isNull: Bool {
		self == .null
	}
}

public nonisolated extension JavaScriptValue { // nonisolated: value
	/** Reduces a value a caller passed to what the bridge converts.

	 A URL travels as its absolute string, because that is what a page can use
	 and what every caller here means by one. A dictionary key that is not a
	 string has no JavaScript equivalent at all, so the entry is dropped rather
	 than the object being refused. */
	init(bridging value: Any) {
		switch value {
		case let url as URL:
			self = .string(url.absoluteString)
		case let string as String:
			self = .string(string)
		case let number as NSNumber:
			self = Self(number: number)
		case let array as [Any]:
			self = .array(array.map(JavaScriptValue.init(bridging:)))
		case let dictionary as [AnyHashable: Any]:
			self = .object(Self.object(bridging: dictionary))
		default:
			self = .null
		}
	}

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

	/// The entries of a bridged dictionary whose keys are strings.
	static func object(bridging dictionary: [AnyHashable: Any]) -> [String: JavaScriptValue] {
		var result: [String: JavaScriptValue] = [:]

		for (key, value) in dictionary {
			guard let key = key as? String else {
				continue
			}

			result[key] = JavaScriptValue(bridging: value)
		}

		return result
	}

	/// The value in the shape `callAsyncJavaScript` takes. The one place `Any`
	/// is the right answer.
	var bridgedObject: Any {
		switch self {
		case .null: NSNull()
		case let .string(value): value
		case let .boolean(value): value
		case let .integer(value): value
		case let .double(value): value
		case let .array(value): value.map(\.bridgedObject)
		case let .object(value): value.mapValues(\.bridgedObject)
		}
	}
}
