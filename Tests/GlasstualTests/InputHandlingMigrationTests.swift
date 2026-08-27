@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "GLTTestClient.h"
/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class GLTKeyEventTarget: NSObject {
	@objc var invocationCount: UInt = 0
	@objc var lastEvent: NSEvent?

	@objc
	func handleKeyEvent(_ event: NSEvent) {
		invocationCount += 1
		lastEvent = event
	}
}

@MainActor
private final class GLTCompletionWindow: NicknameCompletionWindow {
	var inputTextField: MainWindowTextView!
	var selectedClient: IRCClient?
	var selectedChannel: Channel?
}

@objc
class GLTCompletionChannel: Channel, @unchecked Sendable {
	@objc var testMembers: [ChannelUser] = []

	override var channelMembers: [ChannelUser]? {
		testMembers
	}
}

@objc
@MainActor
class InputHandlingMigrationTests: XCTestCase {
	@objc
	func testInputHistoryNavigatesEntriesAndSkipsConsecutiveDuplicates() {
		let defaults = UserDefaults.standard
		let originalChannelSpecificValue = defaults.bool(forKey: "SaveInputHistoryPerSelection")

		defaults.set(false, forKey: "SaveInputHistoryPerSelection")

		let window = TVCMainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let history = InputHistory(window: window)

		history.add(NSAttributedString(string: "first"))
		history.add(NSAttributedString(string: "second"))
		history.add(NSAttributedString(string: "second"))

		XCTAssertEqual(history.up(NSAttributedString(string: ""))?.string, "second")
		XCTAssertEqual(history.up(NSAttributedString(string: "second"))?.string, "first")
		XCTAssertEqual(history.down(NSAttributedString(string: "first"))?.string, "second")
		XCTAssertEqual(history.down(NSAttributedString(string: "second"))?.string, "")

		defaults.set(originalChannelSpecificValue, forKey: "SaveInputHistoryPerSelection")
	}

	@objc
	func testKeyEventHandlerDispatchesRegisteredKeyCode() {
		let target = GLTKeyEventTarget()
		let handler = KeyEventHandler(target: target)
		let event = keyEventWithCharacters("a", modifiers: .command, keyCode: 42)

		handler.register(
			#selector(GLTKeyEventTarget.handleKeyEvent(_:)),
			key: 42,
			modifiers: NSEvent.ModifierFlags.command.rawValue
		)

		XCTAssertTrue(handler.processKeyEvent(event))

		XCTAssertEqual(target.invocationCount, 1)
		XCTAssertEqual(target.lastEvent, event)
	}

	@objc
	func testKeyEventHandlerFallsBackToCaseInsensitiveCharacter() throws {
		let target = GLTKeyEventTarget()
		let handler = KeyEventHandler(target: target)
		let event = keyEventWithCharacters("A", modifiers: [], keyCode: 42)

		try handler.register(
			#selector(GLTKeyEventTarget.handleKeyEvent(_:)),
			character: UInt16(XCTUnwrap(Character("a").asciiValue)),
			modifiers: 0
		)
		XCTAssertTrue(handler.processKeyEvent(event))
		XCTAssertEqual(target.invocationCount, 1)
	}

	@objc
	func testKeyEventHandlerReturnsNoForUnregisteredEvent() {
		let target = GLTKeyEventTarget()
		let handler = KeyEventHandler(target: target)
		let event = keyEventWithCharacters("z", modifiers: [], keyCode: 6)

		XCTAssertFalse(handler.processKeyEvent(event))
		XCTAssertEqual(target.invocationCount, 0)
	}

	func testKeyEventHandlerDispatchesTypedShortcutAction() {
		let handler = KeyEventHandler(target: GLTKeyEventTarget())
		let event = keyEventWithCharacters("\u{1b}", modifiers: .command, keyCode: KeyCode.escape.rawValue)
		var receivedEvent: NSEvent?
		handler.register(key: .escape, modifiers: .command) { receivedEvent = $0 }

		XCTAssertTrue(handler.processKeyEvent(event))
		XCTAssertEqual(receivedEvent, event)
	}

	func testInputHandlingRetainsNibAndSelectorCompatibility() {
		XCTAssertNotNil(NSClassFromString("TLOKeyEventHandler"))
		XCTAssertTrue(KeyEventHandler.instancesRespond(to: NSSelectorFromString("processKeyEvent:")))
		XCTAssertTrue(KeyEventHandler.instancesRespond(to: NSSelectorFromString("setKeyHandlerTarget:")))
		XCTAssertNotNil(NSClassFromString("TLONicknameCompletionStatus"))
		XCTAssertTrue(NicknameCompletionStatus.instancesRespond(to: NSSelectorFromString("completeNickname:")))
	}

	@objc
	func testNicknameCompletionCompletesLocalCommandAndPreservesCommandPrefix() {
		CommandIndex.populateCommandIndex()

		let hostWindow = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let textField = MainWindowTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
		let window = GLTCompletionWindow()
		window.inputTextField = textField
		hostWindow.contentView?.addSubview(textField)
		textField.stringValue = "/jo"
		textField.setSelectedRange(NSRange(location: 3, length: 0))

		let completion = NicknameCompletionStatus(window: window)

		completion.completeNickname(true)
		XCTAssertEqual(textField.string, "/join ")
		XCTAssertEqual(textField.selectedRange.location, 6)
	}

	@objc
	func testNicknameCompletionUsesChannelMembersAndConfiguredSuffix() {
		let defaults = TextualUserDefaults.shared()
		let preferenceKey = "Keyboard -> Tab Key Completion Suffix"
		let originalSuffix = defaults.object(forKey: preferenceKey)

		defaults.set(": ", forKey: preferenceKey)

		let client = GLTTestClient()
		let member = GLTTestClient.testChannelUser(nickname: "Alice", on: client)
		let channel: GLTCompletionChannel! = GLTCompletionChannel(configDictionary: ["channelName": "#chat"])

		channel.testMembers = [member]

		let hostWindow = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let textField = MainWindowTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
		let window = GLTCompletionWindow()
		window.selectedClient = client
		window.selectedChannel = channel
		window.inputTextField = textField
		hostWindow.contentView?.addSubview(textField)
		textField.stringValue = "Al"
		textField.setSelectedRange(NSRange(location: 2, length: 0))

		let completion = NicknameCompletionStatus(window: window)

		completion.completeNickname(true)
		XCTAssertEqual(textField.string, "Alice: ")

		if let originalSuffix {
			defaults.set(originalSuffix, forKey: preferenceKey)
		} else {
			defaults.removeObject(forKey: preferenceKey)
		}
	}

	@objc
	func keyEventWithCharacters(_ characters: String, modifiers: NSEvent.ModifierFlags,
	                            keyCode: UInt16) -> NSEvent
	{
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
			keyCode: keyCode
		)!
	}
}
