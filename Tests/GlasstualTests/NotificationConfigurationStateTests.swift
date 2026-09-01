/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

@testable import Glasstual
import Testing

private nonisolated let notificationEvents: [NotificationEvent] = [.highlight, .channelMessage, .kick]

@Suite("Notification configuration checkbox state")
@MainActor
struct NotificationConfigurationStateTests {
	@Test("A channel configuration with no override reads back as inherited", arguments: notificationEvents)
	func channelConfigurationWithoutOverrideIsInherited(event: NotificationEvent) {
		let configuration = ChannelNotificationConfiguration(eventType: event)

		#expect(configuration.speakEvent == .inherited)
		#expect(configuration.pushNotification == .inherited)
		#expect(configuration.disabledWhileAway == .inherited)
		#expect(configuration.bounceDockIcon == .inherited)
		#expect(configuration.bounceDockIconRepeatedly == .inherited)
	}

	@Test("Every override state round trips through channel configuration", arguments: ChannelEventOverride.allCases)
	func overrideStatesRoundTrip(state: ChannelEventOverride) {
		var config = ChannelConfig()
		config.setNotificationEnabled(state, forEvent: .highlight)

		#expect(config.notificationEnabled(forEvent: .highlight) == state)
	}

	@Test("Preferences-backed configurations report on or off, never inherited", arguments: notificationEvents)
	func preferencesConfigurationIsNeverInherited(event: NotificationEvent) {
		let configuration = PreferencesNotificationConfiguration(eventType: event)

		#expect(configuration.speakEvent != .inherited)
		#expect(configuration.pushNotification != .inherited)
		#expect(configuration.disabledWhileAway != .inherited)
		#expect(configuration.bounceDockIcon != .inherited)
		#expect(configuration.bounceDockIconRepeatedly != .inherited)
	}
}
