/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2020 Codeux Software, LLC
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

import Foundation
import ObjectiveC.runtime

private typealias UnsignedIntegerGetter = @convention(c) (AnyObject, Selector) -> UInt
private typealias DoubleGetter = @convention(c) (AnyObject, Selector) -> Double
private typealias EqualityMethod = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
private typealias ObjectGetter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?

private func synchronized<Result>(on object: AnyObject, _ body: () -> Result) -> Result {
	objc_sync_enter(object)
	defer { objc_sync_exit(object) }
	return body()
}

private func indices(count: Int, options: NSEnumerationOptions) -> AnySequence<Int> {
	if options.contains(.reverse) {
		return AnySequence(stride(from: count - 1, through: 0, by: -1))
	}
	return AnySequence(0 ..< count)
}

extension NSArray {
	@objc(unsignedIntegerAtIndex:)
	func ce_unsignedInteger(at index: UInt) -> UInt {
		synchronized(on: self) {
			let object = object(at: Int(index)) as AnyObject
			let selector = NSSelectorFromString("unsignedIntegerValue")
			guard object.responds(to: selector), let implementation = object.method(for: selector) else { return 0 }
			return unsafeBitCast(implementation, to: UnsignedIntegerGetter.self)(object, selector)
		}
	}

	@objc(doubleAtIndex:)
	func ce_double(at index: UInt) -> Double {
		synchronized(on: self) {
			let object = object(at: Int(index)) as AnyObject
			let selector = NSSelectorFromString("doubleValue")
			guard object.responds(to: selector), let implementation = object.method(for: selector) else { return 0 }
			return unsafeBitCast(implementation, to: DoubleGetter.self)(object, selector)
		}
	}

	@objc(containsObjectIgnoringCase:)
	func ce_containsObjectIgnoringCase(_ candidate: AnyObject) -> Bool {
		guard count > 0 else { return false }
		return synchronized(on: self) {
			let selector = NSSelectorFromString("isEqualIgnoringCase:")
			for object in self {
				let receiver = object as AnyObject
				guard receiver.responds(to: selector),
				      let implementation = receiver.method(for: selector) else { continue }
				if unsafeBitCast(implementation, to: EqualityMethod.self)(receiver, selector, candidate) {
					return true
				}
			}
			return false
		}
	}

	@objc var range: NSRange {
		NSRange(location: 0, length: count)
	}

	@objc var stringArrayControllerObjects: [NSDictionary] {
		synchronized(on: self) {
			compactMap { object in
				guard let string = object as? String else { return nil }
				return ["string": string] as NSDictionary
			}
		}
	}

	@objc(arrayByRemovingEmptyValues)
	func ce_arrayByRemovingEmptyValues() -> [Any] {
		ce_arrayByRemovingEmptyValues(true, trimming: false, uniquing: false)
	}

	@objc(arrayByRemovingEmptyValuesAndUniquing)
	func ce_arrayByRemovingEmptyValuesAndUniquing() -> [Any] {
		ce_arrayByRemovingEmptyValues(true, trimming: false, uniquing: true)
	}

	@objc(arrayByRemovingEmptyValues:trimming:uniquing:)
	func ce_arrayByRemovingEmptyValues(
		_ removeEmptyValues: Bool,
		trimming trimValues: Bool,
		uniquing uniqueValues: Bool
	) -> [Any] {
		guard count > 0 else { return self as! [Any] }
		return synchronized(on: self) {
			var result: [Any] = []
			result.reserveCapacity(count)
			for sourceValue in self {
				let value = trimValues ? Self.ce_trimmedValue(sourceValue) : sourceValue

				if removeEmptyValues, Self.ce_isEmpty(value) {
					continue
				}
				if uniqueValues, result.contains(where: { ($0 as AnyObject).isEqual(value) }) {
					continue
				}
				result.append(value)
			}
			return result
		}
	}

	@objc(objectPassingTest:)
	func ce_objectPassingTest(
		_ predicate: (Any, UInt, UnsafeMutablePointer<ObjCBool>) -> Bool
	) -> Any? {
		ce_objectPassingTest(predicate, withOptions: [])
	}

	@objc(objectPassingTest:withOptions:)
	func ce_objectPassingTest(
		_ predicate: (Any, UInt, UnsafeMutablePointer<ObjCBool>) -> Bool,
		withOptions options: NSEnumerationOptions
	) -> Any? {
		guard count > 0 else { return nil }
		return synchronized(on: self) {
			var stop = ObjCBool(false)
			for index in indices(count: count, options: options) {
				let object = object(at: index)
				if predicate(object, UInt(index), &stop) {
					return object
				}
				if stop.boolValue {
					break
				}
			}
			return nil
		}
	}

