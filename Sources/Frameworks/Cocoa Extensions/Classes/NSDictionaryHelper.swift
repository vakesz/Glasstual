/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2018 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
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
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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

/* A portion of this source file contains copyrighted work derived from one or
 more 3rd party, open source projects. The use of this work is hereby
 acknowledged. */

/*
 The New BSD License

 Copyright (c) 2008 - 2010 Satoshi Nakagawa < psychs AT limechat DOT net >
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 SUCH DAMAGE.
 */

import Foundation
import ObjectiveC.runtime

private typealias BoolGetter = @convention(c) (AnyObject, Selector) -> Bool
private typealias IntegerGetter = @convention(c) (AnyObject, Selector) -> Int
private typealias UnsignedIntegerGetter = @convention(c) (AnyObject, Selector) -> UInt
private typealias Int16Getter = @convention(c) (AnyObject, Selector) -> Int16
private typealias UInt16Getter = @convention(c) (AnyObject, Selector) -> UInt16
private typealias Int64Getter = @convention(c) (AnyObject, Selector) -> Int64
private typealias UInt64Getter = @convention(c) (AnyObject, Selector) -> UInt64
private typealias DoubleGetter = @convention(c) (AnyObject, Selector) -> Double
private typealias EqualityMethod = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
private typealias ObjectGetter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?

private func dictionarySynchronized<Result>(on object: AnyObject, _ body: () -> Result) -> Result {
	objc_sync_enter(object)
	defer { objc_sync_exit(object) }
	return body()
}

private func dictionaryGetter<Value>(
	from object: Any?,
	selectorName: String,
	as _: Value.Type,
	invoke: (IMP, AnyObject, Selector) -> Value
) -> Value? {
	guard let object else { return nil }
	let receiver = object as AnyObject
	let selector = NSSelectorFromString(selectorName)
	guard receiver.responds(to: selector), let implementation = receiver.method(for: selector) else { return nil }
	return invoke(implementation, receiver, selector)
}

private func dictionaryObjectGetter(from object: Any, selector: Selector) -> AnyObject? {
	let receiver = object as AnyObject
	guard receiver.responds(to: selector), let implementation = receiver.method(for: selector) else { return nil }
	return unsafeBitCast(implementation, to: ObjectGetter.self)(receiver, selector)?.takeUnretainedValue()
}

private func dictionaryValueIsEmpty(_ value: Any) -> Bool {
	if value is NSNull {
		return true
	}
	if let string = value as? String {
		return string.isEmpty
	}
	if let data = value as? Data {
		return data.isEmpty
	}
	if let array = value as? NSArray {
		return array.count == 0
	}
	if let dictionary = value as? NSDictionary {
		return dictionary.count == 0
	}
	if let set = value as? NSSet {
		return set.count == 0
	}

	let receiver = value as AnyObject
	for selectorName in ["length", "count"] {
		let selector = NSSelectorFromString(selectorName)
		if receiver.responds(to: selector), let implementation = receiver.method(for: selector) {
			return unsafeBitCast(implementation, to: UnsignedIntegerGetter.self)(receiver, selector) == 0
		}
	}
	return false
}

extension NSDictionary {
	@objc(boolForKey:)
	func ce_bool(forKey key: Any) -> Bool {
		ce_bool(forKey: key, orUseDefault: false)
	}

	@objc(integerForKey:)
	func ce_integer(forKey key: Any) -> Int {
		ce_integer(forKey: key, orUseDefault: 0)
	}

	@objc(unsignedIntegerForKey:)
	func ce_unsignedInteger(forKey key: Any) -> UInt {
		ce_unsignedInteger(forKey: key, orUseDefault: 0)
	}

	@objc(shortForKey:)
	func ce_short(forKey key: Any) -> Int16 {
		ce_short(forKey: key, orUseDefault: 0)
	}

	@objc(unsignedShortForKey:)
	func ce_unsignedShort(forKey key: Any) -> UInt16 {
		ce_unsignedShort(forKey: key, orUseDefault: 0)
	}

	@objc(longForKey:)
	func ce_long(forKey key: Any) -> Int {
		ce_long(forKey: key, orUseDefault: 0)
	}

