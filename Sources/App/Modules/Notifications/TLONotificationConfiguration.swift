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
		LocalizedKey("TVCNotificationConfigurationView[0rs-8l]")
	}

	@objc public static func localizedAlertNoSoundTitle() -> String {
		LocalizedKey("TVCNotificationConfigurationView[vje-9n]")
	}

	@objc public var displayName: String {
		TXSharedApplication.sharedNotificationController().title(forEvent: eventType)
	}

	@objc public var alertSound: String? {
		get { abstractValue(for: "alertSound") }
		set { doesNotRecognizeSelector(NSSelectorFromString("setAlertSound:")) }
	}

	@objc public var speakEvent: UInt {
		get { abstractValue(for: "speakEvent") }
		set { doesNotRecognizeSelector(NSSelectorFromString("setSpeakEvent:")) }
	}

	@objc public var pushNotification: UInt {
		get { abstractValue(for: "pushNotification") }
		set { doesNotRecognizeSelector(NSSelectorFromString("setPushNotification:")) }
	}

	@objc public var disabledWhileAway: UInt {
		get { abstractValue(for: "disabledWhileAway") }
		set { doesNotRecognizeSelector(NSSelectorFromString("setDisabledWhileAway:")) }
	}

	@objc public var bounceDockIcon: UInt {
		get { abstractValue(for: "bounceDockIcon") }
		set { doesNotRecognizeSelector(NSSelectorFromString("setBounceDockIcon:")) }
	}

	@objc public var bounceDockIconRepeatedly: UInt {
		get { abstractValue(for: "bounceDockIconRepeatedly") }
		set { doesNotRecognizeSelector(NSSelectorFromString("setBounceDockIconRepeatedly:")) }
	}

	private func abstractValue<Value>(for selectorName: String) -> Value {
		doesNotRecognizeSelector(NSSelectorFromString(selectorName))

		fatalError("Unreachable after doesNotRecognizeSelector")
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
			TPCPreferences.sound(forEvent: eventType)
				?? TLONotificationAlertSound.TXNoAlertSoundPreferenceValue.rawValue
		}
		set { TPCPreferences.setSound(newValue, forEvent: eventType) }
	}

	override public var pushNotification: UInt {
		get { TPCPreferences.notificationEnabled(forEvent: eventType) ? 1 : 0 }
		set { TPCPreferences.setNotificationEnabled(newValue != 0, forEvent: eventType) }
	}

	override public var speakEvent: UInt {
		get { TPCPreferences.speakEvent(eventType) ? 1 : 0 }
		set { TPCPreferences.setEventIsSpoken(newValue != 0, forEvent: eventType) }
	}

	override public var disabledWhileAway: UInt {
		get { TPCPreferences.disabledWhileAway(forEvent: eventType) ? 1 : 0 }
		set { TPCPreferences.setDisabledWhileAway(newValue != 0, forEvent: eventType) }
	}

	override public var bounceDockIcon: UInt {
		get { TPCPreferences.bounceDockIcon(forEvent: eventType) ? 1 : 0 }
		set { TPCPreferences.setBounceDockIcon(newValue != 0, forEvent: eventType) }
	}

	override public var bounceDockIconRepeatedly: UInt {
		get { TPCPreferences.bounceDockIconRepeatedly(forEvent: eventType) ? 1 : 0 }
		set { TPCPreferences.setBounceDockIconRepeatedly(newValue != 0, forEvent: eventType) }
	}
}

@objc(TDCChannelPropertiesNotificationConfiguration)
public final class ChannelPropertiesNotificationConfiguration: NotificationConfiguration {
	private weak var sheet: TDCChannelPropertiesSheet?

	public required init(eventType: TXNotificationType) {
		super.init(eventType: eventType)
	}

	@objc(initWithEventType:inSheet:)
	public init(eventType: TXNotificationType, in sheet: TDCChannelPropertiesSheet) {
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

	private var config: IRCChannelConfigMutable? {
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
