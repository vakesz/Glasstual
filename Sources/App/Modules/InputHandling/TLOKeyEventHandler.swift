/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc(TLOKeyEventHandler)
@MainActor
public final class KeyEventHandler: NSObject, TLOKeyEventHandlerPrototype {
	private weak var target: NSObject?
	private var codeHandlerMap: [UInt: [UInt: String]] = [:]
	private var characterHandlerMap: [UInt: [UInt16: String]] = [:]

	@available(*, unavailable)
	override public convenience init() {
		fatalError("Use init(target:)")
	}

	@objc(initWithTarget:)
	public init(target: Any) {
		guard let target = target as? NSObject else {
			preconditionFailure("Key event targets must inherit from NSObject")
		}

		self.target = target

		super.init()
	}

	@objc(setKeyHandlerTarget:)
	public func setKeyHandlerTarget(_ target: Any) {
		guard let target = target as? NSObject else {
			preconditionFailure("Key event targets must inherit from NSObject")
		}

		self.target = target
	}

	@objc(registerSelector:key:modifiers:)
	public func register(_ selector: Selector, key keyCode: UInt, modifiers: UInt) {
		precondition(keyCode != 0)

		codeHandlerMap[modifiers, default: [:]][keyCode] = NSStringFromSelector(selector)
	}

	@objc(registerSelector:character:modifiers:)
	public func register(_ selector: Selector, character: UInt16, modifiers: UInt) {
		precondition(character != 0)

		characterHandlerMap[modifiers, default: [:]][character] = NSStringFromSelector(selector)
	}

	@objc(registerSelector:characters:modifiers:)
	public func register(_ selector: Selector, characters characterRange: NSRange, modifiers: UInt) {
		let selectorName = NSStringFromSelector(selector)
		let upperBound = NSMaxRange(characterRange)

		for value in characterRange.location ..< upperBound {
			guard let character = UInt16(exactly: value) else {
				continue
			}

			characterHandlerMap[modifiers, default: [:]][character] = selectorName
		}
	}

	@objc(processKeyEvent:)
	public func processKeyEvent(_ event: NSEvent) -> Bool {
		if let inputClient = NSTextInputContext.current?.client,
		   inputClient.markedRange().length > 0
		{
			return false
		}

		let modifierMask: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
		let modifiers = event.modifierFlags.intersection(modifierMask).rawValue

		if let selectorName = codeHandlerMap[modifiers]?[UInt(event.keyCode)] {
			return invoke(selectorName, event: event)
		}

		guard let firstCharacter = event.charactersIgnoringModifiers?.lowercased().utf16.first,
		      let selectorName = characterHandlerMap[modifiers]?[firstCharacter]
		else {
			return false
		}

		return invoke(selectorName, event: event)
	}

	private func invoke(_ selectorName: String, event: NSEvent) -> Bool {
		guard let target else {
			return false
		}

		let selector = NSSelectorFromString(selectorName)

		guard target.responds(to: selector) else {
			return false
		}

		target.perform(selector, with: event)

		return true
	}
}
