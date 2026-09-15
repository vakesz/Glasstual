/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

/** How one notification event is configured for one channel.

 A channel's override wins when it has one. `.inherited` means the channel has
 no override, so the application-wide preference answers. */
enum NotificationEventSettings {
	static func sound(for event: NotificationEvent, in channel: Channel?) -> String? {
		if let channel, let channelValue = channel.config.sound(forEvent: event) {
			return channelValue
		}

		return Preferences.Notifications.sound(event).storedValue
	}

	static func speaks(_ event: NotificationEvent, in channel: Channel?) -> Bool {
		resolve(event, in: channel, setting: .speak) { $0.speakEvent($1) }
	}

	static func isEnabled(_ event: NotificationEvent, in channel: Channel?) -> Bool {
		resolve(event, in: channel, setting: .enabled) { $0.notificationEnabled(forEvent: $1) }
	}

	static func isDisabledWhileAway(_ event: NotificationEvent, in channel: Channel?) -> Bool {
		resolve(event, in: channel, setting: .disabledWhileAway) { $0.disabledWhileAway(forEvent: $1) }
	}

	static func bouncesDockIcon(for event: NotificationEvent, in channel: Channel?) -> Bool {
		resolve(event, in: channel, setting: .bounceDockIcon) { $0.bounceDockIcon(forEvent: $1) }
	}

	static func bouncesDockIconRepeatedly(for event: NotificationEvent, in channel: Channel?) -> Bool {
		resolve(event, in: channel, setting: .bounceDockIconRepeatedly) {
			$0.bounceDockIconRepeatedly(forEvent: $1)
		}
	}

	private static func resolve(
		_ event: NotificationEvent,
		in channel: Channel?,
		setting: NotificationSetting,
		channelValue: (ChannelConfig, NotificationEvent) -> ChannelEventOverride
	) -> Bool {
		if let channel {
			switch channelValue(channel.config, event) {
			case .on: return true
			case .off: return false
			case .inherited: break
			}
		}

		return Preferences.Notifications.flag(event, setting).value
	}
}
