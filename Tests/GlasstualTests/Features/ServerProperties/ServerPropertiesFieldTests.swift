// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@Suite("Server properties fields")
@MainActor
struct ServerPropertiesFieldTests {
	@Test(
		"Only SOCKS5 and HTTP proxies take an address",
		arguments: [
			(ConnectionProxyKind.none, false),
			(.automatic, false),
			(.socks5, true),
			(.HTTP, true),
			(.tor, false),
		]
	)
	func proxyTypesThatTakeAnAddress(type: ConnectionProxyKind, takesAddress: Bool) {
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

	/// A handle taken away from the main actor has to be on the container suite
	/// -- not on `UserDefaults.standard` -- and read back what the main actor
	/// wrote, which is what the sheet's own reads depend on.
	@Test("A detached defaults handle reads the container the main actor writes")
	func detachedHandleReadsTheContainerSuite() {
		let key = SettingsKey(
			"Tests -> Server Properties -> Flag",
			default: false,
			traits: [.unregistered, .uncatalogued]
		)
		defer { key.reset() }

		key.value = true

		let detached = GlasstualUserDefaults.suite()
		#expect(detached.suiteName == GlasstualUserDefaults.container.suiteName)
		#expect(detached[key])
	}
}
