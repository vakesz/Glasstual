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

	@objc public dynamic var speakEvent: UInt {
		get { abstractValue(for: "speakEvent") }
		set { rejectAbstractSetter(newValue, selectorName: "setSpeakEvent:") }
	}

	@objc public dynamic var pushNotification: UInt {
		get { abstractValue(for: "pushNotification") }
		set { rejectAbstractSetter(newValue, selectorName: "setPushNotification:") }
	}

	@objc public dynamic var disabledWhileAway: UInt {
		get { abstractValue(for: "disabledWhileAway") }
		set { rejectAbstractSetter(newValue, selectorName: "setDisabledWhileAway:") }
	}

	@objc public dynamic var bounceDockIcon: UInt {
		get { abstractValue(for: "bounceDockIcon") }
		set { rejectAbstractSetter(newValue, selectorName: "setBounceDockIcon:") }
	}

	@objc public dynamic var bounceDockIconRepeatedly: UInt {
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

	override public var pushNotification: UInt {
		get { TextualPreferences.notificationEnabled(for: eventType) ? 1 : 0 }
		set { TextualPreferences.setNotificationEnabled(newValue != 0, for: eventType) }
	}

	override public var speakEvent: UInt {
		get { TextualPreferences.speak(eventType) ? 1 : 0 }
		set { TextualPreferences.setEventIsSpoken(newValue != 0, for: eventType) }
	}

	override public var disabledWhileAway: UInt {
		get { TextualPreferences.disabledWhileAway(for: eventType) ? 1 : 0 }
		set { TextualPreferences.setDisabledWhileAway(newValue != 0, for: eventType) }
	}

	override public var bounceDockIcon: UInt {
		get { TextualPreferences.bounceDockIcon(for: eventType) ? 1 : 0 }
		set { TextualPreferences.setBounceDockIcon(newValue != 0, for: eventType) }
	}

	override public var bounceDockIconRepeatedly: UInt {
		get { TextualPreferences.bounceDockIconRepeatedly(for: eventType) ? 1 : 0 }
		set { TextualPreferences.setBounceDockIconRepeatedly(newValue != 0, for: eventType) }
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

	override public var pushNotification: UInt {
		get { unsignedValue(config?.notificationEnabled(forEvent: eventType)) }
		set { config?.setNotificationEnabled(controlState(from: newValue), forEvent: eventType) }
	}

	override public var speakEvent: UInt {
		get { unsignedValue(config?.speakEvent(eventType)) }
		set { config?.setEventIsSpoken(controlState(from: newValue), forEvent: eventType) }
	}

	override public var disabledWhileAway: UInt {
		get { unsignedValue(config?.disabledWhileAway(forEvent: eventType)) }
		set { config?.setDisabledWhileAway(controlState(from: newValue), forEvent: eventType) }
	}

	override public var bounceDockIcon: UInt {
		get { unsignedValue(config?.bounceDockIcon(forEvent: eventType)) }
		set { config?.setBounceDockIcon(controlState(from: newValue), forEvent: eventType) }
	}

	override public var bounceDockIconRepeatedly: UInt {
		get { unsignedValue(config?.bounceDockIconRepeatedly(forEvent: eventType)) }
		set { config?.setBounceDockIconRepeatedly(controlState(from: newValue), forEvent: eventType) }
	}

	private var config: MutableChannelConfig? {
		sheet?.config
	}

	private func unsignedValue(_ state: NSControl.StateValue?) -> UInt {
		guard let state else {
			return 0
		}

		return UInt(bitPattern: state.rawValue)
	}

	private func controlState(from value: UInt) -> NSControl.StateValue {
		NSControl.StateValue(rawValue: Int(bitPattern: value))
	}
}
