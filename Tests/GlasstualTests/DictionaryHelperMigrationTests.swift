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

final class DictionaryHelperMigrationTests: XCTestCase {
	func testTypedAccessorsAcceptNumbersAndNumericStrings() throws {
		let dictionary: NSDictionary = ["enabled": "YES", "count": "42"]

		XCTAssertTrue(try invokeBool(dictionary, selector: "boolForKey:", key: "enabled"))
		XCTAssertEqual(try invokeInteger(dictionary, selector: "integerForKey:", key: "count"), 42)
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
		let dictionary: NSDictionary = [
			"default": "same",
			"empty": "",
			"kept": "value",
		]
		let result = try invokeObject(
			dictionary,
			selector: "dictionaryByRemovingDefaults:",
			argument: ["default": "same"] as NSDictionary
		) as! NSDictionary

		XCTAssertEqual(result, ["kept": "value"] as NSDictionary)
	}

	func testFormDataSupportsStringsNumbersAndNull() throws {
		let dictionary: NSDictionary = ["query": "hello world", "page": 2, "empty": NSNull()]
		let result = try invokeObject(
			dictionary,
			selector: "formDataUsingSeparator:",
			argument: "&" as NSString
		) as! String
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
			"boolForKey:",
			"objectForKey:orUseDefault:",
			"assignObjectTo:forKey:",
			"keyIgnoringCase:",
			"dictionaryByRemovingDefaults:allowEmptyValues:",
			"formDataUsingSeparator:encodingBlock:",
		]
		for selector in immutableSelectors {
			XCTAssertTrue(NSDictionary.instancesRespond(to: NSSelectorFromString(selector)), selector)
		}

		let mutableSelectors = [
			"maybeSetObject:forKey:",
			"setUnsignedLongLong:forKey:",
			"performSelectorOnObjectValueAndReplace:",
		]
		for selector in mutableSelectors {
			XCTAssertTrue(NSMutableDictionary.instancesRespond(to: NSSelectorFromString(selector)), selector)
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
