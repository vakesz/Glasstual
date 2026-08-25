import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCChannelPrivate.h"
// #import "IRCTreeItemPrivate.h"
// #import "NSColorHelper.h"
// #import "NSTableVIewHelperPrivate.h"
// #import "TDCChannelModifyTopicSheetPrivate.h"
// #import "TDCOnboardingSteps.h"
// #import "TDCPreferencesControllerPrivate.h"
// #import "TDCWindowBase.h"
// #import "THOUnicodeHelper.h"
// #import "TLOSpokenNotificationPrivate.h"
// #import "TVCAutoExpandingTextField.h"
// #import "TVCAutoExpandingTokenField.h"
// #import "TVCMemberListUserInfoPopoverPrivate.h"
// #import "TXAppearanceHelper.h"
/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class GLTWindowSpy: NSWindow {
    @objc var orderFrontCount: UInt = 0
    @objc var closeCount: UInt = 0

    @objc
    func makeKeyAndOrderFront(_ sender: AnyObject?) {
        self.orderFrontCount += 1
    }
    @objc
    func close() {
        self.closeCount += 1
    }
}
@objc
class GLTAppearanceSpyView: NSView {
    @objc var applicationAppearanceChangeCount: UInt = 0
    @objc var systemAppearanceChangeCount: UInt = 0

    @objc
    func needsDisplayWhenApplicationAppearanceChanges() -> Bool {
        return true
    }
    @objc
    func needsDisplayWhenSystemAppearanceChanges() -> Bool {
        return true
    }
    @objc
    override func applicationAppearanceChanged() {
        self.applicationAppearanceChangeCount += 1
        super.applicationAppearanceChanged()
    }
    @objc
    override func systemAppearanceChanged() {
        self.systemAppearanceChangeCount += 1
        super.systemAppearanceChanged()
    }
}
@objc
class AppKitSupportMigrationTests: XCTestCase {
    @objc
    func testAutoExpandingFieldsTrackTheirLayoutWidth() {
        var textField: UnsafeMutablePointer<TVCAutoExpandingTextField>! = TVCAutoExpandingTextField(frame: NSMakeRect(0, 0, 240, 20))

        textField.cell.wraps = true
        textField.layout()
        XCTAssertEqual(textField.preferredMaxLayoutWidth, 240)

        var tokenField: UnsafeMutablePointer<TVCAutoExpandingTokenField>! = TVCAutoExpandingTokenField(frame: NSMakeRect(0, 0, 180, 20))

        tokenField.cell.wraps = true
        tokenField.layout()
        XCTAssertEqual(tokenField.preferredMaxLayoutWidth, 180)
    }
    @objc
    func testAutoExpandingHelperIgnoresNonWrappingFields() {
        var field: UnsafeMutablePointer<NSTextField>! = NSTextField(frame: NSMakeRect(0, 0, 240, 20))

        field.cell.wraps = false
        XCTAssertFalse(TVCAutoExpandingFieldUpdatePreferredMaxLayoutWidth(field))
        XCTAssertEqual(field.preferredMaxLayoutWidth, 0)
    }
    @objc
    func testWindowBaseForwardsWindowLifecycleActions() {
        let window: GLTWindowSpy! = GLTWindowSpy()
        var controller: UnsafeMutablePointer<TDCWindowBase>! = TDCWindowBase()

        controller.window = window
        controller.show()
        controller.ok(nil)
        controller.cancel(nil)

        XCTAssertEqual(window.orderFrontCount, 1)
        XCTAssertEqual(window.closeCount, 2)
    }
    @objc
    func testPreferencesControllerLoadsWindowFromNib() {
        let controller: UnsafeMutablePointer<TDCPreferencesController>! = TDCPreferencesController()

        XCTAssertNotNil(controller.window)
    }
    @objc
    func testMemberInfoPopoverUsesTransientBehavior() {
        let popover: UnsafeMutablePointer<TVCMemberListUserInfoPopover>! = TVCMemberListUserInfoPopover()

        popover.awakeFromNib()
        XCTAssertEqual(popover.behavior, NSPopoverBehaviorTransient)
    }
    @objc
    func testChannelModifyTopicSheetLoadsFromNib() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        var channel: UnsafeMutablePointer<IRCChannel>! = IRCChannel(configDictionary: ["channelName": "#chat"])

        channel.associatedClient = client

