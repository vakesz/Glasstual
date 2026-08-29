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

private func dictionaryEntries(_ dictionary: NSDictionary) -> [(key: Any, value: Any)] {
	/* A caller may hand this a dictionary another thread is mutating, so the
	 entries are read out of a snapshot rather than the dictionary itself. */
	guard let snapshot = dictionary.copy() as? NSDictionary else {
		return Array(dictionary)
	}

	return Array(snapshot)
}

private func dictionaryObject(forKey key: Any, in dictionary: NSDictionary) -> Any? {
	dictionary.object(forKey: key)
}

private enum DictionaryValueConversion {
	static func bool(from value: Any?) -> Bool? {
		switch value {
		case let number as NSNumber:
			number.boolValue
		case let string as NSString:
			string.boolValue
		default:
			nil
		}
	}

	static func integer(from value: Any?) -> Int? {
		switch value {
		case let number as NSNumber:
			number.intValue
		case let string as NSString:
			string.integerValue
		default:
			nil
		}
	}

	static func unsignedInteger(from value: Any?) -> UInt? {
		(value as? NSNumber)?.uintValue
	}

	static func short(from value: Any?) -> Int16? {
		(value as? NSNumber)?.int16Value
	}

	static func unsignedShort(from value: Any?) -> UInt16? {
		(value as? NSNumber)?.uint16Value
	}

	static func long(from value: Any?) -> Int? {
		(value as? NSNumber)?.intValue
	}

	static func unsignedLong(from value: Any?) -> UInt? {
		(value as? NSNumber)?.uintValue
	}

	static func longLong(from value: Any?) -> Int64? {
		switch value {
		case let number as NSNumber:
			number.int64Value
		case let string as NSString:
			string.longLongValue
		default:
			nil
		}
	}

	static func unsignedLongLong(from value: Any?) -> UInt64? {
		(value as? NSNumber)?.uint64Value
	}

	static func double(from value: Any?) -> Double? {
		switch value {
		case let number as NSNumber:
			number.doubleValue
		case let string as NSString:
			string.doubleValue
		default:
			nil
		}
	}
}

public extension NSDictionary {
	func ce_bool(forKey key: Any) -> Bool {
		ce_bool(forKey: key, orUseDefault: false)
	}

	func ce_integer(forKey key: Any) -> Int {
		ce_integer(forKey: key, orUseDefault: 0)
	}

	func ce_unsignedInteger(forKey key: Any) -> UInt {
		ce_unsignedInteger(forKey: key, orUseDefault: 0)
	}

	func ce_short(forKey key: Any) -> Int16 {
		ce_short(forKey: key, orUseDefault: 0)
	}

	func ce_unsignedShort(forKey key: Any) -> UInt16 {
		ce_unsignedShort(forKey: key, orUseDefault: 0)
	}

	func ce_long(forKey key: Any) -> Int {
		ce_long(forKey: key, orUseDefault: 0)
	}

	func ce_unsignedLong(forKey key: Any) -> UInt {
		ce_unsignedLong(forKey: key, orUseDefault: 0)
	}

	func ce_longLong(forKey key: Any) -> Int64 {
		ce_longLong(forKey: key, orUseDefault: 0)
	}

	func ce_unsignedLongLong(forKey key: Any) -> UInt64 {
		ce_unsignedLongLong(forKey: key, orUseDefault: 0)
	}

	func ce_double(forKey key: Any) -> Double {
		ce_double(forKey: key, orUseDefault: 0)
	}

	func ce_string(forKey key: Any) -> String? {
		ce_string(forKey: key, orUseDefault: nil)
	}

	func ce_dictionary(forKey key: Any) -> NSDictionary? {
		ce_dictionary(forKey: key, orUseDefault: nil)
	}

	func ce_array(forKey key: Any) -> NSArray? {
		ce_array(forKey: key, orUseDefault: nil)
	}

	func ce_object(forKey key: Any, orUseDefault defaultValue: Any?) -> Any? {
		dictionaryObject(forKey: key, in: self) ?? defaultValue
	}

	func ce_string(forKey key: Any, orUseDefault defaultValue: String?) -> String? {
		dictionaryObject(forKey: key, in: self) as? String ?? defaultValue
	}

	func ce_array(forKey key: Any, orUseDefault defaultValue: NSArray?) -> NSArray? {
		dictionaryObject(forKey: key, in: self) as? NSArray ?? defaultValue
	}

	func ce_dictionary(forKey key: Any, orUseDefault defaultValue: NSDictionary?) -> NSDictionary? {
		dictionaryObject(forKey: key, in: self) as? NSDictionary ?? defaultValue
	}

	func ce_bool(forKey key: Any, orUseDefault defaultValue: Bool) -> Bool {
		DictionaryValueConversion.bool(from: dictionaryObject(forKey: key, in: self)) ?? defaultValue
	}

	func ce_integer(forKey key: Any, orUseDefault defaultValue: Int) -> Int {
		DictionaryValueConversion.integer(from: dictionaryObject(forKey: key, in: self)) ?? defaultValue
	}

