/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

final class LogViewJavaScriptTests: XCTestCase {
	func testEscapingPreservesJavaScriptStringBoundaries() {
		XCTAssertEqual(
			LogViewJavaScript.escape("a\\b\"c\r\nd"),
			"a\\\\b\\\"c\\r\\nd"
		)
	}

	func testDescriptionUsesJavaScriptPrimitiveNames() {
		XCTAssertEqual(LogViewJavaScript.describe(true as NSNumber), "true")
		XCTAssertEqual(LogViewJavaScript.describe(false as NSNumber), "false")
		XCTAssertEqual(LogViewJavaScript.describe(42 as NSNumber), "42")
		XCTAssertEqual(LogViewJavaScript.describe(NSNull()), "null")
		XCTAssertEqual(LogViewJavaScript.describe(Date()), "undefined")
	}

	func testFunctionCallCompilesNestedArguments() throws {
		let url = try XCTUnwrap(URL(string: "https://example.com/a"))
		let script = LogViewJavaScript.functionCall(
			"Glasstual.render",
			arguments: ["quote\"", true, [1, NSNull()], url]
		)

		XCTAssertEqual(
			script,
			"Glasstual.render(\"quote\\\"\",true,[1,null],\"https://example.com/a\");\n"
		)
	}

	@MainActor
	func testObjectiveCFacadeRetainsPublicSelectors() throws {
		let facadeClass = try XCTUnwrap(NSClassFromString("TVCLogView") as? NSObject.Type)
		XCTAssertTrue(facadeClass.responds(to: NSSelectorFromString("escapeJavaScriptString:")))
		XCTAssertTrue(facadeClass.responds(to: NSSelectorFromString("descriptionOfJavaScriptResult:")))
		XCTAssertTrue(facadeClass.responds(to: NSSelectorFromString("emptyCaches")))
	}
}
