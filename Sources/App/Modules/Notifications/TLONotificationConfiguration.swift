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
	var speakEvent: NSControl.StateValue { get set }
	var pushNotification: NSControl.StateValue { get set }
	var disabledWhileAway: NSControl.StateValue { get set }
	var bounceDockIcon: NSControl.StateValue { get set }
	var bounceDockIconRepeatedly: NSControl.StateValue { get set }
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
			TextualPreferences.sound(for: eventType)
				?? NotificationAlertSound.noSoundPreferenceValue
		}
		set { TextualPreferences.setSound(newValue, for: eventType) }
	}

	public var pushNotification: NSControl.StateValue {
		get { TextualPreferences.notificationEnabled(for: eventType) ? .on : .off }
		set { TextualPreferences.setNotificationEnabled(newValue != .off, for: eventType) }
	}

	public var speakEvent: NSControl.StateValue {
		get { TextualPreferences.speak(eventType) ? .on : .off }
		set { TextualPreferences.setEventIsSpoken(newValue != .off, for: eventType) }
	}

	public var disabledWhileAway: NSControl.StateValue {
		get { TextualPreferences.disabledWhileAway(for: eventType) ? .on : .off }
		set { TextualPreferences.setDisabledWhileAway(newValue != .off, for: eventType) }
	}

	public var bounceDockIcon: NSControl.StateValue {
		get { TextualPreferences.bounceDockIcon(for: eventType) ? .on : .off }
		set { TextualPreferences.setBounceDockIcon(newValue != .off, for: eventType) }
	}

	public var bounceDockIconRepeatedly: NSControl.StateValue {
		get { TextualPreferences.bounceDockIconRepeatedly(for: eventType) ? .on : .off }
		set { TextualPreferences.setBounceDockIconRepeatedly(newValue != .off, for: eventType) }
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

	public var pushNotification: NSControl.StateValue {
		get { config?.notificationEnabled(forEvent: eventType) ?? .mixed }
		set { sheet?.config.setNotificationEnabled(newValue, forEvent: eventType) }
	}

	public var speakEvent: NSControl.StateValue {
		get { config?.speakEvent(eventType) ?? .mixed }
		set { sheet?.config.setEventIsSpoken(newValue, forEvent: eventType) }
	}

	public var disabledWhileAway: NSControl.StateValue {
		get { config?.disabledWhileAway(forEvent: eventType) ?? .mixed }
		set { sheet?.config.setDisabledWhileAway(newValue, forEvent: eventType) }
	}

	public var bounceDockIcon: NSControl.StateValue {
		get { config?.bounceDockIcon(forEvent: eventType) ?? .mixed }
		set { sheet?.config.setBounceDockIcon(newValue, forEvent: eventType) }
	}

	public var bounceDockIconRepeatedly: NSControl.StateValue {
		get { config?.bounceDockIconRepeatedly(forEvent: eventType) ?? .mixed }
		set { sheet?.config.setBounceDockIconRepeatedly(newValue, forEvent: eventType) }
	}

	/// A nil config (the sheet is gone) reads back as `.mixed`: the neutral
	/// value the checkbox already understands, and the default for a channel
	/// that carries no override of its own.
	private var config: ChannelConfig? {
		sheet?.config
	}
}
