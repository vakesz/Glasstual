import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "TDCPreferencesNotificationConfigurationPrivate.h"
// #import "TLONotificationConfigurationPrivate.h"
// #import "TPCPreferencesLocal.h"
/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class TLONotificationConfigurationTests: XCTestCase {
    @objc
    func testBaseConfigurationPreservesEventAndDisplayName() {
        let configuration: UnsafeMutablePointer<TLONotificationConfiguration>! = TLONotificationConfiguration.configurationWithEventType(TXNotificationTypeHighlight)

        XCTAssertEqual(configuration.eventType, TXNotificationTypeHighlight)
        XCTAssertGreaterThan(configuration.displayName.length, 0)
    }
    @objc
    func testLocalizedSoundTitlesAndConstantsRemainAvailable() {
        XCTAssertGreaterThan(TLONotificationConfiguration.localizedAlertDefaultSoundTitle.length, 0)
        XCTAssertGreaterThan(TLONotificationConfiguration.localizedAlertNoSoundTitle.length, 0)

        XCTAssertEqualObjects(TXDefaultAlertSoundPreferenceValue, "Default")
        XCTAssertEqualObjects(TXNoAlertSoundPreferenceValue, "None")
    }
    @objc
    func testPreferencesConfigurationReadsExistingGlobalValues() {
        let eventType: TXNotificationType = TXNotificationTypeHighlight
        let configuration: UnsafeMutablePointer<TDCPreferencesNotificationConfiguration>! = TDCPreferencesNotificationConfiguration.objectWithEventType(eventType)
        let expectedSound: String! = TPCPreferences.soundForEvent(eventType) ?? TXNoAlertSoundPreferenceValue

        XCTAssertEqual(configuration.eventType, eventType)

        XCTAssertEqualObjects(configuration.alertSound, expectedSound)

        XCTAssertEqual(configuration.pushNotification, TPCPreferences.notificationEnabledForEvent(eventType))
        XCTAssertEqual(configuration.speakEvent, TPCPreferences.speakEvent(eventType))
        XCTAssertEqual(configuration.disabledWhileAway, TPCPreferences.disabledWhileAwayForEvent(eventType))
        XCTAssertEqual(configuration.bounceDockIcon, TPCPreferences.bounceDockIconForEvent(eventType))
        XCTAssertEqual(configuration.bounceDockIconRepeatedly, TPCPreferences.bounceDockIconRepeatedlyForEvent(eventType))
    }
    @objc
    func testBaseFactoryRemainsPolymorphicForSubclasses() {
        let configuration: UnsafeMutablePointer<TLONotificationConfiguration>! = TDCPreferencesNotificationConfiguration.configurationWithEventType(TXNotificationTypeInvite)

        XCTAssertTrue(configuration.isKindOfClass(TDCPreferencesNotificationConfiguration.class))
        XCTAssertEqual(configuration.eventType, TXNotificationTypeInvite)
    }
}