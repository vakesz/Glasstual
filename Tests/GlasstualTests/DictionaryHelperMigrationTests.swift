/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import ObjectiveC.runtime
import XCTest

private typealias DictionaryBoolGetter = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
private typealias DictionaryIntegerGetter = @convention(c) (AnyObject, Selector, AnyObject) -> Int
private typealias DictionaryObjectMethod = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>
private typealias MutableDictionaryBoolSetter = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
private typealias MutableDictionarySelectorMethod = @convention(c) (AnyObject, Selector, Selector) -> Void

@MainActor
final class DictionaryHelperMigrationTests: XCTestCase {
	func testTypedAccessorsAcceptNumbersAndNumericStrings() throws {
		let dictionary: NSDictionary = [
			"double": "4.25",
			"enabled": "YES",
			"integer": "42",
			"longLong": "-9000000000",
			"short": NSNumber(value: Int16(-12)),
			"unsignedInteger": NSNumber(value: UInt(123)),
			"unsignedLongLong": NSNumber(value: UInt64(18_000_000_000)),
			"unsignedShort": NSNumber(value: UInt16(65000)),
		]

		XCTAssertTrue(try invokeBool(dictionary, selector: "boolForKey:", key: "enabled"))
		XCTAssertEqual(try invokeInteger(dictionary, selector: "integerForKey:", key: "integer"), 42)
		XCTAssertEqual(dictionary.ce_short(forKey: "short"), -12)
		XCTAssertEqual(dictionary.ce_unsignedShort(forKey: "unsignedShort"), 65000)
		XCTAssertEqual(dictionary.ce_unsignedInteger(forKey: "unsignedInteger"), 123)
		XCTAssertEqual(dictionary.ce_longLong(forKey: "longLong"), -9_000_000_000)
		XCTAssertEqual(dictionary.ce_unsignedLongLong(forKey: "unsignedLongLong"), 18_000_000_000)
		XCTAssertEqual(dictionary.ce_double(forKey: "double"), 4.25)
		XCTAssertEqual(dictionary.ce_unsignedInteger(forKey: "integer", orUseDefault: 17), 17)
	}

	func testTypedAccessorsUseDefaultsForWrongTypes() throws {
		let dictionary: NSDictionary = ["name": NSArray()]
		let selector = NSSelectorFromString("integerForKey:orUseDefault:")
		typealias Getter = @convention(c) (AnyObject, Selector, AnyObject, Int) -> Int
		let implementation = try XCTUnwrap(dictionary.method(for: selector))

		XCTAssertEqual(
			unsafeBitCast(implementation, to: Getter.self)(dictionary, selector, "name" as NSString, 19),
			19
		)
	}

	func testRemovingDefaultsDropsEqualAndEmptyValues() throws {
		let hashTable = NSHashTable<AnyObject>(options: .strongMemory)
		let mapTable = NSMapTable<AnyObject, AnyObject>.strongToStrongObjects()
		let dictionary: NSDictionary = [
			"attributedString": NSAttributedString(string: ""),
			"default": "same",
			"empty": "",
			"hashTable": hashTable,
			"indexSet": NSIndexSet(),
			"kept": "value",
			"mapTable": mapTable,
			"orderedSet": NSOrderedSet(),
			"pointerArray": NSPointerArray.strongObjects(),
		]
		let result = try XCTUnwrap(invokeObject(
			dictionary,
			selector: "dictionaryByRemovingDefaults:",
			argument: ["default": "same"] as NSDictionary
		) as? NSDictionary)

		XCTAssertEqual(result, ["kept": "value"] as NSDictionary)
	}

	func testCaseInsensitiveCollectionLookupUsesTypedStringComparison() {
		let array: NSArray = ["GLASSTUAL", "Textual"]
		let dictionary: NSDictionary = ["Network": "Libera.Chat"]

		XCTAssertTrue(array.ce_containsObjectIgnoringCase("glasstual" as NSString))
		XCTAssertEqual(dictionary.ce_keyIgnoringCase("network" as NSString) as? String, "Network")
	}