	@objc(unsignedLongForKey:)
	func ce_unsignedLong(forKey key: Any) -> UInt {
		ce_unsignedLong(forKey: key, orUseDefault: 0)
	}

	@objc(longLongForKey:)
	func ce_longLong(forKey key: Any) -> Int64 {
		ce_longLong(forKey: key, orUseDefault: 0)
	}

	@objc(unsignedLongLongForKey:)
	func ce_unsignedLongLong(forKey key: Any) -> UInt64 {
		ce_unsignedLongLong(forKey: key, orUseDefault: 0)
	}

	@objc(doubleForKey:)
	func ce_double(forKey key: Any) -> Double {
		ce_double(forKey: key, orUseDefault: 0)
	}

	@objc(stringForKey:)
	func ce_string(forKey key: Any) -> String? {
		ce_string(forKey: key, orUseDefault: nil)
	}

	@objc(dictionaryForKey:)
	func ce_dictionary(forKey key: Any) -> NSDictionary? {
		ce_dictionary(forKey: key, orUseDefault: nil)
	}

	@objc(arrayForKey:)
	func ce_array(forKey key: Any) -> NSArray? {
		ce_array(forKey: key, orUseDefault: nil)
	}

	@objc(objectForKey:orUseDefault:)
	func ce_object(forKey key: Any, orUseDefault defaultValue: Any?) -> Any? {
		dictionarySynchronized(on: self) { object(forKey: key) ?? defaultValue }
	}

	@objc(stringForKey:orUseDefault:)
	func ce_string(forKey key: Any, orUseDefault defaultValue: String?) -> String? {
		dictionarySynchronized(on: self) { object(forKey: key) as? String ?? defaultValue }
	}

	@objc(arrayForKey:orUseDefault:)
	func ce_array(forKey key: Any, orUseDefault defaultValue: NSArray?) -> NSArray? {
		dictionarySynchronized(on: self) { object(forKey: key) as? NSArray ?? defaultValue }
	}

	@objc(dictionaryForKey:orUseDefault:)
	func ce_dictionary(forKey key: Any, orUseDefault defaultValue: NSDictionary?) -> NSDictionary? {
		dictionarySynchronized(on: self) { object(forKey: key) as? NSDictionary ?? defaultValue }
	}

	@objc(boolForKey:orUseDefault:)
	func ce_bool(forKey key: Any, orUseDefault defaultValue: Bool) -> Bool {
		dictionarySynchronized(on: self) {
			dictionaryGetter(from: object(forKey: key), selectorName: "boolValue", as: Bool.self) {
				unsafeBitCast($0, to: BoolGetter.self)($1, $2)
			} ?? defaultValue
		}
	}

	@objc(integerForKey:orUseDefault:)
	func ce_integer(forKey key: Any, orUseDefault defaultValue: Int) -> Int {
		dictionarySynchronized(on: self) {
			dictionaryGetter(from: object(forKey: key), selectorName: "integerValue", as: Int.self) {
				unsafeBitCast($0, to: IntegerGetter.self)($1, $2)
			} ?? defaultValue
		}
	}

	@objc(unsignedIntegerForKey:orUseDefault:)
	func ce_unsignedInteger(forKey key: Any, orUseDefault defaultValue: UInt) -> UInt {
		dictionarySynchronized(on: self) {
			dictionaryGetter(from: object(forKey: key), selectorName: "unsignedIntegerValue", as: UInt.self) {
				unsafeBitCast($0, to: UnsignedIntegerGetter.self)($1, $2)
			} ?? defaultValue
		}
	}

	@objc(shortForKey:orUseDefault:)
	func ce_short(forKey key: Any, orUseDefault defaultValue: Int16) -> Int16 {
		dictionarySynchronized(on: self) {
			dictionaryGetter(from: object(forKey: key), selectorName: "shortValue", as: Int16.self) {
				unsafeBitCast($0, to: Int16Getter.self)($1, $2)
			} ?? defaultValue
		}
	}

