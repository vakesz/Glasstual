/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import XCTest

@MainActor
final class CocoaExtensionsUtilityMigrationTests: XCTestCase {
	func testUserDefaultsNumericHelpersPreserveValuesAndSelectors() throws {
		let suiteName = "CocoaExtensionsUtilityMigrationTests.\(UUID().uuidString)"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		defaults.setUnsignedInteger(42, forKey: "unsignedInteger")
		defaults.setShort(-12, forKey: "short")
		defaults.setUnsignedShort(65000, forKey: "unsignedShort")
		defaults.setLongLong(-9_000_000_000, forKey: "longLong")
		defaults.setUnsignedLongLong(18_000_000_000, forKey: "unsignedLongLong")

		XCTAssertEqual(defaults.unsignedInteger(forKey: "unsignedInteger"), 42)
		XCTAssertEqual(defaults.short(forKey: "short"), -12)
		XCTAssertEqual(defaults.unsignedShort(forKey: "unsignedShort"), 65000)
		XCTAssertEqual(defaults.longLong(forKey: "longLong"), -9_000_000_000)
		XCTAssertEqual(defaults.unsignedLongLong(forKey: "unsignedLongLong"), 18_000_000_000)
		XCTAssertTrue(defaults.responds(to: NSSelectorFromString("setUnsignedLongLong:forKey:")))
	}

	func testUserDefaultsColorHelperUsesSecureArchiving() throws {
		let suiteName = "CocoaExtensionsUtilityMigrationTests.\(UUID().uuidString)"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let color = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)

		defaults.setColor(color, forKey: "color")

		let restored = try XCTUnwrap(defaults.color(forKey: "color"))
		XCTAssertEqual(restored.usingColorSpace(.deviceRGB), color.usingColorSpace(.deviceRGB))
		defaults.setColor(nil, forKey: "color")
		XCTAssertNil(defaults.object(forKey: "color"))
	}
}
