/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Log view JavaScript bridge")
struct LogViewJavaScriptTests {
	@Test("A result is described with the JavaScript name for its primitive")
	func descriptionUsesJavaScriptPrimitiveNames() {
		#expect(LogViewJavaScript.describe(true as NSNumber) == "true")
		#expect(LogViewJavaScript.describe(false as NSNumber) == "false")
		#expect(LogViewJavaScript.describe(42 as NSNumber) == "42")
		#expect(LogViewJavaScript.describe(NSNull()) == "null")
		#expect(LogViewJavaScript.describe(Date()) == "undefined")
	}

	/** The bridge no longer builds argument literals, so the body names the
	 arguments WebKit binds and carries no value of its own. */
	@Test("The function body names the arguments WebKit binds rather than their values")
	func functionBodyReferencesBoundArgumentNames() {
		#expect(
			LogViewJavaScript.functionBody("Glasstual.render", argumentCount: 3)
				== "return Glasstual.render(a0,a1,a2);"
		)
		#expect(
			LogViewJavaScript.functionBody("_Glasstual.viewFinishedLoading", argumentCount: 0)
				== "return _Glasstual.viewFinishedLoading();"
		)
	}

	@Test("Anything that is not an identifier path is refused a function body")
	func functionBodyRejectsAnythingThatIsNotAnIdentifierPath() {
		#expect(LogViewJavaScript.functionBody("", argumentCount: 0) == nil)
		#expect(LogViewJavaScript.functionBody("alert(1); //", argumentCount: 0) == nil)
		#expect(LogViewJavaScript.functionBody("Glasstual.", argumentCount: 0) == nil)
		#expect(LogViewJavaScript.functionBody("1Glasstual", argumentCount: 0) == nil)
		#expect(LogViewJavaScript.functionBody("Glasstual['render']", argumentCount: 0) == nil)
	}

	@Test("Arguments are reduced to the values WebKit knows how to convert")
	func argumentsAreReducedToValuesWebKitConverts() throws {
		let url = try #require(URL(string: "https://example.com/a"))
		let named = LogViewJavaScript.namedArguments(["quote\"", true, [1, NSNull()], url, Date()])

		#expect(named["a0"]?.string == "quote\"")
		#expect(named["a1"]?.boolean == true)
		#expect(named["a2"]?.array?.count == 2)
		#expect(named["a3"]?.string == "https://example.com/a")
		#expect(named["a4"] == .null)
	}

	/** Callers build their payloads as `JavaScriptValue` and hand them to an
	 `[Any]` bridge, so every one of them is bridged a second time on the way
	 through. A value that is already bridged has to survive that. */
	@Test("A payload that is already bridged survives a second pass")
	func alreadyBridgedValuesSurviveASecondPass() {
		let payload: [String: JavaScriptValue] = [
			"html": .string("<span>hi</span>"),
			"lineNumber": .string("1234"),
			"contentSize": .object(["width": .double(64), "height": .double(48)]),
			"tags": .array([.string("a"), .integer(2)]),
		]

		let named = LogViewJavaScript.namedArguments([payload])
		let bridged = named["a0"]?.object

		#expect(bridged?["html"]?.string == "<span>hi</span>")
		#expect(bridged?["lineNumber"]?.string == "1234")
		#expect(bridged?["contentSize"]?.object?["width"]?.integer == 64)
		#expect(bridged?["tags"]?.array?.count == 2)
		#expect(bridged?.values.contains(.null) == false)

		#expect(LogViewJavaScript.namedArguments([JavaScriptValue.integer(7)])["a0"] == .integer(7))
	}

	@Test("A nested dictionary key that is not a string is dropped")
	func nestedDictionaryKeysThatAreNotStringsAreDropped() {
		let dictionary = JavaScriptValue.object(bridging: ["key": ["nested": 1], 2: "dropped"])

		#expect(dictionary.count == 1)
		#expect(dictionary["key"]?.object?["nested"]?.integer == 1)
	}
}