	func testArrayValueConversionAndNormalization() {
		let values: NSArray = [NSNumber(value: UInt(42)), "4.25"]
		XCTAssertEqual(values.ce_unsignedInteger(at: 0), 42)
		XCTAssertEqual(values.ce_double(at: 1), 4.25)

		let unnormalized: NSArray = ["  Alpha  ", "", "Alpha", NSArray(), NSNull()]
		let normalized = unnormalized.ce_arrayByRemovingEmptyValues(true, trimming: true, uniquing: true)
		XCTAssertEqual(normalized as NSArray, ["Alpha"] as NSArray)
	}

	func testMutableArrayReplacesObjectValuesUsingSelector() {
		let array: NSMutableArray = ["MIXED"]
		array.ce_performSelectorOnObjectValueAndReplace(NSSelectorFromString("lowercaseString"))

		XCTAssertEqual(array, ["mixed"] as NSArray)
	}

	func testFormDataSupportsStringsNumbersAndNull() throws {
		let dictionary: NSDictionary = ["query": "hello world", "page": 2, "empty": NSNull()]
		let result = try XCTUnwrap(invokeObject(
			dictionary,
			selector: "formDataUsingSeparator:",
			argument: "&" as NSString
		) as? String)
		let fields = Set(result.split(separator: "&").map(String.init))

		XCTAssertEqual(fields, ["query=hello%20world", "page=2", "empty="])
	}

	func testMutableNumericSetterRetainsObjectiveCABI() throws {
		let dictionary = NSMutableDictionary()
		let setSelector = NSSelectorFromString("setBool:forKey:")
		let setImplementation = try XCTUnwrap(dictionary.method(for: setSelector))
		unsafeBitCast(setImplementation, to: MutableDictionaryBoolSetter.self)(
			dictionary,
			setSelector,
			true,
			"enabled" as NSString
		)
		XCTAssertEqual(dictionary["enabled"] as? Bool, true)
	}

	func testMutableDictionaryReplacesObjectValuesUsingSelector() throws {
		let dictionary: NSMutableDictionary = ["word": "MIXED"]
		let replaceSelector = NSSelectorFromString("performSelectorOnObjectValueAndReplace:")
		let replaceImplementation = try XCTUnwrap(dictionary.method(for: replaceSelector))
		unsafeBitCast(replaceImplementation, to: MutableDictionarySelectorMethod.self)(
			dictionary,
			replaceSelector,
			NSSelectorFromString("lowercaseString")
		)

		XCTAssertEqual(dictionary["word"] as? String, "mixed")
	}

