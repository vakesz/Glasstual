// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@Suite("Main window")
@MainActor
struct MainWindowTests {
	/// The window without `configure()`, which starts the application. The key
	/// handlers are registered by hand, the way configuring registers them.
	private func makeWindow() -> MainWindow {
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		let inputBar = window.inputContentView!
		inputBar.frame = NSRect(x: 0, y: 0, width: 400, height: 40)
		window.contentView?.addSubview(inputBar)
		window.registerKeyHandlers()
		return window
	}

	private static func keyDown(keyCode: UInt16, characters: String) -> NSEvent? {
		NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: characters,
			charactersIgnoringModifiers: characters,
			isARepeat: false,
			keyCode: keyCode
		)
	}

	/** Escape from the toolbar's search field or the find bar left full screen
	 before the field could clear or close itself. */
	@Test("Escape outside the message field is left to the view that has the keyboard")
	func escapeOutsideTheInputBarIsDeclined() throws {
		let window = makeWindow()
		let searchField = NSSearchField(frame: NSRect(x: 0, y: 100, width: 200, height: 24))
		window.contentView?.addSubview(searchField)
		#expect(window.makeFirstResponder(searchField))

		let escape = try #require(Self.keyDown(keyCode: KeyCode.escape.rawValue, characters: "\u{1B}"))

		#expect(window.performedCustomKeyboardEvent(escape) == false)
	}

	/** With "Tab does nothing", the window swallowed Tab and the keyboard could
	 not leave the message field. The window now declines the key, and the
	 field moves the keyboard to the next view instead of typing a tab. */
	@Test("A Tab the window declines moves the keyboard on instead of typing a tab")
	func declinedTabMovesTheKeyboardOn() {
		let window = makeWindow()
		let nextField = NSTextField(frame: NSRect(x: 0, y: 200, width: 200, height: 24))
		window.contentView?.addSubview(nextField)
		window.inputTextField.nextKeyView = nextField
		#expect(window.makeFirstResponder(window.inputTextField))

		window.inputTextField.doCommand(by: #selector(NSResponder.insertTab(_:)))

		#expect(window.inputTextField.string.isEmpty)
		#expect(window.inputBarHoldsKeyboardFocus == false)
	}

	/** The overlay only turned the conversation transparent. VoiceOver still
	 read the views under it, and Tab still reached the message field. */
	@Test("The loading overlay hides the message field and takes the keyboard from it")
	func overlayHidesTheInputBar() {
		let window = makeWindow()
		#expect(window.makeFirstResponder(window.inputTextField))

		window.setConversationObscured(true)

		#expect(window.inputContentView.isHidden)
		#expect(window.inputBarHoldsKeyboardFocus == false)
		#expect(window.columnModel.isConversationObscured)

		window.setConversationObscured(false)

		#expect(window.inputContentView.isHidden == false)
		#expect(window.columnModel.isConversationObscured == false)
	}

	/// The bundled default size is 474 points tall, below the 500-point minimum
	/// content height, so Reset Window left the window smaller than a resize
	/// could make it.
	@Test("Reset Window never sizes the window below its minimum")
	func defaultFrameRespectsTheMinimumSize() {
		let window = makeWindow()
		window.contentMinSize = MainWindowConstants.minimumContentSize
		let minimum = window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMinSize)).size

		let frame = window.defaultWindowFrame

		#expect(frame.width >= minimum.width)
		#expect(frame.height >= minimum.height)
	}
}

/** Two-finger swipes were read from `beginGesture` and `endGesture`, which
 AppKit no longer sends, so the gesture never did anything. */
@Suite("Main window swipe policy")
struct MainWindowSwipePolicyTests {
	@Test(
		"A swipe needs the system setting and the application's own switch",
		arguments: [(true, 30.0, true), (false, 30.0, false), (true, 0.0, false)]
	)
	func swipeNeedsBothSwitches(systemAllows: Bool, setting: Double, isEnabled: Bool) {
		#expect(MainWindowSwipePolicy.isEnabled(
			systemAllowsSwipeTracking: systemAllows,
			swipeSetting: setting
		) == isEnabled)
	}

	@Test("Only a sideways gesture starts a swipe, and only at its first event")
	func onlyASidewaysStartBegins() {
		#expect(MainWindowSwipePolicy.beginsSwipe(
			phase: .began, scrollingDeltaX: -6, scrollingDeltaY: 1, isEnabled: true
		))
		#expect(MainWindowSwipePolicy.beginsSwipe(
			phase: .began, scrollingDeltaX: 1, scrollingDeltaY: 6, isEnabled: true
		) == false)
		#expect(MainWindowSwipePolicy.beginsSwipe(
			phase: .changed, scrollingDeltaX: -6, scrollingDeltaY: 0, isEnabled: true
		) == false)
		#expect(MainWindowSwipePolicy.beginsSwipe(
			phase: .began, scrollingDeltaX: -6, scrollingDeltaY: 0, isEnabled: false
		) == false)
		#expect(MainWindowSwipePolicy.beginsSwipe(
			phase: .began, scrollingDeltaX: 0, scrollingDeltaY: 0, isEnabled: true
		) == false)
	}

	@Test("A completed swipe turns back to the right and goes on to the left")
	func completedSwipeDirection() {
		#expect(MainWindowSwipePolicy.destination(gestureAmount: 1, phase: .ended, isComplete: true) == .previous)
		#expect(MainWindowSwipePolicy.destination(gestureAmount: -1, phase: .ended, isComplete: true) == .next)
	}

	/// The handler runs for every update and animation frame. Only the call that
	/// completes a swipe past the threshold may move the selection.
	@Test("Updates, animation frames and a swipe that fell short move nothing")
	func unfinishedSwipesMoveNothing() {
		#expect(MainWindowSwipePolicy.destination(gestureAmount: 0.4, phase: .changed, isComplete: false) == nil)
		#expect(MainWindowSwipePolicy.destination(gestureAmount: 0.8, phase: .ended, isComplete: false) == nil)
		#expect(MainWindowSwipePolicy.destination(gestureAmount: 0, phase: .cancelled, isComplete: true) == nil)
	}
}
