/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
@testable import Glasstual
import os
import XCTest

@MainActor
final class LoggingBridgeMigrationTests: XCTestCase {
	func testLegacyStackTraceFormatterPreservesLineBoundaries() {
		XCTAssertEqual(
			_LogToConsoleFormattedStackTrace(["first frame", "second frame"]),
			"first frame\nsecond frame"
		)
	}

	func testLegacyDefaultSubsystemRoundTripsThroughSwiftStorage() {
		let subsystem = OSLog(subsystem: "com.vakesz.glasstual.tests", category: "LoggingBridge")
		_LogToConsoleSetDefaultSubsystem(subsystem)
		defer { _LogToConsoleSetDefaultSubsystem(nil) }

		XCTAssertTrue(_LogToConsoleDefaultSubsystem() === subsystem)
	}
}
