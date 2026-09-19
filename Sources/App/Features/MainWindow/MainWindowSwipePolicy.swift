// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// When a two-finger horizontal swipe moves between conversations, and which way.
enum MainWindowSwipePolicy {
	enum Destination: Equatable {
		case previous
		case next
	}

	/** Both switches have to be on. One is the system's "Swipe between pages",
	 and the other is the application's own setting, where zero has always
	 meant off. The setting used to be a distance between two touches. The
	 distance a swipe has to cover is now the system's threshold, the same one
	 every other swipe on the Mac uses. */
	static func isEnabled(systemAllowsSwipeTracking: Bool, swipeSetting: Double) -> Bool {
		systemAllowsSwipeTracking && swipeSetting > 0
	}

	/// A swipe is tracked from the event that starts the scroll gesture, and
	/// only when that gesture leads sideways.
	static func beginsSwipe(
		phase: NSEvent.Phase,
		scrollingDeltaX: CGFloat,
		scrollingDeltaY: CGFloat,
		isEnabled: Bool
	) -> Bool {
		isEnabled && phase == .began && scrollingDeltaX != 0 && abs(scrollingDeltaX) > abs(scrollingDeltaY)
	}

	/** Where a tracked swipe lands, decided once, when the tracking completes.

	 AppKit calls the handler for every update and every animation frame, so
	 only the completing call may move the selection. A swipe carried past the
	 system's threshold completes as `.ended` at a full gesture amount. One
	 that fell short completes as `.cancelled`, back at zero. Fingers moving
	 right go back, as they do between pages, and fingers moving left go on. */
	static func destination(gestureAmount: CGFloat, phase: NSEvent.Phase, isComplete: Bool) -> Destination? {
		guard isComplete, phase == .ended, gestureAmount != 0 else { return nil }
		return gestureAmount > 0 ? .previous : .next
	}
}
