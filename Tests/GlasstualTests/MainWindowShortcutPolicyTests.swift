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
	private func makeWindow() -> MainWindow {
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		let inputBar = window.inputContentView!
		inputBar.frame = NSRect(x: 0, y: 0, width: 400, height: 40)
		window.contentView?.addSubview(inputBar)
		return window
	}

	@Test("The message field, and anything inside its container, owns the shortcut")
	func inputBarOwnsTheShortcut() {
		let window = makeWindow()

		#expect(window.makeFirstResponder(window.inputTextField))
		#expect(window.inputBarHoldsKeyboardFocus)
	}

	/** The regression: typing a filter in the toolbar's search field and
	 pressing Tab completed a nickname into the chat input and moved the
	 keyboard there with it. */
	@Test("A responder outside the input bar does not")
	func otherRespondersDoNot() {
		let window = makeWindow()
		let searchField = NSSearchField(frame: NSRect(x: 0, y: 100, width: 200, height: 24))
		window.contentView?.addSubview(searchField)

		#expect(window.makeFirstResponder(searchField))
		#expect(window.inputBarHoldsKeyboardFocus == false)

		window.makeFirstResponder(nil)
		#expect(window.inputBarHoldsKeyboardFocus == false)
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
