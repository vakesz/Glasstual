/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Foundation
import Testing

@MainActor
@Suite("Cocoa extensions user defaults helpers")
struct CocoaExtensionsUserDefaultsTests {
	@Test("A colour round-trips through secure archiving and clears on nil")
	func userDefaultsColorHelperUsesSecureArchiving() throws {
		let suiteName = "CocoaExtensionsUserDefaultsTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let color = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)

		defaults.setColor(color, forKey: "color")

		let restored = try #require(defaults.color(forKey: "color"))

		#expect(restored.usingColorSpace(.deviceRGB) == color.usingColorSpace(.deviceRGB))

		defaults.setColor(nil, forKey: "color")

		#expect(defaults.object(forKey: "color") == nil)
	}
}
