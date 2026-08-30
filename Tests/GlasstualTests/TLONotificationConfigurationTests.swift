/*  *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Notification configuration")
struct TLONotificationConfigurationTests {
	@Test("A configuration remembers the event it was made for and names it")
	func configurationsPreserveEventAndDisplayName() {
		let configuration: any NotificationConfiguration =
			PreferencesNotificationConfiguration(eventType: .highlight)

		#expect(configuration.eventType == .highlight)
		#expect(configuration.displayName.isEmpty == false)
	}

	@Test("The sound menu titles are localized and the stored values are not")
	func localizedSoundTitlesAndConstantsRemainAvailable() {
		#expect(NotificationAlertSound.localizedDefaultTitle.isEmpty == false)
		#expect(NotificationAlertSound.localizedNoSoundTitle.isEmpty == false)

		#expect(NotificationAlertSound.defaultPreferenceValue == "Default")
		#expect(NotificationAlertSound.noSoundPreferenceValue == "None")
	}

	@Test("The global configuration reads the values already in preferences")
	func preferencesConfigurationReadsExistingGlobalValues() {
		let eventType = TXNotificationType.highlight
		let configuration = PreferencesNotificationConfiguration(eventType: eventType)
		let expectedSound = TextualPreferences.sound(for: eventType)
			?? NotificationAlertSound.noSoundPreferenceValue

		#expect(configuration.eventType == eventType)

		#expect(configuration.alertSound == expectedSound)

		#expect(
			(configuration.pushNotification != NSControl.StateValue.off)
				== TextualPreferences.notificationEnabled(for: eventType)
		)
		#expect((configuration.speakEvent != NSControl.StateValue.off) == TextualPreferences.speak(eventType))
		#expect(
			(configuration.disabledWhileAway != NSControl.StateValue.off)
				== TextualPreferences.disabledWhileAway(for: eventType)
		)
		#expect(
			(configuration.bounceDockIcon != NSControl.StateValue.off)
				== TextualPreferences.bounceDockIcon(for: eventType)
		)
		#expect(
			(configuration.bounceDockIconRepeatedly != NSControl.StateValue.off)
				== TextualPreferences.bounceDockIconRepeatedly(for: eventType)
		)
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
