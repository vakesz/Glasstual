/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@Suite("Server properties sheet values")
@MainActor
struct ServerPropertiesSheetValueTests {
	@Test(
		"Only SOCKS5 and HTTP proxies take an address",
		arguments: [
			(ConnectionProxyType.none, false),
			(.automatic, false),
			(.socks5, true),
			(.HTTP, true),
			(.tor, false),
		]
	)
	func proxyTypesThatTakeAnAddress(type: ConnectionProxyType, takesAddress: Bool) {
		#expect(ServerPropertiesModel.proxyTypeUsesAddress(type) == takesAddress)
	}

	/// dictionaryValue(for:) omits a nil but persists an empty string, so the
	/// optional fields all have to normalise the same way.
	@Test("Empty text normalises to nil")
	func emptyTextIsNil() {
		#expect(ServerPropertiesModel.nilIfEmpty("") == nil)
		#expect(ServerPropertiesModel.nilIfEmpty("value") == "value")
	}

	/** A keyword typed in Regular Expression mode has to compile.

	 The renderer builds the expression with `try?`, so a pattern that does not
	 compile stopped highlighting and said nothing; the sheet only ever checked
	 that the field was not empty. */
	@Test("An unusable pattern is rejected only where patterns are what is matched")
	func regularExpressionKeywordsAreValidated() {
		#expect(HighlightKeywordPattern.isValid("^alice[0-9]+$"))
		#expect(HighlightKeywordPattern.isValid("alice(") == false)
		#expect(HighlightKeywordPattern.isValid("[unclosed") == false)

		#expect(
			HighlightKeywordPattern.validationError(for: "alice(", usesRegularExpression: true)
				== ApplicationStrings.invalidRegularExpression
		)
		#expect(HighlightKeywordPattern.validationError(for: "alice(", usesRegularExpression: false) == nil)
		#expect(HighlightKeywordPattern.validationError(for: "^alice$", usesRegularExpression: true) == nil)
	}

	@Test("The advanced encodings preference is read from the shared container")
	func advancedEncodingsKeyLivesInTheContainer() {
		let key = Preferences.Internals.includeAdvancedEncodings.name
		let container = GlasstualUserDefaults.container
		let original = container.object(forKey: key)
		defer {
			if let original {
				container.set(original, forKey: key)
			} else {
				container.removeObject(forKey: key)
			}
		}

		container.set(true, forKey: key)
		#expect(container.bool(forKey: key))
		// A handle taken away from the main actor has to be on this suite -- not
		// on UserDefaults.standard -- and read the same value back.
		let detached = GlasstualUserDefaults.suite()
		#expect(detached.suiteName == container.suiteName)
		#expect(detached.bool(forKey: key))
	}
}
