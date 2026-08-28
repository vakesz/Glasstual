/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

private let notificationEvents: [TXNotificationType] = [.highlight, .channelMessage, .kick]

@Suite("Notification configuration checkbox state")
@MainActor
struct NotificationConfigurationStateTests {
	@Test("A channel configuration with no override reads back as mixed", arguments: notificationEvents)
	func channelConfigurationWithoutOverrideIsMixed(event: TXNotificationType) {
		let configuration = ChannelNotificationConfiguration(eventType: event)

		#expect(configuration.speakEvent == .mixed)
		#expect(configuration.pushNotification == .mixed)
		#expect(configuration.disabledWhileAway == .mixed)
		#expect(configuration.bounceDockIcon == .mixed)
		#expect(configuration.bounceDockIconRepeatedly == .mixed)
	}

	/// Every value the checkboxes carry has to survive a trip through the
	/// configuration unchanged — `.mixed` is negative, which is what used to
	/// trap on the way through `UInt`.
	@Test(
		"Every checkbox state assigns to a button without conversion",
		arguments: [NSControl.StateValue.off, .on, .mixed]
	)
	func checkboxStatesRoundTripThroughAButton(state: NSControl.StateValue) {
		let button = NSButton()
		button.setButtonType(.switch)
		button.allowsMixedState = true
		button.state = state

		#expect(button.state == state)
	}

	@Test("Preferences-backed configurations report on or off, never mixed", arguments: notificationEvents)
	func preferencesConfigurationIsNeverMixed(event: TXNotificationType) {
		let configuration = PreferencesNotificationConfiguration.object(withEventType: event)

		#expect(configuration.speakEvent != .mixed)
		#expect(configuration.pushNotification != .mixed)
		#expect(configuration.disabledWhileAway != .mixed)
		#expect(configuration.bounceDockIcon != .mixed)
		#expect(configuration.bounceDockIconRepeatedly != .mixed)
	}

	/// Opening Channel Properties → Notifications for a channel with no
	/// overrides used to abort the process on `Int(UInt.max)`.
	@Test("Showing a mixed-state configuration in the view controller does not trap")
	func viewControllerAcceptsMixedConfigurations() {
		let controller = NotificationConfigurationViewController()
		controller.allowsMixedState = true
		controller.notifications = notificationEvents.map { ChannelNotificationConfiguration(eventType: $0) }
		controller.reload()
	}

	/// `selectedTag()` is -1 once the pop-up's menu has been emptied.
	@Test("Emptying the notification list leaves the view controller usable")
	func viewControllerAcceptsAnEmptyNotificationList() {
		let controller = NotificationConfigurationViewController()
		controller.notifications = [ChannelNotificationConfiguration(eventType: .highlight)]
		controller.notifications = []
		controller.reload()
	}
}
