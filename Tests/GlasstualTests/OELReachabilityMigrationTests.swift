@testable import Glasstual
import XCTest

/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@MainActor
class OELReachabilityMigrationTests: XCTestCase {
	func testFactoryCreatesNotifier() {
		let reachability = Reachability.reachabilityForInternetConnection()

		XCTAssertNotNil(reachability)
		XCTAssertFalse(reachability.reachable)
	}

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

	func testStartAndStopNotifierRoundTrip() {
		let reachability = Reachability.reachabilityForInternetConnection()

		XCTAssertTrue(reachability.startNotifier())

		reachability.stopNotifier()

		XCTAssertTrue(reachability.startNotifier())

		reachability.stopNotifier()
	}
}
