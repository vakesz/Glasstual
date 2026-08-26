@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "TDCPreferencesNotificationConfigurationPrivate.h"
/// #import "TLONotificationConfigurationPrivate.h"
/// #import "TPCPreferencesLocal.h"
/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class TLONotificationConfigurationTests: XCTestCase {
	@objc
	func testBaseConfigurationPreservesEventAndDisplayName() {
		let configuration = NotificationConfiguration.configuration(withEventType: .highlight)

		XCTAssertEqual(configuration.eventType, .highlight)
		XCTAssertFalse(configuration.displayName.isEmpty)
	}

	@objc
	func testLocalizedSoundTitlesAndConstantsRemainAvailable() {
		XCTAssertFalse(NotificationConfiguration.localizedAlertDefaultSoundTitle().isEmpty)
		XCTAssertFalse(NotificationConfiguration.localizedAlertNoSoundTitle().isEmpty)

		XCTAssertEqual(TLONotificationAlertSound.TXDefaultAlertSoundPreferenceValue.rawValue, "Default")
		XCTAssertEqual(TLONotificationAlertSound.TXNoAlertSoundPreferenceValue.rawValue, "None")
	}

	@objc
	func testPreferencesConfigurationReadsExistingGlobalValues() {
		let eventType = TXNotificationType.highlight
		let configuration = PreferencesNotificationConfiguration.object(withEventType: eventType)
		let expectedSound = TPCPreferences.sound(forEvent: eventType)
			?? TLONotificationAlertSound.TXNoAlertSoundPreferenceValue.rawValue

		XCTAssertEqual(configuration.eventType, eventType)

		XCTAssertEqual(configuration.alertSound, expectedSound)

		XCTAssertEqual(configuration.pushNotification != 0, TPCPreferences.notificationEnabled(forEvent: eventType))
		XCTAssertEqual(configuration.speakEvent != 0, TPCPreferences.speakEvent(eventType))
		XCTAssertEqual(configuration.disabledWhileAway != 0, TPCPreferences.disabledWhileAway(forEvent: eventType))
		XCTAssertEqual(configuration.bounceDockIcon != 0, TPCPreferences.bounceDockIcon(forEvent: eventType))
		XCTAssertEqual(
			configuration.bounceDockIconRepeatedly != 0,
			TPCPreferences.bounceDockIconRepeatedly(forEvent: eventType)
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
