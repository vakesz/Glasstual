/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/** `NSApplication` offers the window every key event before the responder
 chain sees it, so a shortcut registered on the window otherwise fires wherever
 the keyboard happens to be. */
@Suite("Main window input shortcuts")
@MainActor
struct MainWindowShortcutPolicyTests {
	private func makeInputBar() -> (container: NSView, field: NSTextView) {
		let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
		let scrollView = NSScrollView(frame: container.bounds)
		let field = NSTextView(frame: container.bounds)
		scrollView.documentView = field
		container.addSubview(scrollView)
		return (container, field)
	}

	@Test("The message field, and anything inside its container, owns the shortcut")
	func inputBarOwnsTheShortcut() {
		let (container, field) = makeInputBar()

		#expect(MainWindowInputShortcutPolicy.shouldHandle(firstResponder: field, inputBar: container))
		#expect(MainWindowInputShortcutPolicy.shouldHandle(firstResponder: container, inputBar: container))
	}

	/** The regression: typing a filter in the toolbar's search field and
	 pressing Tab completed a nickname into the chat input and moved the
	 keyboard there with it. */
	@Test("A responder outside the input bar does not")
	func otherRespondersDoNot() {
		let (container, _) = makeInputBar()
		let searchField = NSSearchField(frame: .zero)

		#expect(MainWindowInputShortcutPolicy.shouldHandle(firstResponder: searchField, inputBar: container) == false)
		#expect(MainWindowInputShortcutPolicy.shouldHandle(firstResponder: nil, inputBar: container) == false)
		#expect(MainWindowInputShortcutPolicy.shouldHandle(firstResponder: nil, inputBar: nil) == false)
	}

	/// A window that has not built its input bar yet answers no rather than
	/// claiming the event.
	@Test("No input bar means no claim")
	func missingInputBarDeclines() {
		let (_, field) = makeInputBar()

		#expect(MainWindowInputShortcutPolicy.shouldHandle(firstResponder: field, inputBar: nil) == false)
	}

	/** A declined shortcut has to leave the event alone, not swallow it: the
	 view that has the keyboard still has to receive the key press. */
	@Test("A declining registration reports the event as unhandled")
	func decliningRegistrationLeavesTheEvent() throws {
		let handler = KeyEventHandler()
		var declinedCount = 0
		var claimedCount = 0
		handler.registerConditional(key: .tab) { _ in
			declinedCount += 1
			return false
		}
		handler.registerConditional(key: .escape) { _ in
			claimedCount += 1
			return true
		}

		let tab = try #require(Self.keyDown(keyCode: KeyCode.tab.rawValue))
		let escape = try #require(Self.keyDown(keyCode: KeyCode.escape.rawValue, characters: "\u{1B}"))

		#expect(handler.processKeyEvent(tab) == false)
		#expect(declinedCount == 1)
		#expect(handler.processKeyEvent(escape))
		#expect(claimedCount == 1)
	}

	private static func keyDown(keyCode: UInt16, characters: String = "\t") -> NSEvent? {
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
}

/// A stale swipe origin produced a delta past any threshold, and the channel
/// changed under a gesture the user never made.
@Suite("Main window swipe origin")
@MainActor
struct MainWindowSwipePolicyTests {
	@Test("Only a two-finger gesture with swiping enabled records an origin")
	func twoFingersRecordAnOrigin() {
		#expect(MainWindowSwipePolicy.recordsOrigin(touchCount: 2, minimumSwipeLength: 30))
	}

	@Test("Everything else clears it")
	func anythingElseClearsTheOrigin() {
		#expect(MainWindowSwipePolicy.recordsOrigin(touchCount: 1, minimumSwipeLength: 30) == false)
		#expect(MainWindowSwipePolicy.recordsOrigin(touchCount: 3, minimumSwipeLength: 30) == false)
		#expect(MainWindowSwipePolicy.recordsOrigin(touchCount: 0, minimumSwipeLength: 30) == false)
		#expect(MainWindowSwipePolicy.recordsOrigin(touchCount: 2, minimumSwipeLength: 0) == false)
	}
}
