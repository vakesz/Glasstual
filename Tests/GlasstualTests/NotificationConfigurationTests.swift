/*  *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Notification configuration")
struct NotificationConfigurationTests {
	@Test("A configuration remembers the event it was made for and names it")
	func configurationsPreserveEventAndDisplayName() {
		let configuration: any NotificationConfiguration =
			PreferencesNotificationConfiguration(eventType: .highlight)

		#expect(configuration.eventType == .highlight)
		#expect(configuration.displayName.isEmpty == false)
	}

	/// The getter used to substitute "None" for a missing stored value, so the
	/// "Default" row could never be selected: choosing it wrote `nil`, and the
	/// very next read turned that into "No sound".
	@Test("Choosing the default sound reads back as the default")
	func defaultSoundRoundTrips() {
		/* An event that ships with no registered sound, so nothing stands behind
		 a removed value. */
		let eventType = NotificationEvent.userJoined
		let key = Preferences.Notifications.sound(eventType)
		let original = key.storedValue
		defer { key.storedValue = original }

		let configuration = PreferencesNotificationConfiguration(eventType: eventType)
		configuration.alertSound = NotificationAlertSound.noSoundPreferenceValue
		#expect(configuration.alertSound == NotificationAlertSound.noSoundPreferenceValue)

		configuration.alertSound = nil
		#expect(configuration.alertSound == nil)
	}

	@Test("The sound menu titles are localized and the stored values are not")
	func localizedSoundTitlesAndConstantsRemainAvailable() {
		#expect(NotificationAlertSound.localizedDefaultTitle.isEmpty == false)
		#expect(NotificationAlertSound.localizedNoSoundTitle.isEmpty == false)

		#expect(NotificationAlertSound.defaultPreferenceValue == "Default")
		#expect(NotificationAlertSound.noSoundPreferenceValue == "None")
	}

	/** The five flags are written as an alternating pattern rather than all
	 true: reading each accessor back against the key it is meant to read passes
	 for a mis-mapped accessor whenever the two keys happen to agree, which at
	 the shipped defaults they do. */
	@Test("The global configuration reads the values already in preferences")
	func preferencesConfigurationReadsExistingGlobalValues() {
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

		sound.value = "Submarine"
		for (offset, flag) in flags.enumerated() {
			Preferences.Notifications.flag(eventType, flag).value = offset.isMultiple(of: 2)
		}

		let configuration = PreferencesNotificationConfiguration(eventType: eventType)

		#expect(configuration.eventType == eventType)
		#expect(configuration.alertSound == "Submarine")
		#expect(configuration.pushNotification == .on)
		#expect(configuration.speakEvent == .off)
		#expect(configuration.disabledWhileAway == .on)
		#expect(configuration.bounceDockIcon == .off)
		#expect(configuration.bounceDockIconRepeatedly == .on)
	}

	/// The pane holds whichever implementation it was handed, without knowing
	/// which one it is.
	@Test("Both implementations satisfy the protocol the pane talks to")
	func bothImplementationsSatisfyTheProtocol() {
		let configurations: [any NotificationConfiguration] = [
			PreferencesNotificationConfiguration(eventType: .invite),
			ChannelNotificationConfiguration(eventType: .invite),
		]

		for configuration in configurations {
			#expect(configuration.eventType == .invite)
		}
	}
}
