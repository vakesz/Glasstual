/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@MainActor
struct TLOKeyEventHandlerTests {
	private func keyEvent(
		code: UInt16,
		characters: String,
		modifiers: NSEvent.ModifierFlags = []
	) -> NSEvent? {
		NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: modifiers,
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: characters,
			charactersIgnoringModifiers: characters,
			isARepeat: false,
			keyCode: code
		)
	}

	/// Key code 0 is `kVK_ANSI_A`; registering it used to abort the process.
	@Test("Key code zero can be registered and dispatched")
	func keyCodeZeroIsAcceptedAndDispatched() throws {
		let handler = KeyEventHandler()
		var firedCount = 0

		handler.register(key: .keyA) { _ in firedCount += 1 }

		let event = try #require(keyEvent(code: 0, characters: "a"))

		#expect(handler.processKeyEvent(event))
		#expect(firedCount == 1)
	}

	@Test("An unregistered key code is not consumed")
	func unregisteredKeyIsNotConsumed() throws {
		let handler = KeyEventHandler()
		var firedCount = 0

		handler.register(key: .keyA) { _ in firedCount += 1 }

		let event = try #require(keyEvent(code: 0x31, characters: "\u{f701}"))

		#expect(handler.processKeyEvent(event) == false)
		#expect(firedCount == 0)
	}

	/// Registration is keyed by the exact modifier set, so the same key with
	/// different modifiers is a different shortcut.
	@Test("Modifiers are part of the shortcut")
	func modifiersDistinguishShortcuts() throws {
		let handler = KeyEventHandler()
		var plain = 0
		var commanded = 0

		handler.register(key: .escape) { _ in plain += 1 }
		handler.register(key: .escape, modifiers: .command) { _ in commanded += 1 }

		let plainEvent = try #require(keyEvent(code: KeyCode.escape.rawValue, characters: "\u{1b}"))
		let commandEvent = try #require(
			keyEvent(code: KeyCode.escape.rawValue, characters: "\u{1b}", modifiers: .command)
		)

		#expect(handler.processKeyEvent(plainEvent))
		#expect(handler.processKeyEvent(commandEvent))
		#expect(plain == 1)
		#expect(commanded == 1)
	}

	@Test("A character shortcut matches regardless of case")
	func characterShortcutIsCaseInsensitive() throws {
		let handler = KeyEventHandler()
		var firedCount = 0

		handler.register(character: "a") { _ in firedCount += 1 }

		let event = try #require(keyEvent(code: 42, characters: "A"))

		#expect(handler.processKeyEvent(event))
		#expect(firedCount == 1)
	}

	@Test("The handler hands the event it matched to the action")
	func actionReceivesTheEvent() throws {
		let handler = KeyEventHandler()
		var receivedEvent: NSEvent?

		handler.register(key: .escape, modifiers: .command) { receivedEvent = $0 }

		let event = try #require(
			keyEvent(code: KeyCode.escape.rawValue, characters: "\u{1b}", modifiers: .command)
		)

		#expect(handler.processKeyEvent(event))
		#expect(receivedEvent == event)
	}
}
