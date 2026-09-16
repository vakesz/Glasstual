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

enum NotificationAlertSound {
	static let noSoundPreferenceValue = "None"

	@MainActor static var localizedDefaultTitle: String {
		NotificationSoundStrings.defaultSound
	}

	@MainActor static var localizedNoSoundTitle: String {
		NotificationSoundStrings.noSound
	}
}

/// One notification event's settings, as the notification pane edits them.
/// This used to be a class whose every accessor called
/// `doesNotRecognizeSelector` so that the two real implementations had to
/// override it; the compiler enforces that now.
@MainActor
protocol NotificationConfiguration: AnyObject {
	var eventType: NotificationEvent { get }
	var alertSound: String? { get set }
	var speakEvent: ChannelEventOverride { get set }
	var pushNotification: ChannelEventOverride { get set }
	var disabledWhileAway: ChannelEventOverride { get set }
	var bounceDockIcon: ChannelEventOverride { get set }
	var bounceDockIconRepeatedly: ChannelEventOverride { get set }
}

extension NotificationConfiguration {
	var displayName: String {
		NotificationStrings.eventTypeTitle(for: eventType)
	}
}

/// An entry in the notification pane's event list: either an event or the
/// separator that groups them.
@MainActor
enum NotificationConfigurationItem {
	case configuration(any NotificationConfiguration)
	case separator

	var configuration: (any NotificationConfiguration)? {
		switch self {
		case let .configuration(configuration): configuration
		case .separator: nil
		}
	}
}

/// The application-wide settings for an event.
@MainActor
final class PreferencesNotificationConfiguration: NotificationConfiguration {
	let eventType: NotificationEvent

	init(eventType: NotificationEvent) {
		self.eventType = eventType
	}

	/// `nil` is the picker's "Default" row: no sound has been chosen for this
	/// event. Substituting "None" for it made "Default" unreachable — picking it
	/// stored `nil`, and the next read turned that straight back into "None".
	var alertSound: String? {
		get { Preferences.Notifications.sound(eventType).storedValue }
		set { Preferences.Notifications.sound(eventType).storedValue = newValue }
	}

	var pushNotification: ChannelEventOverride {
		get { Preferences.Notifications.flag(eventType, .enabled).value ? .on : .off }
		set { Preferences.Notifications.flag(eventType, .enabled).value = newValue == .on }
	}

	var speakEvent: ChannelEventOverride {
		get { Preferences.Notifications.flag(eventType, .speak).value ? .on : .off }
		set { Preferences.Notifications.flag(eventType, .speak).value = newValue == .on }
	}

	var disabledWhileAway: ChannelEventOverride {
		get { Preferences.Notifications.flag(eventType, .disabledWhileAway).value ? .on : .off }
		set { Preferences.Notifications.flag(eventType, .disabledWhileAway).value = newValue == .on }
	}

	var bounceDockIcon: ChannelEventOverride {
		get { Preferences.Notifications.flag(eventType, .bounceDockIcon).value ? .on : .off }
		set { Preferences.Notifications.flag(eventType, .bounceDockIcon).value = newValue == .on }
	}

	var bounceDockIconRepeatedly: ChannelEventOverride {
		get { Preferences.Notifications.flag(eventType, .bounceDockIconRepeatedly).value ? .on : .off }
		set { Preferences.Notifications.flag(eventType, .bounceDockIconRepeatedly).value = newValue == .on }
	}
}

/// One channel's override of the application-wide settings.
@MainActor
final class ChannelNotificationConfiguration: NotificationConfiguration {
	let eventType: NotificationEvent

	private weak var channel: ChannelPropertiesModel?

	init(eventType: NotificationEvent, in channel: ChannelPropertiesModel) {
		self.eventType = eventType
		self.channel = channel
	}

	var alertSound: String? {
		get { config?.sound(forEvent: eventType) }
		set { channel?.config.setSound(newValue, forEvent: eventType) }
	}

	var pushNotification: ChannelEventOverride {
		get { config?.notificationEnabled(forEvent: eventType) ?? .inherited }
		set { channel?.config.setNotificationEnabled(newValue, forEvent: eventType) }
	}

	var speakEvent: ChannelEventOverride {
		get { config?.speakEvent(eventType) ?? .inherited }
		set { channel?.config.setEventIsSpoken(newValue, forEvent: eventType) }
	}

	var disabledWhileAway: ChannelEventOverride {
		get { config?.disabledWhileAway(forEvent: eventType) ?? .inherited }
		set { channel?.config.setDisabledWhileAway(newValue, forEvent: eventType) }
	}

	var bounceDockIcon: ChannelEventOverride {
		get { config?.bounceDockIcon(forEvent: eventType) ?? .inherited }
		set { channel?.config.setBounceDockIcon(newValue, forEvent: eventType) }
	}

	var bounceDockIconRepeatedly: ChannelEventOverride {
		get { config?.bounceDockIconRepeatedly(forEvent: eventType) ?? .inherited }
		set { channel?.config.setBounceDockIconRepeatedly(newValue, forEvent: eventType) }
	}

	/// A nil config, once the channel's editor is gone, reads back as
	/// `.inherited`. The picker already shows that value, and it is what a
	/// channel with no override of its own carries.
	private var config: ChannelConfig? {
		channel?.config
	}
}
