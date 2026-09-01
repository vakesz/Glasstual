/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Testing

@MainActor
@Suite("Cocoa extensions user defaults helpers")
struct CocoaExtensionsUserDefaultsTests {
	@Test("The numeric helpers read back the width they were written with")
	func userDefaultsNumericHelpersPreserveValues() throws {
		let suiteName = "CocoaExtensionsUserDefaultsTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		defaults.setUnsignedInteger(42, forKey: "unsignedInteger")
		defaults.setShort(-12, forKey: "short")
		defaults.setUnsignedShort(65000, forKey: "unsignedShort")
		defaults.setLongLong(-9_000_000_000, forKey: "longLong")
		defaults.setUnsignedLongLong(18_000_000_000, forKey: "unsignedLongLong")

		#expect(defaults.unsignedInteger(forKey: "unsignedInteger") == 42)
		#expect(defaults.short(forKey: "short") == -12)
		#expect(defaults.unsignedShort(forKey: "unsignedShort") == 65000)
		#expect(defaults.longLong(forKey: "longLong") == -9_000_000_000)
		#expect(defaults.unsignedLongLong(forKey: "unsignedLongLong") == 18_000_000_000)
	}

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
