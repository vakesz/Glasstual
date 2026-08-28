@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "GLTTestClient.h"
/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@MainActor
private final class GLTCompletionWindow: NicknameCompletionWindow {
	var inputTextField: MainWindowTextView!
	var selectedClient: IRCClient?
	var selectedChannel: Channel?
}

@objc
@MainActor
class GLTCompletionChannel: Channel, @unchecked Sendable {
	@objc var testMembers: [ChannelUser] = []

	override var channelMembers: [ChannelUser] {
		testMembers
	}
}

@objc
@MainActor
class InputHandlingMigrationTests: XCTestCase {
	@objc
	func testInputHistoryNavigatesEntriesAndSkipsConsecutiveDuplicates() {
		let defaults = TextualUserDefaults.shared()
		let preferenceKey = "SaveInputHistoryPerSelection"
		let originalChannelSpecificValue = defaults
			.persistentDomain(forName: ApplicationGroup.identifier)?[preferenceKey]
		defer {
			if let originalChannelSpecificValue {
				defaults.set(originalChannelSpecificValue, forKey: preferenceKey)
			} else {
				defaults.removeObject(forKey: preferenceKey)
			}
		}

		defaults.set(false, forKey: preferenceKey)

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
	}

	/** Key event handlers are registered with closures now; the selector-based
	 registration and its NSObject target requirement are gone. */
	func testKeyEventHandlerDispatchesRegisteredKeyCode() {
		let handler = KeyEventHandler()
		let event = keyEventWithCharacters("a", modifiers: .command, keyCode: 42)
		var invocationCount = 0
		var lastEvent: NSEvent?

		handler.register(character: "a", modifiers: .command) { event in
			invocationCount += 1
			lastEvent = event
		}

		XCTAssertTrue(handler.processKeyEvent(event))
		XCTAssertEqual(invocationCount, 1)
		XCTAssertEqual(lastEvent, event)
	}

	func testKeyEventHandlerFallsBackToCaseInsensitiveCharacter() {
		let handler = KeyEventHandler()
		let event = keyEventWithCharacters("A", modifiers: [], keyCode: 42)
		var invocationCount = 0

		handler.register(character: "a") { _ in invocationCount += 1 }

		XCTAssertTrue(handler.processKeyEvent(event))
		XCTAssertEqual(invocationCount, 1)
	}

	func testKeyEventHandlerReturnsNoForUnregisteredEvent() {
		let handler = KeyEventHandler()
		let event = keyEventWithCharacters("z", modifiers: [], keyCode: 6)
		var invocationCount = 0

		handler.register(character: "a") { _ in invocationCount += 1 }

		XCTAssertFalse(handler.processKeyEvent(event))
		XCTAssertEqual(invocationCount, 0)
	}

	func testKeyEventHandlerDispatchesTypedShortcutAction() {
		let handler = KeyEventHandler()
		let event = keyEventWithCharacters("\u{1b}", modifiers: .command, keyCode: KeyCode.escape.rawValue)
		var receivedEvent: NSEvent?
		handler.register(key: .escape, modifiers: .command) { receivedEvent = $0 }

		XCTAssertTrue(handler.processKeyEvent(event))
		XCTAssertEqual(receivedEvent, event)
	}

	func testInputHandlingRetainsNibAndSelectorCompatibility() {
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
		let originalSuffix = defaults.persistentDomain(forName: ApplicationGroup.identifier)?[preferenceKey]
		defer {
			if let originalSuffix {
				defaults.set(originalSuffix, forKey: preferenceKey)
			} else {
				defaults.removeObject(forKey: preferenceKey)
			}
		}

		defaults.set(": ", forKey: preferenceKey)

		let client = GLTTestClient()
		let member = GLTTestClient.testChannelUser(nickname: "Alice", on: client)
		let channel: GLTCompletionChannel! = GLTCompletionChannel(config: ChannelConfig(channelName: "#chat"))

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
