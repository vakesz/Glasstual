import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "GLTTestClient.h"
/// #import "IRCChannelPrivate.h"
/// #import "IRCChannelUserPrivate.h"
/// #import "IRCUser.h"
/// #import "TLOInputHistoryPrivate.h"
/// #import "TLOKeyEventHandler.h"
/// #import "TLONicknameCompletionStatusPrivate.h"
/// #import "IRCCommandIndexPrivate.h"
/// #import "TPCPreferencesUserDefaults.h"
/// #import "TVCMainWindow.h"
/// #import "TVCMainWindowTextView.h"
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

@objc
class GLTCompletionWindow: TVCMainWindow {
	@objc var testInputTextField = TVCMainWindowTextView(frame: .zero)
	@objc var testSelectedClient: IRCClient?
	@objc var testSelectedChannel: IRCChannel?

	override var inputTextField: TVCMainWindowTextView? {
		testInputTextField
	}

	override var selectedClient: IRCClient? {
		testSelectedClient
	}

	override var selectedChannel: IRCChannel? {
		testSelectedChannel
	}
}

@objc
class GLTCompletionChannel: IRCChannel {
	@objc var testMembers: [IRCChannelUser] = []

	override var memberList: [IRCChannelUser]? {
		testMembers
	}
}

@objc
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
		let history = TLOInputHistory(window: window)

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
		let handler = TLOKeyEventHandler(target: target)
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
		let handler = TLOKeyEventHandler(target: target)
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
		let handler = TLOKeyEventHandler(target: target)
		let event = keyEventWithCharacters("z", modifiers: [], keyCode: 6)

		XCTAssertFalse(handler.processKeyEvent(event))
		XCTAssertEqual(target.invocationCount, 0)
	}

	@objc
	func testNicknameCompletionCompletesLocalCommandAndPreservesCommandPrefix() {
		IRCCommandIndex.populateCommandIndex()

		let window: GLTCompletionWindow! = GLTCompletionWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)

		window.testInputTextField = TVCMainWindowTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
		window.contentView?.addSubview(window.testInputTextField)
		window.testInputTextField.stringValue = "/jo"
		window.testInputTextField.setSelectedRange(NSRange(location: 3, length: 0))

		let completion = TLONicknameCompletionStatus(window: window)

		completion.completeNickname(true)
		XCTAssertEqual(window.testInputTextField.string, "/join ")
		XCTAssertEqual(window.testInputTextField.selectedRange.location, 6)
	}

	@objc
	func testNicknameCompletionUsesChannelMembersAndConfiguredSuffix() {
		let defaults = TPCPreferencesUserDefaults.shared()
		let preferenceKey = "Keyboard -> Tab Key Completion Suffix"
		let originalSuffix = defaults.object(forKey: preferenceKey)

		defaults.set(": ", forKey: preferenceKey)

		let client = GLTTestClient()
		let member = GLTTestClient.testChannelUser(nickname: "Alice", on: client)
		let channel: GLTCompletionChannel! = GLTCompletionChannel(configDictionary: ["channelName": "#chat"])

		channel.testMembers = [member]

		let window: GLTCompletionWindow! = GLTCompletionWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)

		window.testSelectedClient = client
		window.testSelectedChannel = channel
		window.testInputTextField = TVCMainWindowTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
		window.contentView?.addSubview(window.testInputTextField)
		window.testInputTextField.stringValue = "Al"
		window.testInputTextField.setSelectedRange(NSRange(location: 2, length: 0))

		let completion = TLONicknameCompletionStatus(window: window)

		completion.completeNickname(true)
		XCTAssertEqual(window.testInputTextField.string, "Alice: ")

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