	func ce_unsignedInteger(forKey key: Any, orUseDefault defaultValue: UInt) -> UInt {
		DictionaryValueConversion.unsignedInteger(from: dictionaryObject(forKey: key, in: self)) ?? defaultValue
	}

	func ce_short(forKey key: Any, orUseDefault defaultValue: Int16) -> Int16 {
		DictionaryValueConversion.short(from: dictionaryObject(forKey: key, in: self)) ?? defaultValue
	}

	func ce_unsignedShort(forKey key: Any, orUseDefault defaultValue: UInt16) -> UInt16 {
		DictionaryValueConversion.unsignedShort(from: dictionaryObject(forKey: key, in: self)) ?? defaultValue
	}

	func ce_long(forKey key: Any, orUseDefault defaultValue: Int) -> Int {
		DictionaryValueConversion.long(from: dictionaryObject(forKey: key, in: self)) ?? defaultValue
	}

	func ce_unsignedLong(forKey key: Any, orUseDefault defaultValue: UInt) -> UInt {
		DictionaryValueConversion.unsignedLong(from: dictionaryObject(forKey: key, in: self)) ?? defaultValue
	}

	func ce_longLong(forKey key: Any, orUseDefault defaultValue: Int64) -> Int64 {
		DictionaryValueConversion.longLong(from: dictionaryObject(forKey: key, in: self)) ?? defaultValue
	}

	func ce_unsignedLongLong(forKey key: Any, orUseDefault defaultValue: UInt64) -> UInt64 {
		DictionaryValueConversion.unsignedLongLong(from: dictionaryObject(forKey: key, in: self)) ?? defaultValue
	}

	func ce_double(forKey key: Any, orUseDefault defaultValue: Double) -> Double {
		DictionaryValueConversion.double(from: dictionaryObject(forKey: key, in: self)) ?? defaultValue
	}

	func ce_firstKey(for object: Any) -> Any? {
		for (key, value) in dictionaryEntries(self) where (value as AnyObject).isEqual(object) {
			return key
		}
		return nil
	}

	func ce_keyIgnoringCase(_ key: AnyObject) -> Any? {
		for (candidate, _) in dictionaryEntries(self) {
			guard let receiver = candidate as? NSObject else { continue }
			if receiver.textual_isEqualIgnoringCase(key) {
				return candidate
			}
		}
		return nil
	}

	var sortedDictionaryKeys: [Any] {
		ce_sortedDictionaryKeys(reversed: false)
	}

	var sortedDictionaryKeysReversed: [Any] {
		ce_sortedDictionaryKeys(reversed: true)
	}

	private func ce_sortedDictionaryKeys(reversed: Bool) -> [Any] {
		let keys = dictionaryEntries(self).map(\.key).sorted { left, right in
			guard let left = left as? NSString, let right = right as? NSString else {
				preconditionFailure("sortedDictionaryKeys requires string keys")
			}
			return left.compare(right as String) == .orderedAscending
		}
		return reversed ? keys.reversed() : keys
	}

	func ce_dictionaryByRemovingDefaults(_ defaults: NSDictionary?) -> NSDictionary {
		ce_dictionaryByRemovingDefaults(defaults, allowEmptyValues: false)
	}

	func ce_dictionaryByRemovingDefaults(_ defaults: NSDictionary?, allowEmptyValues: Bool) -> NSDictionary {
		let entries = dictionaryEntries(self)
		guard !entries.isEmpty else { return self }
		guard defaults != nil || !allowEmptyValues else { return self }

		let result = NSMutableDictionary(capacity: entries.count)
		for (key, value) in entries {
			if isEmptyValue(value) {
				if !allowEmptyValues {
					continue
				}
			} else if let defaults,
			          let defaultValue = dictionaryObject(forKey: key, in: defaults),
			          (value as AnyObject).isEqual(defaultValue)
			{
				continue
			}
			guard let copiedKey = key as? NSCopying else {
				preconditionFailure("NSDictionary key does not conform to NSCopying")
			}
			result.setObject(value, forKey: copiedKey)
		}
		return result.copy() as? NSDictionary ?? result
	}

	func ce_dictionaryByAddingEntries(_ entries: NSDictionary) -> NSDictionary {
		let currentEntries = dictionaryEntries(self)
		guard !currentEntries.isEmpty else { return entries.copy() as? NSDictionary ?? entries }

		let addedEntries = dictionaryEntries(entries)
		let result = NSMutableDictionary(capacity: currentEntries.count + addedEntries.count)
		for (key, value) in currentEntries + addedEntries {
			guard let copiedKey = key as? NSCopying else {
				preconditionFailure("NSDictionary key does not conform to NSCopying")
			}
			result.setObject(value, forKey: copiedKey)
		}
		return result.copy() as? NSDictionary ?? result
	}

	func ce_formData(usingSeparator separator: String) -> String {
		ce_formData(usingSeparator: separator) { value in
			value.percentEncoded ?? value
		}
	}

	func ce_formData(usingSeparator separator: String, encodingBlock: (String) -> String) -> String {
		dictionaryEntries(self).compactMap { key, value -> String? in
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