        let sheet: UnsafeMutablePointer<TDCChannelModifyTopicSheet>! = TDCChannelModifyTopicSheet(channel: channel)

        XCTAssertEqual(sheet.client, client)
        XCTAssertEqual(sheet.channel, channel)

        XCTAssertEqualObjects(sheet.channelId, channel.uniqueIdentifier)

        XCTAssertNotNil(sheet.sheet)
    }
    @objc
    func testOnboardingStylePreviewViewExposesRadioButtonAccessibility() {
        var view: UnsafeMutablePointer<TDCOnboardingStylePreviewView>! = TDCOnboardingStylePreviewView()

        view.styleTitle = "Bubbles"

        XCTAssertTrue(view.isAccessibilityElement)

        XCTAssertEqualObjects(view.accessibilityRole, NSAccessibilityRadioButtonRole)
        XCTAssertEqualObjects(view.accessibilityLabel, "Bubbles")
        XCTAssertEqualObjects(view.accessibilityValue, false)

        view.selected = true

        XCTAssertEqualObjects(view.accessibilityValue, true)
    }
    @objc
    func testSpokenNotificationResolvesClientTarget() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        let notification: UnsafeMutablePointer<TLOSpokenNotification>! = TLOSpokenNotification(notification: TXNotificationTypeConnect, lineType: TVCLogLineTypeNotice, target: client, nickname: "alice", text: "connected")

        XCTAssertEqual(notification.client, client)

        XCTAssertNil(notification.channel)

        XCTAssertEqual(notification.notificationType, TXNotificationTypeConnect)
        XCTAssertEqual(notification.lineType, TVCLogLineTypeNotice)

        XCTAssertEqualObjects(notification.nickname, "alice")
        XCTAssertEqualObjects(notification.text, "connected")
    }
    @objc
    func testSpokenNotificationResolvesChannelAndItsClient() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        var channel: UnsafeMutablePointer<IRCChannel>! = IRCChannel(configDictionary: ["channelName": "#chat"])

        channel.associatedClient = client

        let notification: UnsafeMutablePointer<TLOSpokenNotification>! = TLOSpokenNotification(notification: TXNotificationTypeChannelMessage, lineType: TVCLogLineTypePrivateMessage, target: channel, nickname: "alice", text: "hello")

        XCTAssertEqual(notification.client, client)
        XCTAssertEqual(notification.channel, channel)
    }
    @objc
    func testPreferredGlobalTableViewFontMatchesLegacySize() {
        let font: UnsafeMutablePointer<NSFont>! = NSTableView.preferredGlobalTableViewFont()

        XCTAssertEqualWithAccuracy(font.pointSize, 13.0, 0.001)
    }
    @objc
    func testFormatterColorsIncludeCanonicalIRCPalette() {
        XCTAssertEqual(NSColor.formatterColors.count, 99)

        XCTAssertEqualObjects(NSColor.formatterWhiteColor, NSColor.formatterColors[0])
        XCTAssertEqualObjects(NSColor.formatterBlackColor, NSColor.formatterColors[1])
        XCTAssertEqualObjects(NSColor.formatterLightGrayColor, NSColor.formatterColors[15])
    }
    @objc
    func testAppearanceNotificationsPropagateToSubviews() {
        let parent: UnsafeMutablePointer<NSView>! = NSView(frame: NSMakeRect(0, 0, 100, 100))
        let child: GLTAppearanceSpyView! = GLTAppearanceSpyView(frame: NSMakeRect(0, 0, 50, 50))

        parent.addSubview(child)
        parent.notifyApplicationAppearanceChanged()
        parent.notifySystemAppearanceChanged()

        XCTAssertEqual(child.applicationAppearanceChangeCount, 1)
        XCTAssertEqual(child.systemAppearanceChangeCount, 1)
    }
    @objc
    func testUnicodeHelperClassifiesCodePoints() {
        XCTAssertTrue(THOUnicodeHelper.isAlphabeticalCodePoint('A'))
        XCTAssertTrue(THOUnicodeHelper.isAlphabeticalCodePoint('z'))

        XCTAssertFalse(THOUnicodeHelper.isAlphabeticalCodePoint('1'))

        XCTAssertTrue(THOUnicodeHelper.isPrivate(0xe010))
        XCTAssertTrue(THOUnicodeHelper.isIdeographic(0x4e00))
        XCTAssertTrue(THOUnicodeHelper.isIdeographicOrPrivate(0xe010))
    }
}