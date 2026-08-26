@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "OELReachabilityPrivate.h"
/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class OELReachabilityMigrationTests: XCTestCase {
	@objc
	func testFactoryCreatesNotifier() throws {
		let reachability = try XCTUnwrap(OELReachability.forInternetConnection())

		XCTAssertNotNil(reachability)
		XCTAssertFalse(reachability.isReachable)
	}

	@objc
	func testFirstPathSeedsWithoutEvent() {
		var currentlyReachable = ObjCBool(false)
		var receivedInitialPath = ObjCBool(false)
		let event: Int = OELReachability.evaluatePathChange(
			true,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		XCTAssertEqual(event, 0)
		XCTAssertTrue(currentlyReachable.boolValue)
		XCTAssertTrue(receivedInitialPath.boolValue)
	}

	@objc
	func testUnchangedPathProducesNoEvent() {
		var currentlyReachable = ObjCBool(true)
		var receivedInitialPath = ObjCBool(true)
		let event: Int = OELReachability.evaluatePathChange(
			true,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		XCTAssertEqual(event, 0)
		XCTAssertTrue(currentlyReachable.boolValue)
	}

	@objc
	func testReachabilityTransitionsEmitExpectedEvents() {
		var currentlyReachable = ObjCBool(true)
		var receivedInitialPath = ObjCBool(true)
		let becameUnreachable: Int = OELReachability.evaluatePathChange(
			false,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		XCTAssertEqual(becameUnreachable, 2)
		XCTAssertFalse(currentlyReachable.boolValue)

		let becameReachable: Int = OELReachability.evaluatePathChange(
			true,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		XCTAssertEqual(becameReachable, 1)
		XCTAssertTrue(currentlyReachable.boolValue)
	}

	@objc
	func testStartAndStopNotifierRoundTrip() throws {
		let reachability = try XCTUnwrap(OELReachability.forInternetConnection())

		XCTAssertTrue(reachability.startNotifier())

		reachability.stopNotifier()

		XCTAssertTrue(reachability.startNotifier())

		reachability.stopNotifier()
	}
}
