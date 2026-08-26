@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "TLONotificationControllerPrivate.h"
/// #import "TPCPreferencesLocal.h"
/// #import "TXSharedApplicationPrivate.h"
/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@MainActor
@objc
class TLONotificationControllerMigrationTests: XCTestCase {
	@objc
	func controller() -> NotificationController {
		SharedApplication.sharedNotificationController()
	}

	@objc
	func testTitleForEventReturnsLocalizedNonEmptyStrings() {
		let controller = controller()

		XCTAssertFalse(controller.title(forEvent: .highlight).isEmpty)
		XCTAssertFalse(controller.title(forEvent: .connect).isEmpty)
		XCTAssertFalse(controller.title(forEvent: .fileTransferReceiveRequested).isEmpty)
		XCTAssertFalse(controller.title(forEvent: .userJoined).isEmpty)
	}

	@objc
	func testThreadIdentifierCombinesClientAndChannel() {
		XCTAssertNil(NotificationController.threadIdentifier(forClient: nil, channel: "chan"))
		XCTAssertEqual(NotificationController.threadIdentifier(forClient: "client-a", channel: nil), "client-a")
		XCTAssertEqual(
			NotificationController.threadIdentifier(forClient: "client-a", channel: "chan-b"),
			"client-a-chan-b"
		)
	}

	@objc
	func testNotificationIdentifierUsesStableNSStringHashLayout() {
		let title = "Hello"
		let message = "World"
		let thread = "client-channel"
		let expected: String! = String(
			format: "TXNotification-%@-%ld-%ld",
			thread,
			(title as NSString).hash,
			(message as NSString).hash
		)
		let actual = NotificationController.notificationIdentifier(
			title: title,
			message: message,
			threadIdentifier: thread
		)

		XCTAssertEqual(actual, expected)

		let noThreadExpected: String! = String(
			format: "TXNotification-%@-%ld-%ld",
			"<No Thread>",
			(title as NSString).hash,
			(message as NSString).hash
		)

		XCTAssertEqual(
			NotificationController.notificationIdentifier(title: title, message: message, threadIdentifier: nil),
			noThreadExpected
		)
	}

	@objc
	func testUserInfoScopeMatchingTreatsNilChannelsAsEqual() {
		let clientOnly: [AnyHashable: Any] = [TXNotificationUserInfoClientIdentifierKey: "c1"]
		let withChannel: [AnyHashable: Any] = [
			TXNotificationUserInfoClientIdentifierKey: "c1",
			TXNotificationUserInfoChannelIdentifierKey: "ch1",
		]

		XCTAssertTrue(NotificationController.isNotification(
			userInfo: clientOnly,
			inScopeOfClientIdentifier: "c1",
			channelIdentifier: nil
		))

		XCTAssertFalse(NotificationController.isNotification(
			userInfo: clientOnly,
			inScopeOfClientIdentifier: "c1",
			channelIdentifier: "ch1"
		))

		XCTAssertTrue(NotificationController.isNotification(
			userInfo: withChannel,
			inScopeOfClientIdentifier: "c1",
			channelIdentifier: "ch1"
		))

		XCTAssertFalse(NotificationController.isNotification(
			userInfo: withChannel,
			inScopeOfClientIdentifier: "c2",
			channelIdentifier: "ch1"
		))
	}

	@objc
	func testPublicFormatConstantsRemainStable() {
		XCTAssertEqual(TXNotificationUserInfoClientIdentifierKey, "clientId")
		XCTAssertEqual(TXNotificationUserInfoChannelIdentifierKey, "channelId")
		XCTAssertEqual(TXNotificationDialogStandardNicknameFormat, "%@ %@")
		XCTAssertEqual(TXNotificationDialogActionNicknameFormat, "• %@: %@")
		XCTAssertEqual(TXNotificationHighlightLogStandardActionFormat, "• %@: %@")
		XCTAssertEqual(TXNotificationHighlightLogStandardMessageFormat, "%@ %@")
	}

	@objc
	func testPreferenceLookupsWithNilChannelMatchGlobalPreferences() {
		let controller = controller()
		let eventType = TXNotificationType.highlight

		XCTAssertEqual(controller.sound(forEvent: eventType, in: nil), TPCPreferences.sound(forEvent: eventType))

		XCTAssertEqual(controller.speakEvent(eventType, in: nil), TPCPreferences.speakEvent(eventType))
		XCTAssertEqual(
			controller.notificationEnabled(forEvent: eventType, in: nil),
			TPCPreferences.notificationEnabled(forEvent: eventType)
		)
		XCTAssertEqual(
			controller.disabledWhileAway(forEvent: eventType, in: nil),
			TPCPreferences.disabledWhileAway(forEvent: eventType)
		)
		XCTAssertEqual(
			controller.bounceDockIcon(forEvent: eventType, in: nil),
			TPCPreferences.bounceDockIcon(forEvent: eventType)
		)
		XCTAssertEqual(
			controller.bounceDockIconRepeatedly(forEvent: eventType, in: nil),
			TPCPreferences.bounceDockIconRepeatedly(forEvent: eventType)
		)
	}

	@objc
	func testAreNotificationsDisabledToggle() {
		let controller = controller()
		let original: Bool = controller.areNotificationsDisabled

		controller.areNotificationsDisabled = true

		XCTAssertTrue(controller.areNotificationsDisabled)

		controller.areNotificationsDisabled = false

		XCTAssertFalse(controller.areNotificationsDisabled)

		controller.areNotificationsDisabled = original
	}
}
