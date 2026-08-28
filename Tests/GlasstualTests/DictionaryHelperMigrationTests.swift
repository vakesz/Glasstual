/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import ObjectiveC.runtime
import Testing

private typealias DictionaryBoolGetter = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
private typealias DictionaryIntegerGetter = @convention(c) (AnyObject, Selector, AnyObject) -> Int
private typealias DictionaryObjectMethod = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>

@MainActor
@Suite("Dictionary and array helpers")
struct DictionaryHelperMigrationTests {
	@Test("A typed read accepts a number and the string spelling of one")
	func typedAccessorsAcceptNumbersAndNumericStrings() throws {
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

		let enabled = try invokeBool(dictionary, selector: "boolForKey:", key: "enabled")
		let integer = try invokeInteger(dictionary, selector: "integerForKey:", key: "integer")

		#expect(enabled)
		#expect(integer == 42)
		#expect(dictionary.ce_short(forKey: "short") == -12)
		#expect(dictionary.ce_unsignedShort(forKey: "unsignedShort") == 65000)
		#expect(dictionary.ce_unsignedInteger(forKey: "unsignedInteger") == 123)
		#expect(dictionary.ce_longLong(forKey: "longLong") == -9_000_000_000)
		#expect(dictionary.ce_unsignedLongLong(forKey: "unsignedLongLong") == 18_000_000_000)
		#expect(dictionary.ce_double(forKey: "double") == 4.25)
		#expect(dictionary.ce_unsignedInteger(forKey: "integer", orUseDefault: 17) == 17)
	}

	@Test("A value of the wrong type reads as the supplied default")
	func typedAccessorsUseDefaultsForWrongTypes() throws {
		let dictionary: NSDictionary = ["name": NSArray()]
		let selector = NSSelectorFromString("integerForKey:orUseDefault:")
		typealias Getter = @convention(c) (AnyObject, Selector, AnyObject, Int) -> Int
		let implementation = try #require(dictionary.method(for: selector))
		let value = unsafeBitCast(implementation, to: Getter.self)(dictionary, selector, "name" as NSString, 19)

		#expect(value == 19)
	}

	@Test("Removing defaults drops the values equal to a default and the empty ones")
	func removingDefaultsDropsEqualAndEmptyValues() throws {
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
		let result = try #require(invokeObject(
			dictionary,
			selector: "dictionaryByRemovingDefaults:",
			argument: ["default": "same"] as NSDictionary
		) as? NSDictionary)

		#expect(result == ["kept": "value"] as NSDictionary)
	}

	@Test("A case-insensitive lookup compares the values as strings")
	func caseInsensitiveCollectionLookupUsesTypedStringComparison() {
		let array: NSArray = ["GLASSTUAL", "Textual"]
		let dictionary: NSDictionary = ["Network": "Libera.Chat"]

		#expect(array.ce_containsObjectIgnoringCase("glasstual" as NSString))
		#expect(dictionary.ce_keyIgnoringCase("network" as NSString) as? String == "Network")
	}

	@Test("An array converts its elements and normalises away the empty and duplicate ones")
	func arrayValueConversionAndNormalization() {
		let values: NSArray = [NSNumber(value: UInt(42)), "4.25"]

		#expect(values.ce_unsignedInteger(at: 0) == 42)
		#expect(values.ce_double(at: 1) == 4.25)

		let unnormalized: NSArray = ["  Alpha  ", "", "Alpha", NSArray(), NSNull()]
		let normalized = unnormalized.ce_arrayByRemovingEmptyValues(true, trimming: true, uniquing: true)

		#expect(normalized as NSArray == ["Alpha"] as NSArray)
	}

	@Test("Form data percent-encodes strings and spells numbers and null out")
	func formDataSupportsStringsNumbersAndNull() throws {
		let dictionary: NSDictionary = ["query": "hello world", "page": 2, "empty": NSNull()]
		let result = try #require(invokeObject(
			dictionary,
			selector: "formDataUsingSeparator:",
			argument: "&" as NSString
		) as? String)
		let fields = Set(result.split(separator: "&").map(String.init))

		#expect(fields == ["query=hello%20world", "page=2", "empty="])
	}

	private func invokeBool(_ dictionary: NSDictionary, selector name: String, key: String) throws -> Bool {
		let selector = NSSelectorFromString(name)
		let implementation = try #require(dictionary.method(for: selector))
		return unsafeBitCast(implementation, to: DictionaryBoolGetter.self)(
			dictionary,
			selector,
			key as NSString
		)
	}

	private func invokeInteger(_ dictionary: NSDictionary, selector name: String, key: String) throws -> Int {
		let selector = NSSelectorFromString(name)
		let implementation = try #require(dictionary.method(for: selector))
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
		let implementation = try #require(dictionary.method(for: selector))
		return unsafeBitCast(implementation, to: DictionaryObjectMethod.self)(
			dictionary,
			selector,
			argument
		).takeUnretainedValue()
	}
}
