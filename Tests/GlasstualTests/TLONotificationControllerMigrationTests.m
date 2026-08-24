/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "TLONotificationControllerPrivate.h"
#import "TPCPreferencesLocal.h"
#import "TXSharedApplicationPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLONotificationControllerMigrationTests : XCTestCase
@end

@implementation TLONotificationControllerMigrationTests

- (TLONotificationController *)controller
{
	return TXSharedApplication.sharedNotificationController;
}

- (void)testTitleForEventReturnsLocalizedNonEmptyStrings
{
	TLONotificationController *controller = self.controller;

	XCTAssertGreaterThan([controller titleForEvent:TXNotificationTypeHighlight].length, 0);
	XCTAssertGreaterThan([controller titleForEvent:TXNotificationTypeConnect].length, 0);
	XCTAssertGreaterThan([controller titleForEvent:TXNotificationTypeFileTransferReceiveRequested].length, 0);
	XCTAssertGreaterThan([controller titleForEvent:TXNotificationTypeUserJoined].length, 0);
}

- (void)testThreadIdentifierCombinesClientAndChannel
{
	XCTAssertNil([TLONotificationController threadIdentifierForClient:nil channel:@"chan"]);
	XCTAssertEqualObjects([TLONotificationController threadIdentifierForClient:@"client-a" channel:nil], @"client-a");
	XCTAssertEqualObjects([TLONotificationController threadIdentifierForClient:@"client-a" channel:@"chan-b"],
						  @"client-a-chan-b");
}

- (void)testNotificationIdentifierUsesStableNSStringHashLayout
{
	NSString *title = @"Hello";
	NSString *message = @"World";
	NSString *thread = @"client-channel";

	NSString *expected = [NSString stringWithFormat:@"TXNotification-%@-%ld-%ld", thread, title.hash, message.hash];
	NSString *actual = [TLONotificationController notificationIdentifierWithTitle:title
																		  message:message
																 threadIdentifier:thread];

	XCTAssertEqualObjects(actual, expected);

	NSString *noThreadExpected =
		[NSString stringWithFormat:@"TXNotification-%@-%ld-%ld", @"<No Thread>", title.hash, message.hash];
	XCTAssertEqualObjects([TLONotificationController notificationIdentifierWithTitle:title
																			 message:message
																	threadIdentifier:nil],
						  noThreadExpected);
}

- (void)testUserInfoScopeMatchingTreatsNilChannelsAsEqual
{
	NSDictionary *clientOnly = @{TXNotificationUserInfoClientIdentifierKey : @"c1"};
	NSDictionary *withChannel =
		@{TXNotificationUserInfoClientIdentifierKey : @"c1", TXNotificationUserInfoChannelIdentifierKey : @"ch1"};

	XCTAssertTrue([TLONotificationController userInfo:clientOnly
						  isInScopeOfClientIdentifier:@"c1"
									channelIdentifier:nil]);
	XCTAssertFalse([TLONotificationController userInfo:clientOnly
						   isInScopeOfClientIdentifier:@"c1"
									 channelIdentifier:@"ch1"]);
	XCTAssertTrue([TLONotificationController userInfo:withChannel
						  isInScopeOfClientIdentifier:@"c1"
									channelIdentifier:@"ch1"]);
	XCTAssertFalse([TLONotificationController userInfo:withChannel
						   isInScopeOfClientIdentifier:@"c2"
									 channelIdentifier:@"ch1"]);
}

- (void)testPublicFormatConstantsRemainStable
{
	XCTAssertEqualObjects(TXNotificationUserInfoClientIdentifierKey, @"clientId");
	XCTAssertEqualObjects(TXNotificationUserInfoChannelIdentifierKey, @"channelId");
	XCTAssertEqualObjects(TXNotificationDialogStandardNicknameFormat, @"%@ %@");
	XCTAssertEqualObjects(TXNotificationDialogActionNicknameFormat, @"\u2022 %@: %@");
	XCTAssertEqualObjects(TXNotificationHighlightLogStandardActionFormat, @"\u2022 %@: %@");
	XCTAssertEqualObjects(TXNotificationHighlightLogStandardMessageFormat, @"%@ %@");
}

- (void)testPreferenceLookupsWithNilChannelMatchGlobalPreferences
{
	TLONotificationController *controller = self.controller;
	TXNotificationType eventType = TXNotificationTypeHighlight;

	XCTAssertEqualObjects([controller soundForEvent:eventType inChannel:nil], [TPCPreferences soundForEvent:eventType]);
	XCTAssertEqual([controller speakEvent:eventType inChannel:nil], [TPCPreferences speakEvent:eventType]);
	XCTAssertEqual([controller notificationEnabledForEvent:eventType inChannel:nil],
				   [TPCPreferences notificationEnabledForEvent:eventType]);
	XCTAssertEqual([controller disabledWhileAwayForEvent:eventType inChannel:nil],
				   [TPCPreferences disabledWhileAwayForEvent:eventType]);
	XCTAssertEqual([controller bounceDockIconForEvent:eventType inChannel:nil],
				   [TPCPreferences bounceDockIconForEvent:eventType]);
	XCTAssertEqual([controller bounceDockIconRepeatedlyForEvent:eventType inChannel:nil],
				   [TPCPreferences bounceDockIconRepeatedlyForEvent:eventType]);
}

- (void)testAreNotificationsDisabledToggle
{
	TLONotificationController *controller = self.controller;
	BOOL original = controller.areNotificationsDisabled;

	controller.areNotificationsDisabled = YES;
	XCTAssertTrue(controller.areNotificationsDisabled);

	controller.areNotificationsDisabled = NO;
	XCTAssertFalse(controller.areNotificationsDisabled);

	controller.areNotificationsDisabled = original;
}

@end

NS_ASSUME_NONNULL_END