	@objc(enumerateSubarraysOfSize:usingBlock:)
	func ce_enumerateSubarrays(
		ofSize subarraySize: UInt,
		using block: (NSArray, UnsafeMutablePointer<ObjCBool>) -> Void
	) {
		ce_enumerateSubarrays(ofSize: subarraySize, using: block, withOptions: [])
	}

	@objc(enumerateSubarraysOfSize:usingBlock:withOptions:)
	func ce_enumerateSubarrays(
		ofSize subarraySize: UInt,
		using block: (NSArray, UnsafeMutablePointer<ObjCBool>) -> Void,
		withOptions options: NSEnumerationOptions
	) {
		precondition(subarraySize > 0)
		guard count > 0 else { return }

		synchronized(on: self) {
			var subarray: [Any] = []
			subarray.reserveCapacity(Int(subarraySize))
			var stop = ObjCBool(false)
			for index in indices(count: count, options: options) {
				subarray.append(object(at: index))
				if subarray.count == Int(subarraySize) {
					block(subarray as NSArray, &stop)
					subarray.removeAll(keepingCapacity: true)
					if stop.boolValue {
						return
					}
				}
			}
			if !subarray.isEmpty {
				block(subarray as NSArray, &stop)
			}
		}
	}

	@objc(arrayByApplyingBlock:)
	func ce_arrayByApplying(
		_ block: (Any, UInt, UnsafeMutablePointer<ObjCBool>) -> Any
	) -> [Any] {
		ce_arrayByApplying(block, withOptions: [])
	}

	@objc(arrayByApplyingBlock:withOptions:)
	func ce_arrayByApplying(
		_ block: (Any, UInt, UnsafeMutablePointer<ObjCBool>) -> Any,
		withOptions options: NSEnumerationOptions
	) -> [Any] {
		guard count > 0 else { return [] }
		return synchronized(on: self) {
			var result: [Any] = []
			result.reserveCapacity(count)
			var stop = ObjCBool(false)
			for index in indices(count: count, options: options) {
				result.append(block(object(at: index), UInt(index), &stop))
				if stop.boolValue {
					break
				}
			}
			return result
		}
	}

	private static func ce_isEmpty(_ value: Any) -> Bool {
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

	private static func ce_trimmedValue(_ value: Any) -> Any {
		let receiver = value as AnyObject
		let selector = NSSelectorFromString("trim")
		guard
			receiver.responds(to: selector),
			let implementation = receiver.method(for: selector),
			let result = unsafeBitCast(implementation, to: ObjectGetter.self)(receiver, selector)?.takeUnretainedValue()
		else {
			return value
		}
		return result
	}
}

extension NSMutableArray {
	@objc(addObjectWithoutDuplication:)
	func ce_addObjectWithoutDuplication(_ object: Any) {
		if !contains(object) {
			add(object)
		}
	}

	@objc(performSelectorOnObjectValueAndReplace:)
	func ce_performSelectorOnObjectValueAndReplace(_ selector: Selector) {
		guard count > 0 else { return }
		synchronized(on: self) {
			for (index, value) in (copy() as! [Any]).enumerated() {
				let receiver = value as AnyObject
				guard let implementation = receiver.method(for: selector) else {
					preconditionFailure("Object does not respond to \(NSStringFromSelector(selector))")
				}
				guard let replacement = unsafeBitCast(implementation, to: ObjectGetter.self)(receiver, selector)?
					.takeUnretainedValue()
				else {
					preconditionFailure("Selector \(NSStringFromSelector(selector)) returned nil")
				}
				replaceObject(at: index, with: replacement)
			}
		}
	}

	@objc func shuffle() {
		guard count > 1 else { return }
		synchronized(on: self) {
			for index in stride(from: count - 1, through: 1, by: -1) {
				exchangeObject(at: index, withObjectAt: Int.random(in: 0 ... index))
			}
		}
	}

	@objc(moveObjectAtIndex:toIndex:)
	func ce_moveObject(at fromIndex: UInt, to toIndex: UInt) {
		let object = object(at: Int(fromIndex))
		removeObject(at: Int(fromIndex))
		insert(object, at: Int(fromIndex < toIndex ? toIndex - 1 : toIndex))
	}
}
