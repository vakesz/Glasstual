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
}

@objc(TLONotificationConfiguration)
public class NotificationConfiguration: NSObject {
	@objc public private(set) var eventType: TXNotificationType

	@available(*, unavailable)
	override public convenience init() {
		fatalError("Use init(eventType:)")
	}

	@objc(initWithEventType:)
	public required init(eventType: TXNotificationType) {
		self.eventType = eventType

		super.init()
	}

	@objc(configurationWithEventType:)
	public class func configuration(withEventType eventType: TXNotificationType) -> Self {
		self.init(eventType: eventType)
	}

	@objc public static func localizedAlertDefaultSoundTitle() -> String {
		NotificationSoundStrings.defaultSound
	}

	@objc public static func localizedAlertNoSoundTitle() -> String {
		NotificationSoundStrings.noSound
	}

	@MainActor @objc public var displayName: String {
		SharedApplication.sharedNotificationController().title(forEvent: eventType)
	}

	@objc public dynamic var alertSound: String? {
		get { abstractValue(for: "alertSound") }
		set { rejectAbstractSetter(newValue, selectorName: "setAlertSound:") }
	}

	@objc public dynamic var speakEvent: NSControl.StateValue {
		get { abstractValue(for: "speakEvent") }
		set { rejectAbstractSetter(newValue, selectorName: "setSpeakEvent:") }
	}

	@objc public dynamic var pushNotification: NSControl.StateValue {
		get { abstractValue(for: "pushNotification") }
		set { rejectAbstractSetter(newValue, selectorName: "setPushNotification:") }
	}

	@objc public dynamic var disabledWhileAway: NSControl.StateValue {
		get { abstractValue(for: "disabledWhileAway") }
		set { rejectAbstractSetter(newValue, selectorName: "setDisabledWhileAway:") }
	}

	@objc public dynamic var bounceDockIcon: NSControl.StateValue {
		get { abstractValue(for: "bounceDockIcon") }
		set { rejectAbstractSetter(newValue, selectorName: "setBounceDockIcon:") }
	}

	@objc public dynamic var bounceDockIconRepeatedly: NSControl.StateValue {
		get { abstractValue(for: "bounceDockIconRepeatedly") }
		set { rejectAbstractSetter(newValue, selectorName: "setBounceDockIconRepeatedly:") }
	}

	private func abstractValue<Value>(for selectorName: String) -> Value {
		doesNotRecognizeSelector(NSSelectorFromString(selectorName))

		fatalError("Unreachable after doesNotRecognizeSelector")
	}

	private func rejectAbstractSetter(_ value: some Any, selectorName: String) {
		withExtendedLifetime(value) {
			doesNotRecognizeSelector(NSSelectorFromString(selectorName))
		}
	}
}

@objc(TDCPreferencesNotificationConfiguration)
public final class PreferencesNotificationConfiguration: NotificationConfiguration {
	@objc(objectWithEventType:)
	public static func object(withEventType eventType: TXNotificationType) -> PreferencesNotificationConfiguration {
		PreferencesNotificationConfiguration(eventType: eventType)
	}

	override public var alertSound: String? {
		get {
			TextualPreferences.sound(for: eventType)
				?? NotificationAlertSound.noSoundPreferenceValue
		}
		set { TextualPreferences.setSound(newValue, for: eventType) }
	}

	override public var pushNotification: NSControl.StateValue {
		get { TextualPreferences.notificationEnabled(for: eventType) ? .on : .off }
		set { TextualPreferences.setNotificationEnabled(newValue != .off, for: eventType) }
	}

	override public var speakEvent: NSControl.StateValue {
		get { TextualPreferences.speak(eventType) ? .on : .off }
		set { TextualPreferences.setEventIsSpoken(newValue != .off, for: eventType) }
	}

	override public var disabledWhileAway: NSControl.StateValue {
		get { TextualPreferences.disabledWhileAway(for: eventType) ? .on : .off }
		set { TextualPreferences.setDisabledWhileAway(newValue != .off, for: eventType) }
	}

	override public var bounceDockIcon: NSControl.StateValue {
		get { TextualPreferences.bounceDockIcon(for: eventType) ? .on : .off }
		set { TextualPreferences.setBounceDockIcon(newValue != .off, for: eventType) }
	}

	override public var bounceDockIconRepeatedly: NSControl.StateValue {
		get { TextualPreferences.bounceDockIconRepeatedly(for: eventType) ? .on : .off }
		set { TextualPreferences.setBounceDockIconRepeatedly(newValue != .off, for: eventType) }
	}
}

@objc(TDCChannelPropertiesNotificationConfiguration)
public final class ChannelNotificationConfiguration: NotificationConfiguration {
	private weak var sheet: ChannelPropertiesSheet?

	public required init(eventType: TXNotificationType) {
		super.init(eventType: eventType)
	}

	@objc(initWithEventType:inSheet:)
	public init(eventType: TXNotificationType, in sheet: ChannelPropertiesSheet) {
		self.sheet = sheet

		super.init(eventType: eventType)
	}

	override public var alertSound: String? {
		get { config?.sound(forEvent: eventType) }
		set { config?.setSound(newValue, forEvent: eventType) }
	}

	override public var pushNotification: NSControl.StateValue {
		get { config?.notificationEnabled(forEvent: eventType) ?? .mixed }
		set { config?.setNotificationEnabled(newValue, forEvent: eventType) }
	}

	override public var speakEvent: NSControl.StateValue {
		get { config?.speakEvent(eventType) ?? .mixed }
		set { config?.setEventIsSpoken(newValue, forEvent: eventType) }
	}

	override public var disabledWhileAway: NSControl.StateValue {
		get { config?.disabledWhileAway(forEvent: eventType) ?? .mixed }
		set { config?.setDisabledWhileAway(newValue, forEvent: eventType) }
	}

	override public var bounceDockIcon: NSControl.StateValue {
		get { config?.bounceDockIcon(forEvent: eventType) ?? .mixed }
		set { config?.setBounceDockIcon(newValue, forEvent: eventType) }
	}

	override public var bounceDockIconRepeatedly: NSControl.StateValue {
		get { config?.bounceDockIconRepeatedly(forEvent: eventType) ?? .mixed }
		set { config?.setBounceDockIconRepeatedly(newValue, forEvent: eventType) }
	}

	/// A nil config (the sheet is gone) reads back as `.mixed`: the neutral
	/// value the checkbox already understands, and the default for a channel
	/// that carries no override of its own.
	private var config: MutableChannelConfig? {
		sheet?.config
	}
}
