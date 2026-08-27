/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import XCTest

private final class AppearanceSpyView: NSView {
	private(set) var applicationAppearanceChangeCount = 0
	private(set) var systemAppearanceChangeCount = 0

	override var needsDisplayWhenApplicationAppearanceChanges: Bool {
		true
	}

	override var needsDisplayWhenSystemAppearanceChanges: Bool {
		true
	}

	override func applicationAppearanceChanged() {
		applicationAppearanceChangeCount += 1
		super.applicationAppearanceChanged()
	}

	override func systemAppearanceChanged() {
		systemAppearanceChangeCount += 1
		super.systemAppearanceChanged()
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
}
