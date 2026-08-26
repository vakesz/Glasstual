/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import ObjectiveC.runtime
import XCTest

final class LogControllerMigrationTests: XCTestCase {
	func testObjectiveCRuntimeNamesRemainStable() {
		XCTAssertEqual(NSStringFromClass(LogController.self), "TVCLogController")
		XCTAssertEqual(
			NSStringFromClass(LogControllerPrintOperationContext.self),
			"TVCLogControllerPrintOperationContext"
		)
	}

	func testPublicAndPrivateObjectiveCSelectorsRemainAvailable() {
		let selectors = [
			"initWithClient:inWindow:",
			"initWithChannel:inWindow:",
			"jumpToLine:",
			"jumpToLine:completionHandler:",
			"print:",
			"print:completionBlock:",
			"renderLogLineAtLineNumber:numberOfLinesBefore:numberOfLinesAfter:completionBlock:",
			"renderLogLinesAfterLineNumber:beforeLineNumber:maximumNumberOfLines:completionBlock:",
			"processInlineMediaAtAddress:withUniqueIdentifier:atLineNumber:index:",
			"logViewWebViewReceivedDropWithFile:",
		]

		for selectorName in selectors {
			XCTAssertNotNil(
				class_getInstanceMethod(LogController.self, NSSelectorFromString(selectorName)),
				"Missing Objective-C selector \(selectorName)"
			)
		}
	}

	func testFinishedLoadingNotificationRetainsHistoricName() {
		XCTAssertEqual(
			Notification.Name.logControllerViewFinishedLoading.rawValue,
			"TVCLogControllerViewFinishedLoadingNotification"
		)
	}
}
