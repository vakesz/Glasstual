/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
final class LogScriptEventSinkMigrationTests: XCTestCase {
	@MainActor
	func testLineIdentifiersKeepEstablishedNormalization() {
		XCTAssertEqual(TVCLogScriptEventSink.standardizeLineNumber("line-42"), "42")
		XCTAssertEqual(TVCLogScriptEventSink.standardizeLineNumber("42"), "42")
		XCTAssertEqual(
			TVCLogScriptEventSink.standardizeLineNumbers(["line-a", "b", "line-c"]),
			["a", "b", "c"]
		)
	}

	@MainActor
	func testCommonPayloadConversionPreservesNullAndHTMLSemantics() {
		XCTAssertNil(TVCLogScriptEventSink.objectValueToCommon(NSNull()))
		XCTAssertEqual(TVCLogScriptEventSink.objectValueToCommon("Tom &amp; Jerry") as? String, "Tom & Jerry")
		XCTAssertEqual(TVCLogScriptEventSink.objectValueToCommon(NSNumber(value: 7)) as? NSNumber, 7)
	}
}
