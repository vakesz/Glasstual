/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import XCTest

private final class ImmutablePortableDictionaryFixture: PortablePropertyDict {
	private(set) var observedCopyState = false
	private(set) var value = 0

	override var mutableClass: PortablePropertyObject {
		unsafeBitCast(MutablePortableDictionaryFixture.self, to: PortablePropertyObject.self)
	}

	override func populateDefaultsPreflight() {
		observedCopyState = initializedAsCopy

		if !initializedAsCopy {
			value = 7
		}
	}

	override func populateDictionaryValues(_ dictionary: [String: Any]) {
		value = dictionary["value"] as? Int ?? value
	}

	override func dictionaryValue(for target: PortablePropertyDictTarget) -> [String: Any] {
		[
			"target": target.rawValue,
			"value": value,
		]
	}
}

private final class MutablePortableDictionaryFixture: PortablePropertyDict {
	private(set) var observedCopyState = false
	private(set) var value = 0

	override class var isMutable: Bool {
		true
	}

	override var immutableClass: PortablePropertyObject {
		unsafeBitCast(ImmutablePortableDictionaryFixture.self, to: PortablePropertyObject.self)
	}

	override func populateDefaultsPreflight() {
		observedCopyState = initializedAsCopy

		if !initializedAsCopy {
			value = 7
		}
	}

	override func populateDictionaryValues(_ dictionary: [String: Any]) {
		value = dictionary["value"] as? Int ?? value
	}

	override func dictionaryValue(for target: PortablePropertyDictTarget) -> [String: Any] {
		[
			"target": target.rawValue,
			"value": value,
		]
	}
}

final class PortablePropertyMigrationTests: XCTestCase {
	func testImmutableCopyRetainsReferenceIdentity() {
		let object = ImmutablePortableDictionaryFixture(dictionary: ["value": 42])

		XCTAssertTrue(object.copy() as AnyObject === object)
		XCTAssertFalse(object.initializedAsCopy)
	}

	func testMutableCopyUsesMutableTargetAndMarksCopyBeforeHooks() throws {
		let object = ImmutablePortableDictionaryFixture(dictionary: ["value": 42])
		let copy = try XCTUnwrap(object.mutableCopy() as? MutablePortableDictionaryFixture)

		XCTAssertEqual(copy.value, 42)
		XCTAssertTrue(copy.initializedAsCopy)
		XCTAssertTrue(copy.observedCopyState)
		XCTAssertEqual(copy.dictionaryValue["target"] as? UInt, PortablePropertyDictTarget.default.rawValue)
	}

	func testUniqueCopyCreatesDistinctEqualObjectWithMatchingHash() throws {
		let object = ImmutablePortableDictionaryFixture(dictionary: ["value": 42])
		let copy = try XCTUnwrap(object.uniqueCopy() as? ImmutablePortableDictionaryFixture)

		XCTAssertFalse(copy === object)
		XCTAssertEqual(copy, object)
		XCTAssertEqual(copy.hash, object.hash)
		XCTAssertTrue(copy.observedCopyState)
	}
}
