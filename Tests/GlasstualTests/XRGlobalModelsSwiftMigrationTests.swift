/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import XCTest

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

@MainActor
final class XRGlobalModelsSwiftMigrationTests: XCTestCase {
	func testObjectEmptinessPreservesDynamicLengthAndCountSemantics() {
		XCTAssertTrue(isObjectEmpty(nil))
		XCTAssertTrue(isObjectEmpty(NSNull()))
		XCTAssertTrue(isObjectEmpty(GlobalModelsLengthFixture(length: 0)))
		XCTAssertFalse(isObjectEmpty(GlobalModelsLengthFixture(length: 1)))
		XCTAssertTrue(isObjectEmpty(NSArray()))
		XCTAssertFalse(isObjectEmpty(["value"] as NSArray))
		XCTAssertFalse(isObjectEmpty(NSNumber(value: 0)))
	}

	func testScheduledBlockRetainsCreateResumeAndCancelLifecycle() {
		let expectation = expectation(description: "Scheduled block executed")
		let queue = DispatchQueue(label: "com.vakesz.glasstual.tests.global-models")
		let source = scheduleBlock(on: queue, after: 0.01) {
			expectation.fulfill()
		}

		source.resume()
		wait(for: [expectation], timeout: 1)
		source.cancel()
		XCTAssertTrue(source.isCancelled)
	}

	func testInstanceMethodExchangePreservesRuntimeBehavior() {
		let fixture = GlobalModelsSwizzleFixture()
		XCTAssertEqual(fixture.originalValue(), "original")

		XCTAssertTrue(exchangeInstanceMethods(
			on: GlobalModelsSwizzleFixture.self,
			original: #selector(GlobalModelsSwizzleFixture.originalValue),
			replacement: #selector(GlobalModelsSwizzleFixture.replacementValue)
		))
		defer {
			exchangeInstanceMethods(
				on: GlobalModelsSwizzleFixture.self,
				original: #selector(GlobalModelsSwizzleFixture.originalValue),
				replacement: #selector(GlobalModelsSwizzleFixture.replacementValue)
			)
		}

		XCTAssertEqual(fixture.originalValue(), "replacement")
		XCTAssertEqual(fixture.replacementValue(), "original")
	}
}
