import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCChannelPrivate.h"
// #import "IRCChannelUserPrivate.h"
// #import "IRCUser.h"
// #import "TLOInputHistoryPrivate.h"
// #import "TLOKeyEventHandler.h"
// #import "TLONicknameCompletionStatusPrivate.h"
// #import "IRCCommandIndexPrivate.h"
// #import "TPCPreferencesUserDefaults.h"
// #import "TVCMainWindow.h"
// #import "TVCMainWindowTextView.h"
/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class GLTKeyEventTarget: NSObject {
    @objc var invocationCount: UInt = 0
    @objc var lastEvent: UnsafeMutablePointer<NSEvent>?

    @objc
    func handleKeyEvent(_ event: UnsafeMutablePointer<NSEvent>) {
        self.invocationCount += 1
        self.lastEvent = event
    }
}
@objc
class GLTCompletionWindow: TVCMainWindow {
    @objc var testInputTextField: UnsafeMutablePointer<TVCMainWindowTextView>
    @objc var testSelectedClient: UnsafeMutablePointer<IRCClient>?
    @objc var testSelectedChannel: UnsafeMutablePointer<IRCChannel>?

    @objc
    func inputTextField() -> UnsafeMutablePointer<TVCMainWindowTextView>? {
        return self.testInputTextField
    }
    @objc
    func selectedClient() -> UnsafeMutablePointer<IRCClient>? {
        return self.testSelectedClient
    }
    @objc
    func selectedChannel() -> UnsafeMutablePointer<IRCChannel>? {
        return self.testSelectedChannel
    }
}
@objc
class GLTCompletionChannel: IRCChannel {
    @objc var testMembers: [IRCChannelUser]

