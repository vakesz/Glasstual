/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "TDCPreferencesNotificationConfigurationPrivate.h"
#import "TLONotificationConfigurationPrivate.h"
#import "TPCPreferencesLocal.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLONotificationConfigurationTests : XCTestCase
@end

@implementation TLONotificationConfigurationTests

- (void)testBaseConfigurationPreservesEventAndDisplayName
{
	TLONotificationConfiguration *configuration =
		[TLONotificationConfiguration configurationWithEventType:TXNotificationTypeHighlight];

	XCTAssertEqual(configuration.eventType, TXNotificationTypeHighlight);
	XCTAssertGreaterThan(configuration.displayName.length, 0);
}

- (void)testLocalizedSoundTitlesAndConstantsRemainAvailable
{
	XCTAssertGreaterThan(TLONotificationConfiguration.localizedAlertDefaultSoundTitle.length, 0);
	XCTAssertGreaterThan(TLONotificationConfiguration.localizedAlertNoSoundTitle.length, 0);
	XCTAssertEqualObjects(TXDefaultAlertSoundPreferenceValue, @"Default");
	XCTAssertEqualObjects(TXNoAlertSoundPreferenceValue, @"None");
}

- (void)testPreferencesConfigurationReadsExistingGlobalValues
{
	TXNotificationType eventType = TXNotificationTypeHighlight;
	TDCPreferencesNotificationConfiguration *configuration =
		[TDCPreferencesNotificationConfiguration objectWithEventType:eventType];
	NSString *expectedSound = [TPCPreferences soundForEvent:eventType] ?: TXNoAlertSoundPreferenceValue;

	XCTAssertEqual(configuration.eventType, eventType);
	XCTAssertEqualObjects(configuration.alertSound, expectedSound);
	XCTAssertEqual(configuration.pushNotification, [TPCPreferences notificationEnabledForEvent:eventType]);
	XCTAssertEqual(configuration.speakEvent, [TPCPreferences speakEvent:eventType]);
	XCTAssertEqual(configuration.disabledWhileAway, [TPCPreferences disabledWhileAwayForEvent:eventType]);
	XCTAssertEqual(configuration.bounceDockIcon, [TPCPreferences bounceDockIconForEvent:eventType]);
	XCTAssertEqual(configuration.bounceDockIconRepeatedly, [TPCPreferences bounceDockIconRepeatedlyForEvent:eventType]);
}

- (void)testBaseFactoryRemainsPolymorphicForSubclasses
{
	TLONotificationConfiguration *configuration =
		[TDCPreferencesNotificationConfiguration configurationWithEventType:TXNotificationTypeInvite];

	XCTAssertTrue([configuration isKindOfClass:TDCPreferencesNotificationConfiguration.class]);
	XCTAssertEqual(configuration.eventType, TXNotificationTypeInvite);
}

@end

NS_ASSUME_NONNULL_END
