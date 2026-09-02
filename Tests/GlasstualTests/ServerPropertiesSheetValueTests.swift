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
	private func usesAddress(forTag tag: Int) -> Bool {
		ServerPropertiesModel.proxyTypeUsesAddress(ServerPropertiesModel.proxyType(forTag: tag))
	}

	/// proxyTypeChanged fell back to .none and saveConfig to .automatic, so an
	/// unrecognised tag disabled the proxy fields while quietly enabling the
	/// system SOCKS proxy in the saved configuration.
	@Test(
		"A proxy tag maps to one type, with one fallback",
		arguments: [
			(0, UInt(0)),
			(1, UInt(1)),
			(5, UInt(5)),
			(6, UInt(6)),
			(8, UInt(8)),
			(-1, UInt(0)),
			(4, UInt(0)),
			(99, UInt(0)),
		]
	)
	func proxyTypeForTag(tag: Int, expected: UInt) {
		#expect(ServerPropertiesModel.proxyType(forTag: tag).rawValue == expected)
	}

	@Test("Only SOCKS5 and HTTP proxies take an address")
	func proxyTypesThatTakeAnAddress() {
		#expect(usesAddress(forTag: 5))
		#expect(usesAddress(forTag: 6))
		for tag in [-1, 0, 1, 8, 99] {
			#expect(usesAddress(forTag: tag) == false)
		}
	}

	/// The encoding pop-up carries the numeric encoding in `tag`, so an advanced
	/// encoding survives a round trip through a menu that does not list it.
	@Test("An encoding tag round-trips, and an unset tag falls back")
	func encodingForTag() {
		let advanced = String.Encoding.japaneseEUC.rawValue
		#expect(ServerPropertiesModel.encoding(forTag: Int(advanced), default: .utf8) == advanced)
		#expect(ServerPropertiesModel.encoding(forTag: 0, default: .utf8) == String.Encoding.utf8.rawValue)
		#expect(
			ServerPropertiesModel.encoding(forTag: -1, default: .isoLatin1) == String.Encoding.isoLatin1.rawValue
		)
	}

	/// dictionaryValue(for:) omits a nil but persists an empty string, so the
	/// optional fields all have to normalise the same way.
	@Test("Empty text normalises to nil")
	func emptyTextIsNil() {
		#expect(ServerPropertiesModel.nilIfEmpty("") == nil)
		#expect(ServerPropertiesModel.nilIfEmpty("value") == "value")
	}

	@Test("The advanced encodings preference is read from the shared container")
	func advancedEncodingsKeyLivesInTheContainer() {
		let key = Preferences.Internals.includeAdvancedEncodings.name
		let container = TextualUserDefaults.container
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
		let detached = TextualUserDefaults.suite()
		#expect(detached.suiteName == container.suiteName)
		#expect(detached.bool(forKey: key))
	}
}
