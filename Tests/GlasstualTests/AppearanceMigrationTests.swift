/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import XCTest

private final class AppearanceSpyView: NSView, AppearanceObserving {
	private(set) var applicationAppearanceChangeCount = 0
	private(set) var systemAppearanceChangeCount = 0

	func applicationAppearanceChanged() {
		applicationAppearanceChangeCount += 1
		needsDisplay = true
	}

	func systemAppearanceChanged() {
		systemAppearanceChangeCount += 1
		needsDisplay = true
	}
}

@MainActor
final class AppearanceMigrationTests: XCTestCase {
	func testPreferredGlobalTableViewFontMatchesLegacySize() {
		XCTAssertEqual(NSTableView.preferredGlobalTableViewFont().pointSize, 13, accuracy: 0.001)
	}

	func testAppearanceNotificationsPropagateToSubviews() {
		let parent = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
		let child = AppearanceSpyView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
		parent.addSubview(child)

		parent.notifyApplicationAppearanceChanged()
		parent.notifySystemAppearanceChanged()

		XCTAssertEqual(child.applicationAppearanceChangeCount, 1)
		XCTAssertEqual(child.systemAppearanceChangeCount, 1)
	}

	/// A view that does not observe appearance changes is still walked through
	/// so the views beneath it are reached.
	func testNotificationsReachViewsBeneathANonObserver() {
		let parent = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
		let passthrough = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
		let child = AppearanceSpyView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))

		parent.addSubview(passthrough)
		passthrough.addSubview(child)

		parent.notifyApplicationAppearanceChanged()

		XCTAssertEqual(child.applicationAppearanceChangeCount, 1)
	}
}
