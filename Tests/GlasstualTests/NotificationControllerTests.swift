/*  *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Notification controller", .serialized)
struct NotificationControllerTests {
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

	/** The flags are written as an alternating pattern first. Comparing each
	 lookup against the key it is meant to read passes for a lookup wired to the
	 wrong key whenever the two keys agree, which at the shipped defaults they
	 do for every boolean pair here. */
	@Test("A lookup with no channel answers with the global preference")
	func preferenceLookupsWithNilChannelMatchGlobalPreferences() {
		let controller = notificationController()
		let eventType = NotificationEvent.highlight
		let sound = Preferences.Notifications.sound(eventType)
		let flags: [NotificationSetting] = [
			.enabled, .speak, .disabledWhileAway, .bounceDockIcon, .bounceDockIconRepeatedly,
		]
		let storedSound = sound.storedValue
		let storedFlags = flags.map { Preferences.Notifications.flag(eventType, $0).storedValue }
		defer {
			sound.storedValue = storedSound
			for (flag, stored) in zip(flags, storedFlags) {
				Preferences.Notifications.flag(eventType, flag).storedValue = stored
			}
		}

		sound.value = "Glass"
		for (offset, flag) in flags.enumerated() {
			Preferences.Notifications.flag(eventType, flag).value = offset.isMultiple(of: 2)
		}

		#expect(controller.sound(forEvent: eventType, in: nil) == "Glass")
		#expect(controller.notificationEnabled(forEvent: eventType, in: nil))
		#expect(controller.speakEvent(eventType, in: nil) == false)
		#expect(controller.disabledWhileAway(forEvent: eventType, in: nil))
		#expect(controller.bounceDockIcon(forEvent: eventType, in: nil) == false)
		#expect(controller.bounceDockIconRepeatedly(forEvent: eventType, in: nil))
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
