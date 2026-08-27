// The MIT License
//
// Copyright (c) 2016 Gwendal Roué
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
#if canImport(GRMustacheKeyAccess)
	import GRMustacheKeyAccess
#endif

/// GRMustache provides built-in support for rendering `NSObject`.
extension NSObject: MustacheBoxable {
	/// `NSObject` adopts the `MustacheBoxable` protocol so that it can feed
	/// Mustache templates.
	///
	/// You should not directly call the `mustacheBox` property.
	///
	///
	/// NSObject's default implementation handles two general cases:
	///
	/// - Enumerable objects that conform to the `NSFastEnumeration` protocol,
	///   such as `NSArray` and `NSOrderedSet`.
	/// - All other objects
	///
	/// GRMustache ships with a few specific classes that escape the general
	/// cases and provide their own rendering behavior: `NSDictionary`,
	/// `NSFormatter`, `NSNull`, `NSNumber`, `NSString`, and `NSSet` (see the
	/// documentation for those classes).
	///
	/// Your own subclasses of NSObject can also override the `mustacheBox`
	/// method and provide their own custom behavior.
	///
	///
	/// ## Arrays
	///
	/// An object is treated as an array if it conforms to `NSFastEnumeration`.
	/// This is the case of `NSArray` and `NSOrderedSet`, for example.
	/// `NSDictionary` and `NSSet` have their own custom Mustache rendering: see
	/// their documentation for more information.
	///
	///
	/// ### Rendering
	///
	/// - `{{array}}` renders the concatenation of the renderings of the
	///   array items.
	///
	/// - `{{#array}}...{{/array}}` renders as many times as there are items in
	///   `array`, pushing each item on its turn on the top of the
	///   context stack.
	///
	/// - `{{^array}}...{{/array}}` renders if and only if `array` is empty.
	///
	///
	/// ### Keys exposed to templates
	///
	/// An array can be queried for the following keys:
	///
	/// - `count`: number of elements in the array
	/// - `first`: the first object in the array
	/// - `last`: the last object in the array
	///
	/// Because 0 (zero) is falsey, `{{#array.count}}...{{/array.count}}`
	/// renders once, if and only if `array` is not empty.
	///
	///
	/// ## Other objects
	///
	/// Other objects fall in the general case.
	///
	/// Their keys are extracted with the `valueForKey:` method, as long as the
	/// key is a property name, a custom property getter, or the name of a
	/// `NSManagedObject` attribute.
	///
	///
	/// ### Rendering
	///
	/// - `{{object}}` renders the result of the `description` method,
	///   HTML-escaped.
	///
	/// - `{{{object}}}` renders the result of the `description` method, *not*
	///   HTML-escaped.
	///
	/// - `{{#object}}...{{/object}}` renders once, pushing `object` on the top
	///   of the context stack.
	///
	/// - `{{^object}}...{{/object}}` does not render.
	@objc open var mustacheBox: MustacheBox {
		if let enumerable = self as? NSFastEnumeration {
			// Enumerable

			// Turn enumerable into a Swift array that we know how to box
			return makeMustacheBox(Array(IteratorSequence(NSFastEnumerationIterator(enumerable))))

		} else {
			// Generic NSObject

			#if OBJC
				return MustacheBox(
					value: self,
					keyedSubscript: { (key: String) in
						if GRMustacheKeyAccess.isSafeMustacheKey(key, for: self) {
							// Use valueForKey: for safe keys
							self.value(forKey: key)
						} else {
							// Missing key
							nil
						}
					}
				)
			#else
				return MustacheBox(value: self)
			#endif
		}
	}
}

/// GRMustache provides built-in support for rendering `NSNull`.
extension NSNull {
	/// `NSNull` adopts the `MustacheBoxable` protocol so that it can feed
	/// Mustache templates.
	///
	/// You should not directly call the `mustacheBox` property. Always use the
	/// `makeMustacheBox()` function instead:
	///
	///     NSNull().mustacheBox   // Valid, but discouraged
	///     makeMustacheBox(NSNull())          // Preferred
	///
	///
	/// ### Rendering
	///
	/// - `{{null}}` does not render.
	///
	/// - `{{#null}}...{{/null}}` does not render (NSNull is falsey).
	///
	/// - `{{^null}}...{{/null}}` does render (NSNull is falsey).
	@objc override open var mustacheBox: MustacheBox {
		MustacheBox(
			value: self,
			boolValue: false,
			render: { (_: RenderingInfo) in Rendering("") }
		)
	}
}

/// GRMustache provides built-in support for rendering `NSNumber`.
extension NSNumber {
	/// `NSNumber` adopts the `MustacheBoxable` protocol so that it can feed
	/// Mustache templates.
	///
	/// You should not directly call the `mustacheBox` property.
	///
	///
	/// ### Rendering
	///
	/// NSNumber renders exactly like Swift numbers: depending on its internal
	/// objCType, an NSNumber is rendered as a Swift Bool, Int, UInt, Int64,
	/// UInt64, or Double.
	///
	/// - `{{number}}` is rendered with built-in Swift String Interpolation.
	///   Custom formatting can be explicitly required with NumberFormatter,
	///   as in `{{format(a)}}` (see `Formatter`).
	///
	/// - `{{#number}}...{{/number}}` renders if and only if `number` is
	///   not 0 (zero).
	///
	/// - `{{^number}}...{{/number}}` renders if and only if `number` is 0 (zero).
	///
	@objc override open var mustacheBox: MustacheBox {
		let objCType = String(cString: objCType)
		switch objCType {
		case "c":
			return makeMustacheBox(Int(int8Value))
		case "C":
			return makeMustacheBox(UInt(uint8Value))
		case "s":
			return makeMustacheBox(Int(int16Value))
		case "S":
			return makeMustacheBox(UInt(uint16Value))
		case "i":
			return makeMustacheBox(Int(int32Value))
		case "I":
			return makeMustacheBox(UInt(uint32Value))
		case "l":
			return makeMustacheBox(intValue)
		case "L":
			return makeMustacheBox(uintValue)
		case "q":
			return makeMustacheBox(int64Value)
		case "Q":
			return makeMustacheBox(uint64Value)
		case "f":
			return makeMustacheBox(floatValue)
		case "d":
			return makeMustacheBox(doubleValue)
		case "B":
			return makeMustacheBox(boolValue)
		default:
			return makeMustacheBox(self)
		}
	}
}