    @objc
    func memberList() -> [IRCChannelUser]? {
        return self.testMembers
    }
}
@objc
class InputHandlingMigrationTests: XCTestCase {
    @objc
    func testInputHistoryNavigatesEntriesAndSkipsConsecutiveDuplicates() {
        let defaults: NSUserDefaults! = NSUserDefaults.standardUserDefaults
        let originalChannelSpecificValue: Bool = defaults.boolForKey("SaveInputHistoryPerSelection")

        defaults.setBool(false, forKey: "SaveInputHistoryPerSelection")

        let window: UnsafeMutablePointer<TVCMainWindow>! = TVCMainWindow(contentRect: NSZeroRect, styleMask: NSWindowStyleMaskBorderless, backing: NSBackingStoreBuffered, defer: false)
        let history: UnsafeMutablePointer<TLOInputHistory>! = TLOInputHistory(window: window)

        history.add(NSAttributedString(string: "first"))
        history.add(NSAttributedString(string: "second"))
        history.add(NSAttributedString(string: "second"))

        XCTAssertEqualObjects(history.up(NSAttributedString(string: "")).string, "second")
        XCTAssertEqualObjects(history.up(NSAttributedString(string: "second")).string, "first")
        XCTAssertEqualObjects(history.down(NSAttributedString(string: "first")).string, "second")
        XCTAssertEqualObjects(history.down(NSAttributedString(string: "second")).string, "")

        defaults.setBool(originalChannelSpecificValue, forKey: "SaveInputHistoryPerSelection")
    }
    @objc
    func testKeyEventHandlerDispatchesRegisteredKeyCode() {
        let target = GLTKeyEventTarget()
        let handler: UnsafeMutablePointer<TLOKeyEventHandler>! = TLOKeyEventHandler(target: target)
        let event = self.keyEventWithCharacters("a", modifiers: NSEventModifierFlagCommand, keyCode: 42)

        handler.registerSelector(#selector(handleKeyEvent(_:)), key: 42, modifiers: NSEventModifierFlagCommand)

        XCTAssertTrue(handler.processKeyEvent(event))

        XCTAssertEqual(target.invocationCount, 1)
        XCTAssertEqual(target.lastEvent, event)
    }
    @objc
    func testKeyEventHandlerFallsBackToCaseInsensitiveCharacter() {
        let target = GLTKeyEventTarget()
        let handler: UnsafeMutablePointer<TLOKeyEventHandler>! = TLOKeyEventHandler(target: target)
        let event = self.keyEventWithCharacters("A", modifiers: 0, keyCode: 42)

        handler.registerSelector(#selector(handleKeyEvent(_:)), character: 'a', modifiers: 0)
        XCTAssertTrue(handler.processKeyEvent(event))
        XCTAssertEqual(target.invocationCount, 1)
    }
    @objc
    func testKeyEventHandlerReturnsNoForUnregisteredEvent() {
        let target = GLTKeyEventTarget()
        let handler: UnsafeMutablePointer<TLOKeyEventHandler>! = TLOKeyEventHandler(target: target)
        let event = self.keyEventWithCharacters("z", modifiers: 0, keyCode: 6)

        XCTAssertFalse(handler.processKeyEvent(event))
        XCTAssertEqual(target.invocationCount, 0)
    }
    @objc
    func testNicknameCompletionCompletesLocalCommandAndPreservesCommandPrefix() {
        IRCCommandIndex.populateCommandIndex()

        let window: GLTCompletionWindow! = GLTCompletionWindow(contentRect: NSMakeRect(0, 0, 400, 100), styleMask: NSWindowStyleMaskBorderless, backing: NSBackingStoreBuffered, defer: false)

        window.testInputTextField = TVCMainWindowTextView(frame: NSMakeRect(0, 0, 400, 100))
        window.contentView.addSubview(window.testInputTextField)
        window.testInputTextField.stringValue = "/jo"
        window.testInputTextField.setSelectedRange(NSMakeRange(3, 0))

        let completion: UnsafeMutablePointer<TLONicknameCompletionStatus>! = TLONicknameCompletionStatus(window: window)

        completion.completeNickname(true)
        XCTAssertEqualObjects(window.testInputTextField.string, "/join ")
        XCTAssertEqual(window.testInputTextField.selectedRange.location, 6)
    }
    @objc
    func testNicknameCompletionUsesChannelMembersAndConfiguredSuffix() {
        let defaults: UnsafeMutablePointer<TPCPreferencesUserDefaults>! = TPCPreferencesUserDefaults.sharedUserDefaults
        let preferenceKey = "Keyboard -> Tab Key Completion Suffix"
        let originalSuffix: AnyObject! = defaults.objectForKey(preferenceKey)

        defaults.setObject(": ", forKey: preferenceKey)

        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        let user: UnsafeMutablePointer<IRCUser>! = IRCUser(nickname: "Alice", onClient: client)
        let member: UnsafeMutablePointer<IRCChannelUser>! = IRCChannelUser(user: user)
        let channel: GLTCompletionChannel! = GLTCompletionChannel(configDictionary: ["channelName": "#chat"])

        channel.testMembers = [member]

        let window: GLTCompletionWindow! = GLTCompletionWindow(contentRect: NSMakeRect(0, 0, 400, 100), styleMask: NSWindowStyleMaskBorderless, backing: NSBackingStoreBuffered, defer: false)

        window.testSelectedClient = client
        window.testSelectedChannel = channel
        window.testInputTextField = TVCMainWindowTextView(frame: NSMakeRect(0, 0, 400, 100))
        window.contentView.addSubview(window.testInputTextField)
        window.testInputTextField.stringValue = "Al"
        window.testInputTextField.setSelectedRange(NSMakeRange(2, 0))

        let completion: UnsafeMutablePointer<TLONicknameCompletionStatus>! = TLONicknameCompletionStatus(window: window)

        completion.completeNickname(true)
        XCTAssertEqualObjects(window.testInputTextField.string, "Alice: ")

        if originalSuffix {
            defaults.setObject(originalSuffix, forKey: preferenceKey)
        } else {
            defaults.removeObjectForKey(preferenceKey)
        }
    }
    @objc
    func keyEventWithCharacters(_ characters: String, modifiers: NSEventModifierFlags, keyCode: CUnsignedShort) -> UnsafeMutablePointer<NSEvent> {
        return NSEvent.keyEventWithType(NSEventTypeKeyDown, location: NSZeroPoint, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
    }
}