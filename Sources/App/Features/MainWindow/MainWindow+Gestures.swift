/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

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
			swipePreference: Preferences.Input.swipeMinimumLength.value
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

	func preferencesChanged() {
		if Preferences.Notifications.displayDockBadge.value {
			DockIcon.resetCachedCount(); DockIcon.updateDockIcon()
		} else {
			DockIcon.drawWithoutCount()
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
		let defaultSize = MainWindowAppearance.defaultWindowSize
		var value = frame
		value.size = NSSize(
			width: max(defaultSize.width, minimumSize.width),
			height: max(defaultSize.height, minimumSize.height)
		)
		return value
	}
}

/// When a two-finger horizontal swipe moves between conversations, and which way.
enum MainWindowSwipePolicy {
	enum Destination: Equatable {
		case previous
		case next
	}

	/** Both switches have to be on. One is the system's "Swipe between pages",
	 and the other is the application's own preference, where zero has always
	 meant off. The preference used to be a distance between two touches. The
	 distance a swipe has to cover is now the system's threshold, the same one
	 every other swipe on the Mac uses. */
	static func isEnabled(systemAllowsSwipeTracking: Bool, swipePreference: Double) -> Bool {
		systemAllowsSwipeTracking && swipePreference > 0
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