/// GRMustache provides built-in support for rendering `NSString`.
extension NSString {
	/// `NSString` adopts the `MustacheBoxable` protocol so that it can feed
	/// Mustache templates.
	///
	/// You should not directly call the `mustacheBox` property.
	///
	///
	/// ### Rendering
	///
	/// - `{{string}}` renders the string, HTML-escaped.
	///
	/// - `{{{string}}}` renders the string, *not* HTML-escaped.
	///
	/// - `{{#string}}...{{/string}}` renders if and only if `string` is
	///   not empty.
	///
	/// - `{{^string}}...{{/string}}` renders if and only if `string` is empty.
	///
	/// HTML-escaping of `{{string}}` tags is disabled for Text templates: see
	/// `Configuration.contentType` for a full discussion of the content type of
	/// templates.
	///
	///
	/// ### Keys exposed to templates
	///
	/// A string can be queried for the following keys:
	///
	/// - `length`: the number of characters in the string (using Swift method).
	@objc override open var mustacheBox: MustacheBox {
		makeMustacheBox(self as String)
	}
}

/// GRMustache provides built-in support for rendering `NSSet`.
extension NSSet {
	/// `NSSet` adopts the `MustacheBoxable` protocol so that it can feed
	/// Mustache templates.
	///
	///     let set: NSSet = [1,2,3]
	///
	///     // Renders "213"
	///     let template = try! Template(string: "{{#set}}{{.}}{{/set}}")
	///     try! template.render(makeMustacheBox(["set": makeMustacheBox(set)]))
	///
	///
	/// You should not directly call the `mustacheBox` property.
	///
	/// ### Rendering
	///
	/// - `{{set}}` renders the concatenation of the renderings of the set
	///   items, in any order.
	///
	/// - `{{#set}}...{{/set}}` renders as many times as there are items in
	///   `set`, pushing each item on its turn on the top of the context stack.
	///
	/// - `{{^set}}...{{/set}}` renders if and only if `set` is empty.
	///
	///
	/// ### Keys exposed to templates
	///
	/// A set can be queried for the following keys:
	///
	/// - `count`: number of elements in the set
	/// - `first`: the first object in the set
	///
	/// Because 0 (zero) is falsey, `{{#set.count}}...{{/set.count}}` renders
	/// once, if and only if `set` is not empty.
	@objc override open var mustacheBox: MustacheBox {
		makeMustacheBox(Set(IteratorSequence(NSFastEnumerationIterator(self)).compactMap { $0 as? AnyHashable }))
	}
}

/// GRMustache provides built-in support for rendering `NSDictionary`.
extension NSDictionary {
	/// `NSDictionary` adopts the `MustacheBoxable` protocol so that it can feed
	/// Mustache templates.
	///
	///     // Renders "Freddy Mercury"
	///     let dictionary: NSDictionary = [
	///         "firstName": "Freddy",
	///         "lastName": "Mercury"]
	///     let template = try! Template(string: "{{firstName}} {{lastName}}")
	///     let rendering = try! template.render(makeMustacheBox(dictionary))
	///
	///
	/// You should not directly call the `mustacheBox` property.
	///
	///
	/// ### Rendering
	///
	/// - `{{dictionary}}` renders the result of the `description` method,
	///   HTML-escaped.
	///
	/// - `{{{dictionary}}}` renders the result of the `description` method,
	///   *not* HTML-escaped.
	///
	/// - `{{#dictionary}}...{{/dictionary}}` renders once, pushing `dictionary`
	///   on the top of the context stack.
	///
	/// - `{{^dictionary}}...{{/dictionary}}` does not render.
	///
	///
	/// In order to iterate over the key/value pairs of a dictionary, use the
	/// `each` filter from the Standard Library:
	///
	///     // Attach StandardLibrary.each to the key "each":
	///     let template = try! Template(string: "<{{# each(dictionary) }}{{@key}}:{{.}}, {{/}}>")
	///     template.register(StandardLibrary.each, forKey: "each")
	///
	///     // Renders "<name:Arthur, age:36, >"
	///     let dictionary = ["name": "Arthur", "age": 36] as NSDictionary
	///     let rendering = try! template.render(["dictionary": dictionary])
	@objc override open var mustacheBox: MustacheBox {
		makeMustacheBox(self as? [AnyHashable: Any])
	}
}

/// Support for Mustache rendering of ReferenceConvertible types.
public extension ReferenceConvertible where Self: MustacheBoxable {
	/// Returns a MustacheBox that behaves like the equivalent NSObject.
	///
	/// See NSObject.mustacheBox
	var mustacheBox: MustacheBox {
		guard let reference = self as? ReferenceType else { return .empty }
		return reference.mustacheBox
	}
}

/// Data can feed Mustache templates.
extension Data: MustacheBoxable {}

/// Date can feed Mustache templates.
extension Date: MustacheBoxable {}

/// URL can feed Mustache templates.
extension URL: MustacheBoxable {}

/// UUID can feed Mustache templates.
extension UUID: MustacheBoxable {}
