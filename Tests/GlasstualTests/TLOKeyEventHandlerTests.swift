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
	private func keyEvent(code: UInt16, characters: String) -> NSEvent? {
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
			keyCode: code
		)
	}

	/// Key code 0 is `kVK_ANSI_A`; registering it used to abort the process.
	@Test("Key code zero can be registered and dispatched")
	func keyCodeZeroIsAcceptedAndDispatched() throws {
		let target = KeyEventRecorder()
		let handler = KeyEventHandler(target: target)

		handler.register(#selector(KeyEventRecorder.handleKey(_:)), key: 0, modifiers: 0)

		let event = try #require(keyEvent(code: 0, characters: "a"))

		#expect(handler.processKeyEvent(event))
		#expect(target.firedCount == 1)
	}

	@Test("An unregistered key code is not consumed")
	func unregisteredKeyIsNotConsumed() throws {
		let target = KeyEventRecorder()
		let handler = KeyEventHandler(target: target)

		handler.register(#selector(KeyEventRecorder.handleKey(_:)), key: 0, modifiers: 0)

		let event = try #require(keyEvent(code: 0x31, characters: "\u{f701}"))

		#expect(handler.processKeyEvent(event) == false)
		#expect(target.firedCount == 0)
	}
}

private final class KeyEventRecorder: NSObject {
	private(set) var firedCount = 0

	@objc
	func handleKey(_: NSEvent) {
		firedCount += 1
	}
}
