// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import SwiftUI

// MARK: - Gestures and window utilities

extension MainWindow {
	override func swipe(with event: NSEvent) {
		let x = event.deltaX * (event.isDirectionInvertedFromDevice ? -1 : 1)
		if x > 0 {
			selectNextWindow(nil)
		} else if x < 0 {
			selectPreviousWindow(nil)
		}
	}

	/** Two-finger swipes between conversations, read from scroll events.

	 The window used to read them from `beginGesture` and `endGesture`, which
	 AppKit no longer sends, so the gesture did nothing. A trackpad swipe
	 arrives as a scroll gesture. The transcript's scroll view passes a
	 horizontal one up the responder chain because this window asks for it
	 below. The window then tracks it with the system's fluid swipe, which
	 respects the "Swipe between pages" setting and the application's own
	 switch. */
	override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
		axis == .horizontal && MainWindowSwipePolicy.isEnabled(
			systemAllowsSwipeTracking: NSEvent.isSwipeTrackingFromScrollEventsEnabled,
			swipeSetting: SettingsKeys.Input.swipeMinimumLength.value
		)
	}

	override func scrollWheel(with event: NSEvent) {
		guard MainWindowSwipePolicy.beginsSwipe(
			phase: event.phase,
			scrollingDeltaX: event.scrollingDeltaX,
			scrollingDeltaY: event.scrollingDeltaY,
			isEnabled: wantsScrollEventsForSwipeTracking(on: .horizontal)
		) else {
			super.scrollWheel(with: event)
			return
		}

		event.trackSwipeEvent(
			options: [.lockDirection, .clampGestureAmount],
			dampenAmountThresholdMin: -1,
			max: 1
		) { [weak self] gestureAmount, phase, isComplete, _ in
			switch MainWindowSwipePolicy.destination(gestureAmount: gestureAmount, phase: phase, isComplete: isComplete) {
			case .previous:
				self?.selectPreviousWindow(nil)
			case .next:
				self?.selectNextWindow(nil)
			case nil:
				break
			}
		}
	}

	override func endEditing(for object: Any?) {
		if makeFirstResponder(self) == false {
			super.endEditing(for: object)
		}
	}

	override var canBecomeKey: Bool {
		true
	}

	override var canBecomeMain: Bool {
		true
	}

	/** The frame Reset Window gives back, where the window already is.

	 The appearance's default size is never allowed below the window's own
	 minimum. The bundled default is 474 points tall against a 500-point
	 minimum content height, so Reset Window left the window smaller than a
	 resize could ever make it. */
	var defaultWindowFrame: NSRect {
		let minimumSize = frameRect(forContentRect: NSRect(origin: .zero, size: contentMinSize)).size
		let defaultSize = MainWindowConstants.defaultWindowSize
		var value = frame
		value.size = NSSize(
			width: max(defaultSize.width, minimumSize.width),
			height: max(defaultSize.height, minimumSize.height)
		)
		return value
	}
}
