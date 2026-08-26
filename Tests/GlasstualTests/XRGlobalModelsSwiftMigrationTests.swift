/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import XCTest

private typealias ObjectIsEmptyFunction = @convention(c) (AnyObject?) -> Bool

@objcMembers
private final class GlobalModelsLengthFixture: NSObject {
	dynamic let length: UInt

	init(length: UInt) {
		self.length = length
	}
}

@objcMembers
private final class GlobalModelsSwizzleFixture: NSObject {
	dynamic func originalValue() -> NSString {
		"original"
	}

	dynamic func replacementValue() -> NSString {
		"replacement"
	}
}

final class XRGlobalModelsSwiftMigrationTests: XCTestCase {
	func testObjectEmptinessPreservesDynamicLengthAndCountSemantics() throws {
		let implementation = try XCTUnwrap(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "NSObjectIsEmpty"))
		let objectIsEmpty = unsafeBitCast(implementation, to: ObjectIsEmptyFunction.self)

		XCTAssertTrue(objectIsEmpty(nil))
		XCTAssertTrue(objectIsEmpty(NSNull()))
		XCTAssertTrue(objectIsEmpty(GlobalModelsLengthFixture(length: 0)))
		XCTAssertFalse(objectIsEmpty(GlobalModelsLengthFixture(length: 1)))
		XCTAssertTrue(objectIsEmpty(NSArray()))
		XCTAssertFalse(objectIsEmpty(["value"] as NSArray))
		XCTAssertFalse(objectIsEmpty(NSNumber(value: 0)))
	}

	func testScheduledBlockRetainsLegacyCreateResumeAndCancelLifecycle() throws {
		let expectation = expectation(description: "Scheduled block executed")
		let queue = DispatchQueue(label: "com.vakesz.glasstual.tests.global-models")
		let source = try XCTUnwrap(XRScheduleBlockOnQueue(queue, {
			expectation.fulfill()
		}, 0.01, false))

		XRResumeScheduledBlock(source)
		wait(for: [expectation], timeout: 1)
		XRCancelScheduledBlock(source)
		XCTAssertTrue(source.isCancelled)
	}

	func testInstanceMethodExchangePreservesLegacyRuntimeBehavior() {
		let fixture = GlobalModelsSwizzleFixture()
		XCTAssertEqual(fixture.originalValue(), "original")

		XRExchangeInstanceMethod(
			NSStringFromClass(GlobalModelsSwizzleFixture.self),
			"originalValue",
			"replacementValue"
		)
		defer {
			XRExchangeInstanceMethod(
				NSStringFromClass(GlobalModelsSwizzleFixture.self),
				"originalValue",
				"replacementValue"
			)
		}

		XCTAssertEqual(fixture.originalValue(), "replacement")
		XCTAssertEqual(fixture.replacementValue(), "original")
	}
}
