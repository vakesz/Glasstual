/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
final class LogControllerTests: XCTestCase {
	func testFinishedLoadingNotificationRetainsHistoricName() {
		XCTAssertEqual(
			Notification.Name.logControllerViewFinishedLoading.rawValue,
			"TVCLogControllerViewFinishedLoadingNotification"
		)
	}
}