	@objc(unsignedShortForKey:orUseDefault:)
	func ce_unsignedShort(forKey key: Any, orUseDefault defaultValue: UInt16) -> UInt16 {
		dictionarySynchronized(on: self) {
			dictionaryGetter(from: object(forKey: key), selectorName: "unsignedShortValue", as: UInt16.self) {
				unsafeBitCast($0, to: UInt16Getter.self)($1, $2)
			} ?? defaultValue
		}
	}

	@objc(longForKey:orUseDefault:)
	func ce_long(forKey key: Any, orUseDefault defaultValue: Int) -> Int {
		dictionarySynchronized(on: self) {
			dictionaryGetter(from: object(forKey: key), selectorName: "longValue", as: Int.self) {
				unsafeBitCast($0, to: IntegerGetter.self)($1, $2)
			} ?? defaultValue
		}
	}

	@objc(unsignedLongForKey:orUseDefault:)
	func ce_unsignedLong(forKey key: Any, orUseDefault defaultValue: UInt) -> UInt {
		dictionarySynchronized(on: self) {
			dictionaryGetter(from: object(forKey: key), selectorName: "unsignedLongValue", as: UInt.self) {
				unsafeBitCast($0, to: UnsignedIntegerGetter.self)($1, $2)
			} ?? defaultValue
		}
	}

	@objc(longLongForKey:orUseDefault:)
	func ce_longLong(forKey key: Any, orUseDefault defaultValue: Int64) -> Int64 {
		dictionarySynchronized(on: self) {
			dictionaryGetter(from: object(forKey: key), selectorName: "longLongValue", as: Int64.self) {
				unsafeBitCast($0, to: Int64Getter.self)($1, $2)
			} ?? defaultValue
		}
	}

	@objc(unsignedLongLongForKey:orUseDefault:)
	func ce_unsignedLongLong(forKey key: Any, orUseDefault defaultValue: UInt64) -> UInt64 {
		dictionarySynchronized(on: self) {
			dictionaryGetter(from: object(forKey: key), selectorName: "unsignedLongLongValue", as: UInt64.self) {
				unsafeBitCast($0, to: UInt64Getter.self)($1, $2)
			} ?? defaultValue
		}
	}

	@objc(doubleForKey:orUseDefault:)
	func ce_double(forKey key: Any, orUseDefault defaultValue: Double) -> Double {
		dictionarySynchronized(on: self) {
			dictionaryGetter(from: object(forKey: key), selectorName: "doubleValue", as: Double.self) {
				unsafeBitCast($0, to: DoubleGetter.self)($1, $2)
			} ?? defaultValue
		}
	}

	@objc(assignObjectTo:forKey:)
	func ce_assignObject(to pointer: UnsafeMutablePointer<AnyObject?>, forKey key: Any) {
		ce_assignObject(to: pointer, forKey: key, performCopy: true)
	}

	@objc(assignObjectTo:forKey:performCopy:)
	func ce_assignObject(to pointer: UnsafeMutablePointer<AnyObject?>, forKey key: Any, performCopy: Bool) {
		dictionarySynchronized(on: self) {
			guard let object = object(forKey: key) else {
				if !performCopy {
					pointer.pointee = nil
				}
				return
			}
			if !performCopy {
				pointer.pointee = object as AnyObject
			} else if let copied = dictionaryObjectGetter(from: object, selector: #selector(NSObject.copy)) {
				pointer.pointee = copied
			}
		}
	}

	@objc(assignStringTo:forKey:)
	func ce_assignString(to pointer: UnsafeMutablePointer<NSString?>, forKey key: Any) {
		guard let string = ce_string(forKey: key) else { return }
		pointer.pointee = string as NSString
	}

	@objc(assignArrayTo:forKey:)
	func ce_assignArray(to pointer: UnsafeMutablePointer<NSArray?>, forKey key: Any) {
		guard let array = ce_array(forKey: key) else { return }
		pointer.pointee = array.copy() as? NSArray
	}

	@objc(assignBoolTo:forKey:)
	func ce_assignBool(to pointer: UnsafeMutablePointer<Bool>, forKey key: Any) {
		dictionarySynchronized(on: self) {
			guard let number = object(forKey: key) as? NSNumber else { return }
			pointer.pointee = number.boolValue
		}
	}

