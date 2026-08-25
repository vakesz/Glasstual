import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "TLONotificationControllerPrivate.h"
// #import "TPCPreferencesLocal.h"
// #import "TXSharedApplicationPrivate.h"
/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class TLONotificationControllerMigrationTests: XCTestCase {
    @objc
    func controller() -> UnsafeMutablePointer<TLONotificationController> {
        return TXSharedApplication.sharedNotificationController
    }
    @objc
    func testTitleForEventReturnsLocalizedNonEmptyStrings() {
        let controller: UnsafeMutablePointer<TLONotificationController> = self.controller

        XCTAssertGreaterThan(controller.titleForEvent(TXNotificationTypeHighlight).length, 0)
        XCTAssertGreaterThan(controller.titleForEvent(TXNotificationTypeConnect).length, 0)
        XCTAssertGreaterThan(controller.titleForEvent(TXNotificationTypeFileTransferReceiveRequested).length, 0)
        XCTAssertGreaterThan(controller.titleForEvent(TXNotificationTypeUserJoined).length, 0)
    }
    @objc
    func testThreadIdentifierCombinesClientAndChannel() {
        XCTAssertNil(TLONotificationController.threadIdentifierForClient(nil, channel: "chan"))
        XCTAssertEqualObjects(TLONotificationController.threadIdentifierForClient("client-a", channel: nil), "client-a")
        XCTAssertEqualObjects(TLONotificationController.threadIdentifierForClient("client-a", channel: "chan-b"), "client-a-chan-b")
    }
    @objc
    func testNotificationIdentifierUsesStableNSStringHashLayout() {
        let title = "Hello"
        let message = "World"
        let thread = "client-channel"
        let expected: String! = String(format: "TXNotification-%@-%ld-%ld", thread, title.hash, message.hash)
        let actual: String! = TLONotificationController.notificationIdentifierWithTitle(title, message: message, threadIdentifier: thread)

        XCTAssertEqualObjects(actual, expected)

        let noThreadExpected: String! = String(format: "TXNotification-%@-%ld-%ld", "<No Thread>", title.hash, message.hash)

        XCTAssertEqualObjects(TLONotificationController.notificationIdentifierWithTitle(title, message: message, threadIdentifier: nil), noThreadExpected)
    }
    @objc
    func testUserInfoScopeMatchingTreatsNilChannelsAsEqual() {
        let clientOnly: NSDictionary! = [TXNotificationUserInfoClientIdentifierKey: "c1"]
        let withChannel: NSDictionary! = [TXNotificationUserInfoClientIdentifierKey: "c1", TXNotificationUserInfoChannelIdentifierKey: "ch1"]

        XCTAssertTrue(TLONotificationController.userInfo(clientOnly, isInScopeOfClientIdentifier: "c1", channelIdentifier: nil))

        XCTAssertFalse(TLONotificationController.userInfo(clientOnly, isInScopeOfClientIdentifier: "c1", channelIdentifier: "ch1"))

        XCTAssertTrue(TLONotificationController.userInfo(withChannel, isInScopeOfClientIdentifier: "c1", channelIdentifier: "ch1"))

        XCTAssertFalse(TLONotificationController.userInfo(withChannel, isInScopeOfClientIdentifier: "c2", channelIdentifier: "ch1"))
    }
    @objc
    func testPublicFormatConstantsRemainStable() {
        XCTAssertEqualObjects(TXNotificationUserInfoClientIdentifierKey, "clientId")
        XCTAssertEqualObjects(TXNotificationUserInfoChannelIdentifierKey, "channelId")
        XCTAssertEqualObjects(TXNotificationDialogStandardNicknameFormat, "%@ %@")
        XCTAssertEqualObjects(TXNotificationDialogActionNicknameFormat, "\\u2022 %@: %@")
        XCTAssertEqualObjects(TXNotificationHighlightLogStandardActionFormat, "\\u2022 %@: %@")
        XCTAssertEqualObjects(TXNotificationHighlightLogStandardMessageFormat, "%@ %@")
    }
    @objc
    func testPreferenceLookupsWithNilChannelMatchGlobalPreferences() {
        let controller: UnsafeMutablePointer<TLONotificationController> = self.controller
        let eventType: TXNotificationType = TXNotificationTypeHighlight

        XCTAssertEqualObjects(controller.soundForEvent(eventType, inChannel: nil), TPCPreferences.soundForEvent(eventType))

        XCTAssertEqual(controller.speakEvent(eventType, inChannel: nil), TPCPreferences.speakEvent(eventType))
        XCTAssertEqual(controller.notificationEnabledForEvent(eventType, inChannel: nil), TPCPreferences.notificationEnabledForEvent(eventType))
        XCTAssertEqual(controller.disabledWhileAwayForEvent(eventType, inChannel: nil), TPCPreferences.disabledWhileAwayForEvent(eventType))
        XCTAssertEqual(controller.bounceDockIconForEvent(eventType, inChannel: nil), TPCPreferences.bounceDockIconForEvent(eventType))
        XCTAssertEqual(controller.bounceDockIconRepeatedlyForEvent(eventType, inChannel: nil), TPCPreferences.bounceDockIconRepeatedlyForEvent(eventType))
    }
    @objc
    func testAreNotificationsDisabledToggle() {
        var controller: UnsafeMutablePointer<TLONotificationController> = self.controller
        let original: Bool = controller.areNotificationsDisabled

        controller.areNotificationsDisabled = true

        XCTAssertTrue(controller.areNotificationsDisabled)

        controller.areNotificationsDisabled = false

        XCTAssertFalse(controller.areNotificationsDisabled)

        controller.areNotificationsDisabled = original
    }
}