@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class OELReachabilityMigrationTests: XCTestCase {
	@objc
	func testFactoryCreatesNotifier() {
		let reachability = Reachability.reachabilityForInternetConnection()

		XCTAssertNotNil(reachability)
		XCTAssertFalse(reachability.reachable)
	}

	@objc
	func testFirstPathSeedsWithoutEvent() {
		var currentlyReachable = false
		var receivedInitialPath = false
		let event = Reachability.evaluatePathChange(
			reachable: true,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		XCTAssertEqual(event, .none)
		XCTAssertTrue(currentlyReachable)
		XCTAssertTrue(receivedInitialPath)
	}

	@objc
	func testUnchangedPathProducesNoEvent() {
		var currentlyReachable = true
		var receivedInitialPath = true
		let event = Reachability.evaluatePathChange(
			reachable: true,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		XCTAssertEqual(event, .none)
		XCTAssertTrue(currentlyReachable)
	}

	@objc
	func testReachabilityTransitionsEmitExpectedEvents() {
		var currentlyReachable = true
		var receivedInitialPath = true
		let becameUnreachable = Reachability.evaluatePathChange(
			reachable: false,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		XCTAssertEqual(becameUnreachable, .becameUnreachable)
		XCTAssertFalse(currentlyReachable)

		let becameReachable = Reachability.evaluatePathChange(
			reachable: true,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		XCTAssertEqual(becameReachable, .becameReachable)
		XCTAssertTrue(currentlyReachable)
	}

	@objc
	func testStartAndStopNotifierRoundTrip() {
		let reachability = Reachability.reachabilityForInternetConnection()

		XCTAssertTrue(reachability.startNotifier())

		reachability.stopNotifier()

		XCTAssertTrue(reachability.startNotifier())

		reachability.stopNotifier()
	}
}
