// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// One drawing strategy for the dock badge: the standard badge label carries a
/// single total, and the tile has no custom content view.
@MainActor
struct DockIconBadgeStrategyTests {
	private func draw(count: UInt) {
		DockIcon.resetCachedCount()
		DockIcon.draw(withCount: count)
	}

	@Test("A count is shown as the standard badge label")
	func countUsesTheBadgeLabel() {
		draw(count: 5)

		#expect(NSApp.dockTile.badgeLabel == 5.formatted(.number))
		#expect(NSApp.dockTile.contentView == nil)
	}

	@Test("With nothing to report the icon carries no badge at all")
	func zeroCountClearsTheBadge() {
		draw(count: 3)
		DockIcon.draw(withCount: 0)

		#expect(NSApp.dockTile.badgeLabel == nil)
	}

	@Test("A count past the cap is shown as the cap with a plus")
	func countIsCapped() {
		#expect(DockIcon.badgeString(forCount: 9999) == 9999.formatted(.number))
		#expect(DockIcon.badgeString(forCount: 10000).hasSuffix("+"))
	}

	/// Unticking the setting used to return before clearing, leaving the
	/// badge on the dock until the next relaunch.
	@Test("Turning the preference off clears a badge already drawn")
	func disablingThePreferenceClearsTheBadge() {
		let key = SettingsKeys.Notifications.displayDockBadge
		let original = key.value
		defer { key.value = original }

		draw(count: 4)

		key.value = false
		DockIcon.updateDockIcon()

		#expect(NSApp.dockTile.badgeLabel == nil)
	}
}
