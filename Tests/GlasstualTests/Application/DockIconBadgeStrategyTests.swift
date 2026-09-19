// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

/// One drawing strategy for the dock badge: the badge view draws both counts,
/// and the system badge label is never used. Falling back to the label whenever
/// the highlight count was zero made the icon change shape depending on whether
/// anyone had said your name.
@MainActor
struct DockIconBadgeStrategyTests {
	private func draw(highlights: UInt, messages: UInt) {
		DockIcon.resetCachedCount()
		DockIcon.draw(withHighlightCount: highlights, messageCount: messages)
	}

	@Test("A message count with no highlights is drawn by the badge view")
	func messagesAloneUseTheBadgeView() {
		draw(highlights: 0, messages: 5)

		let dockTile = NSApp.dockTile

		#expect(dockTile.contentView is DockIconBadgeHostingView)
		#expect(dockTile.badgeLabel == nil)
		#expect((dockTile.contentView as? DockIconBadgeHostingView)?.rootView.messageCount == 5)
	}

	@Test("Highlights and messages share the one badge view")
	func highlightsAndMessagesShareTheView() {
		draw(highlights: 2, messages: 5)

		let badgeView = NSApp.dockTile.contentView as? DockIconBadgeHostingView

		#expect(badgeView?.rootView.highlightCount == 2)
		#expect(badgeView?.rootView.messageCount == 5)
		#expect(NSApp.dockTile.badgeLabel == nil)
	}

	@Test("With nothing to report the icon carries no badge at all")
	func zeroCountsClearTheTile() {
		draw(highlights: 1, messages: 1)
		draw(highlights: 0, messages: 0)

		#expect(NSApp.dockTile.contentView == nil)
		#expect(NSApp.dockTile.badgeLabel == nil)
	}

	/// Unticking the setting used to return before clearing, leaving the
	/// badge on the dock until the next relaunch.
	@Test("Turning the preference off clears a badge already drawn")
	func disablingThePreferenceClearsTheTile() {
		let key = SettingsKeys.Notifications.displayDockBadge
		let original = key.value
		defer { key.value = original }

		draw(highlights: 1, messages: 1)

		key.value = false
		DockIcon.updateDockIcon()

		#expect(NSApp.dockTile.contentView == nil)
		#expect(NSApp.dockTile.badgeLabel == nil)
	}
}
