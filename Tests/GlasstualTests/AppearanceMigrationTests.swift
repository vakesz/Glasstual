/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

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
@Suite("Appearance change propagation")
struct AppearanceMigrationTests {
	@Test("The preferred table view font keeps the legacy 13 point size")
	func preferredGlobalTableViewFontMatchesLegacySize() {
		#expect(abs(NSTableView.preferredGlobalTableViewFont().pointSize - 13) < 0.001)
	}

	@Test("Both appearance notifications reach an observing subview exactly once")
	func appearanceNotificationsPropagateToSubviews() {
		let parent = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
		let child = AppearanceSpyView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
		parent.addSubview(child)

		parent.notifyApplicationAppearanceChanged()
		parent.notifySystemAppearanceChanged()

		#expect(child.applicationAppearanceChangeCount == 1)
		#expect(child.systemAppearanceChangeCount == 1)
	}

	/// A view that does not observe appearance changes is still walked through
	/// so the views beneath it are reached.
	@Test("A non-observing view does not stop the walk to the views beneath it")
	func notificationsReachViewsBeneathANonObserver() {
		let parent = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
		let passthrough = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
		let child = AppearanceSpyView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))

		parent.addSubview(passthrough)
		passthrough.addSubview(child)

		parent.notifyApplicationAppearanceChanged()

		#expect(child.applicationAppearanceChangeCount == 1)
	}
}
