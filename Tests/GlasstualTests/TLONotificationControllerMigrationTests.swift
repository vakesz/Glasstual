/*  *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Notification controller", .serialized)
struct TLONotificationControllerMigrationTests {
	private func notificationController() -> NotificationController {
		SharedApplication.sharedNotificationController()
	}

	@Test("Every event type has a title to show")
	func titleForEventReturnsLocalizedNonEmptyStrings() {
		let controller = notificationController()

		#expect(controller.title(forEvent: .highlight).isEmpty == false)
		#expect(controller.title(forEvent: .connect).isEmpty == false)
		#expect(controller.title(forEvent: .fileTransferReceiveRequested).isEmpty == false)
		#expect(controller.title(forEvent: .userJoined).isEmpty == false)
	}

	@Test("A thread identifier needs a client, and takes the channel when there is one")
	func threadIdentifierCombinesClientAndChannel() {
		#expect(NotificationController.threadIdentifier(forClient: nil, channel: "chan") == nil)
		#expect(NotificationController.threadIdentifier(forClient: "client-a", channel: nil) == "client-a")
		#expect(
			NotificationController.threadIdentifier(forClient: "client-a", channel: "chan-b") == "client-a-chan-b"
		)
	}

	@Test("A notification without a thread still gets a distinct identifier")
	func notificationIdentifierUsesStableNSStringHashLayout() {
		let title = "Hello"
		let message = "World"
		let thread = "client-channel"
		let expected = String(
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

		#expect(actual == expected)

		let noThreadExpected = String(
			format: "TXNotification-%@-%ld-%ld",
			"<No Thread>",
			(title as NSString).hash,
			(message as NSString).hash
		)

		#expect(
			NotificationController.notificationIdentifier(title: title, message: message, threadIdentifier: nil)
				== noThreadExpected
		)
	}

	@Test("A notification without a channel is in scope only when no channel is asked for")
	func userInfoScopeMatchingTreatsNilChannelsAsEqual() {
		let clientOnly: [AnyHashable: Any] = [NotificationPayload.clientIdentifierKey: "c1"]
		let withChannel: [AnyHashable: Any] = [
			NotificationPayload.clientIdentifierKey: "c1",
			NotificationPayload.channelIdentifierKey: "ch1",
		]

		#expect(NotificationController.isNotification(
			userInfo: clientOnly,
			inScopeOfClientIdentifier: "c1",
			channelIdentifier: nil
		))

		#expect(NotificationController.isNotification(
			userInfo: clientOnly,
			inScopeOfClientIdentifier: "c1",
			channelIdentifier: "ch1"
		) == false)

		#expect(NotificationController.isNotification(
			userInfo: withChannel,
			inScopeOfClientIdentifier: "c1",
			channelIdentifier: "ch1"
		))

		#expect(NotificationController.isNotification(
			userInfo: withChannel,
			inScopeOfClientIdentifier: "c2",
			channelIdentifier: "ch1"
		) == false)
	}

	@Test("A lookup with no channel answers with the global preference")
	func preferenceLookupsWithNilChannelMatchGlobalPreferences() {
		let controller = notificationController()
		let eventType = TXNotificationType.highlight

		#expect(controller.sound(forEvent: eventType, in: nil) == TextualPreferences.sound(for: eventType))
		#expect(controller.speakEvent(eventType, in: nil) == TextualPreferences.speak(eventType))
		#expect(
			controller.notificationEnabled(forEvent: eventType, in: nil)
				== TextualPreferences.notificationEnabled(for: eventType)
		)
		#expect(
			controller.disabledWhileAway(forEvent: eventType, in: nil)
				== TextualPreferences.disabledWhileAway(for: eventType)
		)
		#expect(
			controller.bounceDockIcon(forEvent: eventType, in: nil)
				== TextualPreferences.bounceDockIcon(for: eventType)
		)
		#expect(
			controller.bounceDockIconRepeatedly(forEvent: eventType, in: nil)
				== TextualPreferences.bounceDockIconRepeatedly(for: eventType)
		)
	}

	@Test("Suppressing notifications is a plain toggle")
	func areNotificationsDisabledToggle() {
		let controller = notificationController()
		let original = controller.areNotificationsDisabled
		defer { controller.areNotificationsDisabled = original }

		controller.areNotificationsDisabled = true

		#expect(controller.areNotificationsDisabled)

		controller.areNotificationsDisabled = false

		#expect(controller.areNotificationsDisabled == false)
	}
}
