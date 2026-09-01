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

public enum NotificationAlertSound {
	public static let defaultPreferenceValue = "Default"
	public static let noSoundPreferenceValue = "None"

	@MainActor public static var localizedDefaultTitle: String {
		NotificationSoundStrings.defaultSound
	}

	@MainActor public static var localizedNoSoundTitle: String {
		NotificationSoundStrings.noSound
	}
}

/// One notification event's settings, as the notification pane edits them.
/// This used to be a class whose every accessor called
/// `doesNotRecognizeSelector` so that the two real implementations had to
/// override it; the compiler enforces that now.
@MainActor
public protocol NotificationConfiguration: AnyObject {
	var eventType: TXNotificationType { get }
	var alertSound: String? { get set }
	var speakEvent: ChannelEventOverride { get set }
	var pushNotification: ChannelEventOverride { get set }
	var disabledWhileAway: ChannelEventOverride { get set }
	var bounceDockIcon: ChannelEventOverride { get set }
	var bounceDockIconRepeatedly: ChannelEventOverride { get set }
}

public extension NotificationConfiguration {
	var displayName: String {
		SharedApplication.sharedNotificationController().title(forEvent: eventType)
	}
}

/// An entry in the notification pane's event list: either an event or the
/// separator that groups them.
@MainActor
public enum NotificationConfigurationItem {
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
public final class PreferencesNotificationConfiguration: NotificationConfiguration {
	public let eventType: TXNotificationType

	public init(eventType: TXNotificationType) {
		self.eventType = eventType
	}

	public var alertSound: String? {
		get {
			Preferences.Notifications.sound(eventType).storedValue
				?? NotificationAlertSound.noSoundPreferenceValue
		}
		set { Preferences.Notifications.sound(eventType).storedValue = newValue }
	}

	public var pushNotification: ChannelEventOverride {
		get { Preferences.Notifications.flag(eventType, .enabled).value ? .on : .off }
		set { Preferences.Notifications.flag(eventType, .enabled).value = newValue == .on }
	}

	public var speakEvent: ChannelEventOverride {
		get { Preferences.Notifications.flag(eventType, .speak).value ? .on : .off }
		set { Preferences.Notifications.flag(eventType, .speak).value = newValue == .on }
	}

	public var disabledWhileAway: ChannelEventOverride {
		get { Preferences.Notifications.flag(eventType, .disabledWhileAway).value ? .on : .off }
		set { Preferences.Notifications.flag(eventType, .disabledWhileAway).value = newValue == .on }
	}

	public var bounceDockIcon: ChannelEventOverride {
		get { Preferences.Notifications.flag(eventType, .bounceDockIcon).value ? .on : .off }
		set { Preferences.Notifications.flag(eventType, .bounceDockIcon).value = newValue == .on }
	}

	public var bounceDockIconRepeatedly: ChannelEventOverride {
		get { Preferences.Notifications.flag(eventType, .bounceDockIconRepeatedly).value ? .on : .off }
		set { Preferences.Notifications.flag(eventType, .bounceDockIconRepeatedly).value = newValue == .on }
	}
}

/// One channel's override of the application-wide settings.
@MainActor
public final class ChannelNotificationConfiguration: NotificationConfiguration {
	public let eventType: TXNotificationType

	private weak var sheet: ChannelPropertiesSheet?

	public init(eventType: TXNotificationType) {
		self.eventType = eventType
	}

	public init(eventType: TXNotificationType, in sheet: ChannelPropertiesSheet) {
		self.eventType = eventType
		self.sheet = sheet
	}

	public var alertSound: String? {
		get { config?.sound(forEvent: eventType) }
		set { sheet?.config.setSound(newValue, forEvent: eventType) }
	}

	public var pushNotification: ChannelEventOverride {
		get { config?.notificationEnabled(forEvent: eventType) ?? .inherited }
		set { sheet?.config.setNotificationEnabled(newValue, forEvent: eventType) }
	}

	public var speakEvent: ChannelEventOverride {
		get { config?.speakEvent(eventType) ?? .inherited }
		set { sheet?.config.setEventIsSpoken(newValue, forEvent: eventType) }
	}

	public var disabledWhileAway: ChannelEventOverride {
		get { config?.disabledWhileAway(forEvent: eventType) ?? .inherited }
		set { sheet?.config.setDisabledWhileAway(newValue, forEvent: eventType) }
	}

	public var bounceDockIcon: ChannelEventOverride {
		get { config?.bounceDockIcon(forEvent: eventType) ?? .inherited }
		set { sheet?.config.setBounceDockIcon(newValue, forEvent: eventType) }
	}

	public var bounceDockIconRepeatedly: ChannelEventOverride {
		get { config?.bounceDockIconRepeatedly(forEvent: eventType) ?? .inherited }
		set { sheet?.config.setBounceDockIconRepeatedly(newValue, forEvent: eventType) }
	}

	/// A nil config (the sheet is gone) reads back as `.inherited`: the neutral
	/// value the checkbox already understands, and the default for a channel
	/// that carries no override of its own.
	private var config: ChannelConfig? {
		sheet?.config
	}
}
