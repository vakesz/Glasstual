/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

final class LogViewJavaScriptTests: XCTestCase {
	func testDescriptionUsesJavaScriptPrimitiveNames() {
		XCTAssertEqual(LogViewJavaScript.describe(true as NSNumber), "true")
		XCTAssertEqual(LogViewJavaScript.describe(false as NSNumber), "false")
		XCTAssertEqual(LogViewJavaScript.describe(42 as NSNumber), "42")
		XCTAssertEqual(LogViewJavaScript.describe(NSNull()), "null")
		XCTAssertEqual(LogViewJavaScript.describe(Date()), "undefined")
	}

	/** The bridge no longer builds argument literals, so the body names the
	 arguments WebKit binds and carries no value of its own. */
	func testFunctionBodyReferencesBoundArgumentNames() {
		XCTAssertEqual(
			LogViewJavaScript.functionBody("Glasstual.render", argumentCount: 3),
			"return Glasstual.render(a0,a1,a2);"
		)
		XCTAssertEqual(
			LogViewJavaScript.functionBody("_Glasstual.viewFinishedLoading", argumentCount: 0),
			"return _Glasstual.viewFinishedLoading();"
		)
	}

	func testFunctionBodyRejectsAnythingThatIsNotAnIdentifierPath() {
		XCTAssertNil(LogViewJavaScript.functionBody("", argumentCount: 0))
		XCTAssertNil(LogViewJavaScript.functionBody("alert(1); //", argumentCount: 0))
		XCTAssertNil(LogViewJavaScript.functionBody("Glasstual.", argumentCount: 0))
		XCTAssertNil(LogViewJavaScript.functionBody("1Glasstual", argumentCount: 0))
		XCTAssertNil(LogViewJavaScript.functionBody("Glasstual['render']", argumentCount: 0))
	}

	func testArgumentsAreReducedToValuesWebKitConverts() throws {
		let url = try XCTUnwrap(URL(string: "https://example.com/a"))
		let named = LogViewJavaScript.namedArguments(["quote\"", true, [1, NSNull()], url, Date()])

		XCTAssertEqual(named["a0"] as? String, "quote\"")
		XCTAssertEqual(named["a1"] as? Bool, true)
		XCTAssertEqual((named["a2"] as? [Any])?.count, 2)
		XCTAssertEqual(named["a3"] as? String, "https://example.com/a")
		XCTAssertTrue(named["a4"] is NSNull)
	}

	func testNestedDictionaryKeysThatAreNotStringsAreDropped() {
		let dictionary = LogViewJavaScript.sanitize(["key": ["nested": 1], 2: "dropped"] as [AnyHashable: Any])

		XCTAssertEqual(dictionary.count, 1)
		XCTAssertEqual((dictionary["key"] as? [String: Any])?["nested"] as? Int, 1)
	}

	@MainActor
	func testObjectiveCFacadeRetainsPublicSelectors() throws {
		let facadeClass = try XCTUnwrap(NSClassFromString("TVCLogView") as? NSObject.Type)
		XCTAssertTrue(facadeClass.responds(to: NSSelectorFromString("descriptionOfJavaScriptResult:")))
		XCTAssertTrue(facadeClass.responds(to: NSSelectorFromString("emptyCaches")))
	}
}
