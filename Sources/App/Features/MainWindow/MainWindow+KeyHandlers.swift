// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

/** The window's own keyboard shortcuts.

 Three scopes, and the difference between them is what a key does where the
 reader is not typing a message: ``register(key:modifiers:perform:)`` claims a
 key for the whole window, the `registerForInputBar` pair claims one only while
 the message field holds the keyboard and declines it otherwise, and the
 `registerInput` pair registers on the field itself. */
extension MainWindow {
	private func register(
		key: KeyCode,
		modifiers: NSEvent.ModifierFlags = [],
		perform action: @escaping (MainWindow, NSEvent) -> Void
	) {
		keyEventHandler.register(key: key, modifiers: modifiers) { [weak self] event in
			guard let self else { return }
			action(self, event)
		}
	}

	private func register(
		character: Character,
		modifiers: NSEvent.ModifierFlags,
		perform action: @escaping (MainWindow, NSEvent) -> Void
	) {
		keyEventHandler.register(character: character, modifiers: modifiers) { [weak self] event in
			guard let self else { return }
			action(self, event)
		}
	}

	/** Whether the message field, or anything inside its container, holds the
	 keyboard.

	 `NSApplication` offers the window every key event before the responder
	 chain sees it, so a shortcut registered on the window otherwise fires
	 wherever the keyboard is: typing a filter in the toolbar's search field and
	 pressing Tab completed a nickname into the chat input and moved the
	 keyboard there with it. The container is what is asked about, so the field,
	 its scroll view's clip view and any field editor inside it all count. */
	var inputBarHoldsKeyboardFocus: Bool {
		guard let inputContentView, let responder = firstResponder as? NSView else { return false }
		return responder === inputContentView || responder.isDescendant(of: inputContentView)
	}

	/// A window-level shortcut that only applies to the message field. It is
	/// declined -- and so left to whatever view has the keyboard -- otherwise.
	private func registerForInputBar(
		key: KeyCode,
		modifiers: NSEvent.ModifierFlags = [],
		perform action: @escaping (MainWindow, NSEvent) -> Void
	) {
		keyEventHandler.registerConditional(key: key, modifiers: modifiers) { [weak self] event in
			guard let self, inputBarHoldsKeyboardFocus else { return false }
			action(self, event)
			return true
		}
	}

	/// The character form of `registerForInputBar(key:modifiers:perform:)`.
	private func registerForInputBar(
		character: Character,
		modifiers: NSEvent.ModifierFlags,
		perform action: @escaping (MainWindow, NSEvent) -> Void
	) {
		keyEventHandler.registerConditional(character: character, modifiers: modifiers) { [weak self] event in
			guard let self, inputBarHoldsKeyboardFocus else { return false }
			action(self, event)
			return true
		}
	}

	private func registerInput(
		key: KeyCode,
		modifiers: NSEvent.ModifierFlags = [],
		perform action: @escaping (MainWindow, NSEvent) -> Void
	) {
		inputTextField.register(key: key, modifiers: modifiers) { [weak self] event in
			guard let self else { return }
			action(self, event)
		}
	}

	private func registerInput(
		character: Character,
		modifiers: NSEvent.ModifierFlags,
		perform action: @escaping (MainWindow, NSEvent) -> Void
	) {
		inputTextField.register(character: character, modifiers: modifiers) { [weak self] event in
			guard let self else { return }
			action(self, event)
		}
	}

	func performedCustomKeyboardEvent(_ event: NSEvent) -> Bool {
		keyEventHandler.processKeyEvent(event)
	}

	func redirectKeyDown(_ event: NSEvent) {
		inputTextField.focus()
		guard event.keyCode != KeyCode.enter.rawValue, event.keyCode != KeyCode.returnKey.rawValue else { return }
		inputTextField.keyDown(with: event)
	}

	func registerKeyHandlers() {
		/* In the message field, Escape dismisses a spelling suggestion, cancels
		 a reply and closes the completion popup. Anywhere else the window
		 leaves Escape to whatever holds the keyboard. It used to leave full
		 screen instead, so the toolbar's search field and the find bar never
		 got the Escape that clears or closes them. The green button and
		 Control-Command-F leave full screen. */
		registerForInputBar(key: .escape) { $0.inputTextField.keyDown(with: $1) }
		/* Declined, not swallowed, when the setting says Tab does nothing:
		 the field then hands Tab to keyboard navigation instead of holding the
		 keyboard in place. */
		keyEventHandler.registerConditional(key: .tab) { [weak self] event in
			guard let self, inputBarHoldsKeyboardFocus else { return false }
			return tab(event)
		}
		keyEventHandler.registerConditional(key: .tab, modifiers: .shift) { [weak self] event in
			guard let self, inputBarHoldsKeyboardFocus else { return false }
			return shiftTab(event)
		}
		register(key: .tab, modifiers: .option) { $0.selectPreviousSelection($1) }
		/* The two colour commands pop a menu up at the caret, which no menu item
		 can do, so they stay registrations. Bold, italics and underline are
		 Format menu items with key equivalents of their own; registering them
		 here as well gave the window a second, unvalidated copy of each.
		 Registered unconditionally, ⌘B also swallowed the key wherever the
		 reader was -- in the toolbar's search field, in a sheet's field, in the
		 transcript -- and gave nothing back, which is why what is left is
		 scoped to the input bar. */
		registerForInputBar(character: "c", modifiers: [.control, .shift]) { $0.textFormattingForegroundColor($1) }
		registerForInputBar(character: "h", modifiers: [.control, .shift]) { $0.textFormattingBackgroundColor($1) }
		registerForInputBar(character: "p", modifiers: .control) { $0.inputHistoryUp($1) }
		registerForInputBar(character: "n", modifiers: .control) { $0.inputHistoryDown($1) }

		registerInput(key: .enter, modifiers: .control) { $0.sendControlEnterMessageMaybe($1) }
		registerInput(key: .returnKey, modifiers: .command) { $0.sendMessageAsAction($1) }
		registerInput(key: .enter, modifiers: .command) { $0.sendMessageAsAction($1) }
		/* Control+Command+T, beside Control+Command+S for the server list:
		 Option+Command+L is the Window menu's File Transfers, and
		 Option+Command+T is the system's Show/Hide Toolbar. */
		registerInput(character: "t", modifiers: [.control, .command]) { $0.focusTranscript($1) }
		registerInput(key: .upArrow) { $0.inputHistoryUpWithScrollCheck($1) }
		registerInput(key: .upArrow, modifiers: .option) { $0.inputHistoryUpWithScrollCheck($1) }
		registerInput(key: .downArrow) { $0.inputHistoryDownWithScrollCheck($1) }
		registerInput(key: .downArrow, modifiers: .option) { $0.inputHistoryDownWithScrollCheck($1) }
	}
}
