@testable import Glasstual
import XCTest

/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@MainActor
class TLONotificationConfigurationTests: XCTestCase {
	func testConfigurationsPreserveEventAndDisplayName() {
		let configuration: any NotificationConfiguration =
			PreferencesNotificationConfiguration(eventType: .highlight)

		XCTAssertEqual(configuration.eventType, .highlight)
		XCTAssertFalse(configuration.displayName.isEmpty)
	}

	func testLocalizedSoundTitlesAndConstantsRemainAvailable() {
		XCTAssertFalse(NotificationAlertSound.localizedDefaultTitle.isEmpty)
		XCTAssertFalse(NotificationAlertSound.localizedNoSoundTitle.isEmpty)

		XCTAssertEqual(NotificationAlertSound.defaultPreferenceValue, "Default")
		XCTAssertEqual(NotificationAlertSound.noSoundPreferenceValue, "None")
	}

	func testPreferencesConfigurationReadsExistingGlobalValues() {
		let eventType = TXNotificationType.highlight
		let configuration = PreferencesNotificationConfiguration(eventType: eventType)
		let expectedSound = TextualPreferences.sound(for: eventType)
			?? NotificationAlertSound.noSoundPreferenceValue

		XCTAssertEqual(configuration.eventType, eventType)

		XCTAssertEqual(configuration.alertSound, expectedSound)

		XCTAssertEqual(
			configuration.pushNotification != NSControl.StateValue.off,
			TextualPreferences.notificationEnabled(for: eventType)
		)
		XCTAssertEqual(configuration.speakEvent != NSControl.StateValue.off, TextualPreferences.speak(eventType))
		XCTAssertEqual(
			configuration.disabledWhileAway != NSControl.StateValue.off,
			TextualPreferences.disabledWhileAway(for: eventType)
		)
		XCTAssertEqual(
			configuration.bounceDockIcon != NSControl.StateValue.off,
			TextualPreferences.bounceDockIcon(for: eventType)
		)
		XCTAssertEqual(
			configuration.bounceDockIconRepeatedly != NSControl.StateValue.off,
			TextualPreferences.bounceDockIconRepeatedly(for: eventType)
		)
	}

	/// The pane holds whichever implementation it was handed, without knowing
	/// which one it is.
	func testBothImplementationsSatisfyTheProtocol() {
		let configurations: [any NotificationConfiguration] = [
			PreferencesNotificationConfiguration(eventType: .invite),
			ChannelNotificationConfiguration(eventType: .invite),
		]

		for configuration in configurations {
			XCTAssertEqual(configuration.eventType, .invite)
		}
	}
}