	@objc(assignUnsignedIntegerTo:forKey:)
	func ce_assignUnsignedInteger(to pointer: UnsafeMutablePointer<UInt>, forKey key: Any) {
		dictionarySynchronized(on: self) {
			guard let number = object(forKey: key) as? NSNumber else { return }
			pointer.pointee = number.uintValue
		}
	}

	@objc(assignUnsignedShortTo:forKey:)
	func ce_assignUnsignedShort(to pointer: UnsafeMutablePointer<UInt16>, forKey key: Any) {
		dictionarySynchronized(on: self) {
			guard let number = object(forKey: key) as? NSNumber else { return }
			pointer.pointee = number.uint16Value
		}
	}

	@objc(assignDoubleTo:forKey:)
	func ce_assignDouble(to pointer: UnsafeMutablePointer<Double>, forKey key: Any) {
		dictionarySynchronized(on: self) {
			guard let number = object(forKey: key) as? NSNumber else { return }
			pointer.pointee = number.doubleValue
		}
	}

	@objc(containsKey:)
	func ce_containsKey(_ key: Any) -> Bool {
		dictionarySynchronized(on: self) { object(forKey: key) != nil }
	}

	@objc(firstKeyForObject:)
	func ce_firstKey(for object: Any) -> Any? {
		guard count > 0 else { return nil }
		return dictionarySynchronized(on: self) {
			for key in allKeys where (self.object(forKey: key) as AnyObject).isEqual(object) {
				return key
			}
			return nil
		}
	}

	@objc(keyIgnoringCase:)
	func ce_keyIgnoringCase(_ key: AnyObject) -> Any? {
		guard count > 0 else { return nil }
		return dictionarySynchronized(on: self) {
			let selector = NSSelectorFromString("isEqualIgnoringCase:")
			for candidate in allKeys {
				let receiver = candidate as AnyObject
				guard receiver.responds(to: selector),
				      let implementation = receiver.method(for: selector) else { continue }
				if unsafeBitCast(implementation, to: EqualityMethod.self)(receiver, selector, key) {
					return candidate
				}
			}
			return nil
		}
	}

	@objc var sortedDictionaryKeys: [Any] {
		ce_sortedDictionaryKeys(reversed: false)
	}

	@objc var sortedDictionaryKeysReversed: [Any] {
		ce_sortedDictionaryKeys(reversed: true)
	}

	private func ce_sortedDictionaryKeys(reversed: Bool) -> [Any] {
		guard count > 0 else { return [] }
		let keys = (allKeys as NSArray).sortedArray(using: #selector(NSString.compare(_:)))
		return reversed ? keys.reversed() : keys
	}

	@objc(dictionaryByRemovingDefaults:)
	func ce_dictionaryByRemovingDefaults(_ defaults: NSDictionary?) -> NSDictionary {
		ce_dictionaryByRemovingDefaults(defaults, allowEmptyValues: false)
	}

	@objc(dictionaryByRemovingDefaults:allowEmptyValues:)
	func ce_dictionaryByRemovingDefaults(_ defaults: NSDictionary?, allowEmptyValues: Bool) -> NSDictionary {
		guard count > 0 else { return self }
		guard defaults != nil || !allowEmptyValues else { return self }
		return dictionarySynchronized(on: self) {
			let result = NSMutableDictionary()
			for (key, value) in self {
				if dictionaryValueIsEmpty(value) {
					if !allowEmptyValues {
						continue
					}
				} else if let defaultValue = defaults?.object(forKey: key), (value as AnyObject).isEqual(defaultValue) {
					continue
				}
				result.setObject(value, forKey: key as! NSCopying)
			}
			return result.copy() as! NSDictionary
		}
	}

	@objc(dictionaryByAddingEntries:)
	func ce_dictionaryByAddingEntries(_ entries: NSDictionary) -> NSDictionary {
		guard count > 0 else { return entries.copy() as! NSDictionary }
		return dictionarySynchronized(on: self) {
			let result = mutableCopy() as! NSMutableDictionary
			result.addEntries(from: entries as! [AnyHashable: Any])
			return result.copy() as! NSDictionary
		}
	}

	@objc(formDataUsingSeparator:)
	func ce_formData(usingSeparator separator: String) -> String {
		ce_formData(usingSeparator: separator) { value in
			guard let encoded = dictionaryObjectGetter(
				from: value as NSString,
				selector: NSSelectorFromString("percentEncodedString")
			) else { return value }
			return encoded as! String
		}
	}

	@objc(formDataUsingSeparator:encodingBlock:)
	func ce_formData(usingSeparator separator: String, encodingBlock: (String) -> String) -> String {
		guard count > 0 else { return "" }
		return dictionarySynchronized(on: self) {
			compactMap { key, value -> String? in
				let stringKey: String
				switch key {
				case let key as String: stringKey = key
				case let key as NSNumber: stringKey = key.stringValue
				default: return nil
				}

				let stringValue: String
				switch value {
				case let value as String: stringValue = value
				case let value as NSNumber: stringValue = value.stringValue
				case is NSNull: stringValue = ""
				default: return nil
				}
				return "\(stringKey)=\(encodingBlock(stringValue))"
			}.joined(separator: separator)
		}
	}
}

extension NSMutableDictionary {
	@objc(setObjectWithoutOverride:forKey:)
	func ce_setObjectWithoutOverride(_ value: Any?, forKey key: NSCopying) {
		guard let value, object(forKey: key) == nil else { return }
		setObject(value, forKey: key)
	}

