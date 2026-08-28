@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "TPCPreferencesLocal.h"
/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
@MainActor
class TLONotificationConfigurationTests: XCTestCase {
	@objc
	func testBaseConfigurationPreservesEventAndDisplayName() {
		let configuration = NotificationConfiguration.configuration(withEventType: .highlight)
		let displayName = configuration.displayName

		XCTAssertEqual(configuration.eventType, .highlight)
		XCTAssertFalse(displayName.isEmpty)
	}

	@objc
	func testLocalizedSoundTitlesAndConstantsRemainAvailable() {
		XCTAssertFalse(NotificationConfiguration.localizedAlertDefaultSoundTitle().isEmpty)
		XCTAssertFalse(NotificationConfiguration.localizedAlertNoSoundTitle().isEmpty)

		XCTAssertEqual(NotificationAlertSound.defaultPreferenceValue, "Default")
		XCTAssertEqual(NotificationAlertSound.noSoundPreferenceValue, "None")
	}

	@objc
	func testPreferencesConfigurationReadsExistingGlobalValues() {
		let eventType = TXNotificationType.highlight
		let configuration = PreferencesNotificationConfiguration.object(withEventType: eventType)
		let expectedSound = TextualPreferences.sound(for: eventType)
			?? NotificationAlertSound.noSoundPreferenceValue

		XCTAssertEqual(configuration.eventType, eventType)

		XCTAssertEqual(configuration.alertSound, expectedSound)

		XCTAssertEqual(configuration.pushNotification != .off, TextualPreferences.notificationEnabled(for: eventType))
		XCTAssertEqual(configuration.speakEvent != .off, TextualPreferences.speak(eventType))
		XCTAssertEqual(configuration.disabledWhileAway != .off, TextualPreferences.disabledWhileAway(for: eventType))
		XCTAssertEqual(configuration.bounceDockIcon != .off, TextualPreferences.bounceDockIcon(for: eventType))
		XCTAssertEqual(
			configuration.bounceDockIconRepeatedly != .off,
			TextualPreferences.bounceDockIconRepeatedly(for: eventType)
		)
	}

	@objc
	func testBaseFactoryRemainsPolymorphicForSubclasses() {
		let configuration: NotificationConfiguration = PreferencesNotificationConfiguration
			.configuration(withEventType: .invite)

		XCTAssertTrue(configuration is PreferencesNotificationConfiguration)
		XCTAssertEqual(configuration.eventType, .invite)
	}
}
