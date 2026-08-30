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
 *********************************************************************** */

import AppKit

public enum KeyCode: UInt16, Sendable {
	/// `kVK_ANSI_A`. Zero is a real key code, not "no key".
	case keyA = 0x00
	case returnKey = 0x24
	case tab = 0x30
	case space = 0x31
	case backspace = 0x33
	case escape = 0x35
	case enter = 0x4C
	case home = 0x73
	case pageUp = 0x74
	case forwardDelete = 0x75
	case end = 0x77
	case pageDown = 0x79
	case leftArrow = 0x7B
	case rightArrow = 0x7C
	case downArrow = 0x7D
	case upArrow = 0x7E
}

/// Maps keyboard shortcuts onto closures. Registration used to also accept a
/// selector to send to an `NSObject` target through the runtime; nothing but
/// its own tests used that, and the closure form is checked by the compiler.
@MainActor
public final class KeyEventHandler {
	public typealias Action = @MainActor (NSEvent) -> Void
	private typealias DispatchAction = @MainActor (NSEvent) -> Bool

	private var codeHandlerMap: [UInt: [UInt16: DispatchAction]] = [:]
	private var characterHandlerMap: [UInt: [UInt16: DispatchAction]] = [:]

	public init() {}

	public func register(
		key: KeyCode,
		modifiers: NSEvent.ModifierFlags = [],
		perform action: @escaping Action
	) {
		register(keyCode: key.rawValue, modifiers: modifiers.rawValue) { event in
			action(event)
			return true
		}
	}

	public func register(
		character: Character,
		modifiers: NSEvent.ModifierFlags = [],
		perform action: @escaping Action
	) {
		guard let characterCode = character.lowercased().utf16.first else {
			preconditionFailure("Keyboard shortcut characters cannot be empty")
		}

		register(characterCode: characterCode, modifiers: modifiers.rawValue) { event in
			action(event)
			return true
		}
	}

	public func processKeyEvent(_ event: NSEvent) -> Bool {
		if let inputClient = NSTextInputContext.current?.client,
		   inputClient.markedRange().length > 0
		{
			return false
		}

		let modifierMask: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
		let modifiers = event.modifierFlags.intersection(modifierMask).rawValue

		if let action = codeHandlerMap[modifiers]?[event.keyCode] {
			return action(event)
		}

		guard let firstCharacter = event.charactersIgnoringModifiers?.lowercased().utf16.first,
		      let action = characterHandlerMap[modifiers]?[firstCharacter]
		else {
			return false
		}

		return action(event)
	}

	private func register(keyCode: UInt16, modifiers: UInt, perform action: @escaping DispatchAction) {
		/* Zero is kVK_ANSI_A, a real key, so it must not be rejected here. */
		codeHandlerMap[modifiers, default: [:]][keyCode] = action
	}

	private func register(characterCode: UInt16, modifiers: UInt, perform action: @escaping DispatchAction) {
		precondition(characterCode != 0)
		characterHandlerMap[modifiers, default: [:]][characterCode] = action
	}
}