	@objc(maybeSetObject:forKey:)
	func ce_maybeSetObject(_ value: Any?, forKey key: NSCopying) {
		guard let value else { return }
		setObject(value, forKey: key)
	}

	@objc(setBool:forKey:)
	func ce_setBool(_ value: Bool, forKey key: NSCopying) {
		setObject(value, forKey: key)
	}

	@objc(setInteger:forKey:)
	func ce_setInteger(_ value: Int, forKey key: NSCopying) {
		setObject(value, forKey: key)
	}

	@objc(setUnsignedInteger:forKey:)
	func ce_setUnsignedInteger(_ value: UInt, forKey key: NSCopying) {
		setObject(value, forKey: key)
	}

	@objc(setShort:forKey:)
	func ce_setShort(_ value: Int16, forKey key: NSCopying) {
		setObject(value, forKey: key)
	}

	@objc(setUnsignedShort:forKey:)
	func ce_setUnsignedShort(_ value: UInt16, forKey key: NSCopying) {
		setObject(value, forKey: key)
	}

	@objc(setLong:forKey:)
	func ce_setLong(_ value: Int, forKey key: NSCopying) {
		setObject(value, forKey: key)
	}

	@objc(setUnsignedLong:forKey:)
	func ce_setUnsignedLong(_ value: UInt, forKey key: NSCopying) {
		setObject(value, forKey: key)
	}

	@objc(setLongLong:forKey:)
	func ce_setLongLong(_ value: Int64, forKey key: NSCopying) {
		setObject(value, forKey: key)
	}

	@objc(setUnsignedLongLong:forKey:)
	func ce_setUnsignedLongLong(_ value: UInt64, forKey key: NSCopying) {
		setObject(value, forKey: key)
	}

	@objc(setDouble:forKey:)
	func ce_setDouble(_ value: Double, forKey key: NSCopying) {
		setObject(value, forKey: key)
	}

	@objc(setFloat:forKey:)
	func ce_setFloat(_ value: Float, forKey key: NSCopying) {
		setObject(value, forKey: key)
	}

	@objc(performSelectorOnObjectValueAndReplace:)
	func ce_performSelectorOnObjectValueAndReplace(_ selector: Selector) {
		guard count > 0 else { return }
		dictionarySynchronized(on: self) {
			for (key, value) in copy() as! NSDictionary {
				guard let replacement = dictionaryObjectGetter(from: value, selector: selector) else {
					preconditionFailure("Selector \(NSStringFromSelector(selector)) returned nil")
				}
				setObject(replacement, forKey: key as! NSCopying)
			}
		}
	}
}