	func testAllLegacySelectorsRemainAvailable() {
		let immutableSelectors = [
			"arrayForKey:",
			"arrayForKey:orUseDefault:",
			"assignArrayTo:forKey:",
			"assignBoolTo:forKey:",
			"assignDoubleTo:forKey:",
			"assignObjectTo:forKey:",
			"assignObjectTo:forKey:performCopy:",
			"assignStringTo:forKey:",
			"assignUnsignedIntegerTo:forKey:",
			"assignUnsignedShortTo:forKey:",
			"boolForKey:",
			"boolForKey:orUseDefault:",
			"containsKey:",
			"dictionaryByAddingEntries:",
			"dictionaryByRemovingDefaults:",
			"dictionaryByRemovingDefaults:allowEmptyValues:",
			"dictionaryForKey:",
			"dictionaryForKey:orUseDefault:",
			"doubleForKey:",
			"doubleForKey:orUseDefault:",
			"firstKeyForObject:",
			"formDataUsingSeparator:",
			"formDataUsingSeparator:encodingBlock:",
			"integerForKey:",
			"integerForKey:orUseDefault:",
			"keyIgnoringCase:",
			"longForKey:",
			"longForKey:orUseDefault:",
			"longLongForKey:",
			"longLongForKey:orUseDefault:",
			"objectForKey:orUseDefault:",
			"shortForKey:",
			"shortForKey:orUseDefault:",
			"sortedDictionaryKeys",
			"sortedDictionaryKeysReversed",
			"stringForKey:",
			"stringForKey:orUseDefault:",
			"unsignedIntegerForKey:",
			"unsignedIntegerForKey:orUseDefault:",
			"unsignedLongForKey:",
			"unsignedLongForKey:orUseDefault:",
			"unsignedLongLongForKey:",
			"unsignedLongLongForKey:orUseDefault:",
			"unsignedShortForKey:",
			"unsignedShortForKey:orUseDefault:",
		]
		for selector in immutableSelectors {
			XCTAssertTrue(NSDictionary.instancesRespond(to: NSSelectorFromString(selector)), selector)
		}

		let mutableSelectors = [
			"maybeSetObject:forKey:",
			"performSelectorOnObjectValueAndReplace:",
			"setBool:forKey:",
			"setDouble:forKey:",
			"setFloat:forKey:",
			"setInteger:forKey:",
			"setLong:forKey:",
			"setLongLong:forKey:",
			"setObjectWithoutOverride:forKey:",
			"setShort:forKey:",
			"setUnsignedInteger:forKey:",
			"setUnsignedLong:forKey:",
			"setUnsignedLongLong:forKey:",
			"setUnsignedShort:forKey:",
		]
		for selector in mutableSelectors {
			XCTAssertTrue(NSMutableDictionary.instancesRespond(to: NSSelectorFromString(selector)), selector)
		}
	}

	func testAllLegacyArraySelectorsRemainAvailable() {
		let immutableSelectors = [
			"arrayByApplyingBlock:",
			"arrayByApplyingBlock:withOptions:",
			"arrayByRemovingEmptyValues",
			"arrayByRemovingEmptyValues:trimming:uniquing:",
			"arrayByRemovingEmptyValuesAndUniquing",
			"containsObjectIgnoringCase:",
			"doubleAtIndex:",
			"enumerateSubarraysOfSize:usingBlock:",
			"enumerateSubarraysOfSize:usingBlock:withOptions:",
			"objectPassingTest:",
			"objectPassingTest:withOptions:",
			"stringArrayControllerObjects",
			"unsignedIntegerAtIndex:",
		]
		for selector in immutableSelectors {
			XCTAssertTrue(NSArray.instancesRespond(to: NSSelectorFromString(selector)), selector)
		}

		let mutableSelectors = [
			"addObjectWithoutDuplication:",
			"moveObjectAtIndex:toIndex:",
			"performSelectorOnObjectValueAndReplace:",
		]
		for selector in mutableSelectors {
			XCTAssertTrue(NSMutableArray.instancesRespond(to: NSSelectorFromString(selector)), selector)
		}
	}

	private func invokeBool(_ dictionary: NSDictionary, selector name: String, key: String) throws -> Bool {
		let selector = NSSelectorFromString(name)
		let implementation = try XCTUnwrap(dictionary.method(for: selector))
		return unsafeBitCast(implementation, to: DictionaryBoolGetter.self)(
			dictionary,
			selector,
			key as NSString
		)
	}

	private func invokeInteger(_ dictionary: NSDictionary, selector name: String, key: String) throws -> Int {
		let selector = NSSelectorFromString(name)
		let implementation = try XCTUnwrap(dictionary.method(for: selector))
		return unsafeBitCast(implementation, to: DictionaryIntegerGetter.self)(
			dictionary,
			selector,
			key as NSString
		)
	}

	private func invokeObject(
		_ dictionary: NSDictionary,
		selector name: String,
		argument: AnyObject
	) throws -> AnyObject {
		let selector = NSSelectorFromString(name)
		let implementation = try XCTUnwrap(dictionary.method(for: selector))
		return unsafeBitCast(implementation, to: DictionaryObjectMethod.self)(
			dictionary,
			selector,
			argument
		).takeUnretainedValue()
	}
}
