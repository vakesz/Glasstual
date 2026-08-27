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

private let mutableArrayMutationLock = NSRecursiveLock()

private func arraySnapshot(_ array: NSArray) -> [Any] {
	let snapshot = {
		guard let snapshot = array.copy() as? NSArray else {
			return array.map(\.self)
		}
		return snapshot.map(\.self)
	}
	if array is NSMutableArray {
		return mutableArrayMutationLock.withLock(snapshot)
	}
	return snapshot()
}

private func arrayObject(at index: Int, in array: NSArray) -> Any {
	if array is NSMutableArray {
		return mutableArrayMutationLock.withLock { array.object(at: index) }
	}
	return array.object(at: index)
}

private func arrayCount(_ array: NSArray) -> Int {
	if array is NSMutableArray {
		return mutableArrayMutationLock.withLock { array.count }
	}
	return array.count
}

private func indices(count: Int, options: NSEnumerationOptions) -> AnySequence<Int> {
	if options.contains(.reverse) {
		return AnySequence(stride(from: count - 1, through: 0, by: -1))
	}
	return AnySequence(0 ..< count)
}

public extension NSArray {
	@objc(unsignedIntegerAtIndex:)
	func ce_unsignedInteger(at index: UInt) -> UInt {
		(arrayObject(at: Int(index), in: self) as? NSNumber)?.uintValue ?? 0
	}

	@objc(doubleAtIndex:)
	func ce_double(at index: UInt) -> Double {
		switch arrayObject(at: Int(index), in: self) {
		case let number as NSNumber:
			number.doubleValue
		case let string as NSString:
			string.doubleValue
		default:
			0
		}
	}

	@objc(containsObjectIgnoringCase:)
	func ce_containsObjectIgnoringCase(_ candidate: AnyObject) -> Bool {
		arraySnapshot(self).contains { value in
			guard let object = value as? NSObject else { return false }
			return object.textual_isEqualIgnoringCase(candidate)
		}
	}

	@objc var range: NSRange {
		NSRange(location: 0, length: arrayCount(self))
	}

	@objc var stringArrayControllerObjects: [NSDictionary] {
		arraySnapshot(self).compactMap { object in
			guard let string = object as? String else { return nil }
			return ["string": string] as NSDictionary
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
		let values = arraySnapshot(self)
		guard !values.isEmpty else { return [] }

		var result: [Any] = []
		result.reserveCapacity(values.count)
		for sourceValue in values {
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
		let values = arraySnapshot(self)
		guard !values.isEmpty else { return nil }

		var stop = ObjCBool(false)
		for index in indices(count: values.count, options: options) {
			let object = values[index]
			if predicate(object, UInt(index), &stop) {
				return object
			}
			if stop.boolValue {
				break
			}
		}
		return nil
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
		let values = arraySnapshot(self)
		guard !values.isEmpty else { return }

		var subarray: [Any] = []
		subarray.reserveCapacity(Int(subarraySize))
		var stop = ObjCBool(false)
		for index in indices(count: values.count, options: options) {
			subarray.append(values[index])
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
		let values = arraySnapshot(self)
		guard !values.isEmpty else { return [] }

		var result: [Any] = []
		result.reserveCapacity(values.count)
		var stop = ObjCBool(false)
		for index in indices(count: values.count, options: options) {
			result.append(block(values[index], UInt(index), &stop))
			if stop.boolValue {
				break
			}
		}
		return result
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
		if let orderedSet = value as? NSOrderedSet {
			return orderedSet.count == 0
		}
		if let indexSet = value as? NSIndexSet {
			return indexSet.count == 0
		}
		if let attributedString = value as? NSAttributedString {
			return attributedString.length == 0
		}
		if let hashTable = value as? NSHashTable<AnyObject> {
			return hashTable.count == 0
		}
		if let mapTable = value as? NSMapTable<AnyObject, AnyObject> {
			return mapTable.count == 0
		}
		if let pointerArray = value as? NSPointerArray {
			return pointerArray.count == 0
		}
		if let collection = value as? any Collection {
			return collection.isEmpty
		}
		return false
	}

	private static func ce_trimmedValue(_ value: Any) -> Any {
		guard let string = value as? NSString else { return value }
		return string.ceTrim
	}
}

public extension NSMutableArray {
	@objc(addObjectWithoutDuplication:)
	func ce_addObjectWithoutDuplication(_ object: Any) {
		mutableArrayMutationLock.withLock {
			if !contains(object) {
				add(object)
			}
		}
	}

	@objc(performSelectorOnObjectValueAndReplace:)
	func ce_performSelectorOnObjectValueAndReplace(_ selector: Selector) {
		mutableArrayMutationLock.withLock {
			guard count > 0 else { return }
			let values = map(\.self)
			for (index, value) in values.enumerated() {
				guard let receiver = value as? NSObject, receiver.responds(to: selector) else {
					preconditionFailure("Object does not respond to \(NSStringFromSelector(selector))")
				}
				guard let replacement = receiver.perform(selector)?.takeUnretainedValue() else {
					preconditionFailure("Selector \(NSStringFromSelector(selector)) returned nil")
				}
				replaceObject(at: index, with: replacement)
			}
		}
	}

	@objc func shuffle() {
		mutableArrayMutationLock.withLock {
			guard count > 1 else { return }
			for index in stride(from: count - 1, through: 1, by: -1) {
				exchangeObject(at: index, withObjectAt: Int.random(in: 0 ... index))
			}
		}
	}

	@objc(moveObjectAtIndex:toIndex:)
	func ce_moveObject(at fromIndex: UInt, to toIndex: UInt) {
		mutableArrayMutationLock.withLock {
			let object = object(at: Int(fromIndex))
			removeObject(at: Int(fromIndex))
			insert(object, at: Int(fromIndex < toIndex ? toIndex - 1 : toIndex))
		}
	}
}
