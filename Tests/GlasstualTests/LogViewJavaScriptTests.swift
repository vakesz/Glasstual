/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

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

		#expect(named["a0"] as? String == "quote\"")
		#expect(named["a1"] as? Bool == true)
		#expect((named["a2"] as? [Any])?.count == 2)
		#expect(named["a3"] as? String == "https://example.com/a")
		#expect(named["a4"] is NSNull)
	}

	@Test("A nested dictionary key that is not a string is dropped")
	func nestedDictionaryKeysThatAreNotStringsAreDropped() {
		let dictionary = LogViewJavaScript.sanitize(["key": ["nested": 1], 2: "dropped"] as [AnyHashable: Any])

		#expect(dictionary.count == 1)
		#expect((dictionary["key"] as? [String: Any])?["nested"] as? Int == 1)
	}
}
