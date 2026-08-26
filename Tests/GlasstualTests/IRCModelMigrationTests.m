/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "GLTTestClient.h"
#import "IRCChannelConfig.h"
#import "IRCConnection.h"
#import "IRCConnectionConfig.h"
#import "IRCConnectionPrivate.h"
#import "IRCHighlightLogEntryPrivate.h"
#import "IRCHighlightMatchCondition.h"
#import "IRCServerPrivate.h"
#import "IRCUserPersistentStorePrivate.h"
#import "IRCUserRelationsPrivate.h"
#import "TVCLogLinePrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCModelMigrationTests : XCTestCase
@end

@implementation IRCModelMigrationTests

#pragma mark - Connection

- (void)testConnectionInitialStateAndConfigIsolation
{
	GLTTestClient *client = [GLTTestClient testClient];
	IRCConnectionConfigMutable *sourceConfig = [IRCConnectionConfigMutable new];
	sourceConfig.serverAddress = @"irc.example.test";

	IRCConnection *connection = [[IRCConnection alloc] initWithConfig:sourceConfig onClient:client];
	sourceConfig.serverAddress = @"changed.example.test";

	XCTAssertEqual(connection.client, client);
	XCTAssertEqualObjects(connection.config.serverAddress, @"irc.example.test");
	XCTAssertGreaterThan(connection.uniqueIdentifier.length, 0);
	XCTAssertFalse(connection.isConnecting);
	XCTAssertFalse(connection.isConnected);
	XCTAssertFalse(connection.isDisconnecting);
	XCTAssertFalse(connection.isSecured);
	XCTAssertFalse(connection.isSending);
	XCTAssertFalse(connection.EOFReceived);
}

- (void)testConnectionResetClearsTransientState
{
	GLTTestClient *client = [GLTTestClient testClient];
	IRCConnection *connection = [[IRCConnection alloc] initWithConfig:[IRCConnectionConfig new] onClient:client];

	[connection resetState];

	XCTAssertFalse(connection.isConnecting);
	XCTAssertFalse(connection.isConnected);
	XCTAssertFalse(connection.isConnectedWithClientSideCertificate);
	XCTAssertFalse(connection.isDisconnecting);
	XCTAssertFalse(connection.isSecured);
	XCTAssertFalse(connection.isSending);
	XCTAssertFalse(connection.EOFReceived);
	XCTAssertNil(connection.connectedAddress);
}

#pragma mark - Channel config

- (void)testChannelConfigDefaultsAndLegacyKeys
{
	IRCChannelConfig *defaults = [IRCChannelConfig seedWithName:@"#general"];

	XCTAssertTrue(defaults.autoJoin);
	XCTAssertTrue(defaults.pushNotifications);
	XCTAssertTrue(defaults.showTreeBadgeCount);
	XCTAssertEqual(defaults.type, IRCChannelTypeChannel);
	XCTAssertEqualObjects(defaults.channelName, @"#general");
	XCTAssertGreaterThan(defaults.uniqueIdentifier.length, 0);

	IRCChannelConfig *legacy = [[IRCChannelConfig alloc] initWithDictionary:@{
		@"channelName" : @"#legacy",
		@"joinOnConnect" : @NO,
		@"ignoreJPQActivity" : @YES,
		@"enableNotifications" : @NO,
		@"enableTreeBadgeCountDrawing" : @NO
	}];

	XCTAssertFalse(legacy.autoJoin);
	XCTAssertTrue(legacy.ignoreGeneralEventMessages);
	XCTAssertFalse(legacy.pushNotifications);
	XCTAssertFalse(legacy.showTreeBadgeCount);
}

- (void)testChannelConfigMutableAndUniqueCopiesPreserveValues
{
	IRCChannelConfigMutable *mutable = [IRCChannelConfigMutable new];
	mutable.channelName = @"#swift";
	mutable.label = @"Swift migration";
	mutable.defaultModes = @"+nt";
	mutable.secretKey = @"join-key";

	IRCChannelConfig *copy = [mutable copy];
	IRCChannelConfigMutable *unique = [mutable uniqueCopyMutable];

	XCTAssertEqualObjects(copy.channelName, @"#swift");
	XCTAssertEqualObjects(copy.label, @"Swift migration");
	XCTAssertEqualObjects(copy.defaultModes, @"+nt");
	XCTAssertEqualObjects(copy.secretKey, @"join-key");
	XCTAssertEqualObjects(copy.uniqueIdentifier, mutable.uniqueIdentifier);

	XCTAssertEqualObjects(unique.channelName, @"#swift");
	XCTAssertEqualObjects(unique.secretKey, @"join-key");
	XCTAssertNotEqualObjects(unique.uniqueIdentifier, mutable.uniqueIdentifier);
}

- (void)testChannelConfigNotificationOverridesUseThreeStateSemantics
{
	IRCChannelConfigMutable *config = [IRCChannelConfigMutable new];
	TXNotificationType event = TXNotificationTypeHighlight;

	XCTAssertEqual([config notificationEnabledForEvent:event], NSControlStateValueMixed);

	[config setNotificationEnabled:NSControlStateValueOn forEvent:event];
	XCTAssertEqual([config notificationEnabledForEvent:event], NSControlStateValueOn);

	[config setNotificationEnabled:NSControlStateValueOff forEvent:event];
	XCTAssertEqual([config notificationEnabledForEvent:event], NSControlStateValueOff);

	[config setNotificationEnabled:NSControlStateValueMixed forEvent:event];
	XCTAssertEqual([config notificationEnabledForEvent:event], NSControlStateValueMixed);
}

#pragma mark - Highlight match condition

- (void)testHighlightMatchConditionRoundTripsDictionaryAndDefaults
{
	IRCHighlightMatchCondition *condition = [[IRCHighlightMatchCondition alloc]
		initWithDictionary:@{@"matchKeyword" : @"alert", @"matchChannelID" : @"chan-1", @"matchIsExcluded" : @YES}];

	XCTAssertEqualObjects(condition.matchKeyword, @"alert");
	XCTAssertEqualObjects(condition.matchChannelId, @"chan-1");
	XCTAssertTrue(condition.matchIsExcluded);
	XCTAssertGreaterThan(condition.uniqueIdentifier.length, 0);

	NSDictionary *dictionary = condition.dictionaryValue;
	XCTAssertEqualObjects(dictionary[@"matchKeyword"], @"alert");
	XCTAssertEqualObjects(dictionary[@"matchChannelID"], @"chan-1");
	XCTAssertEqualObjects(dictionary[@"matchIsExcluded"], @YES);
	XCTAssertEqualObjects(dictionary[@"uniqueIdentifier"], condition.uniqueIdentifier);
}

- (void)testHighlightMatchConditionMutableCopyAndUniqueCopy
{
	IRCHighlightMatchCondition *original =
		[[IRCHighlightMatchCondition alloc] initWithDictionary:@{@"matchKeyword" : @"ping"}];
	IRCHighlightMatchConditionMutable *mutableCopy = [original mutableCopy];
	mutableCopy.matchKeyword = @"pong";
	mutableCopy.matchIsExcluded = YES;

	XCTAssertEqualObjects(original.matchKeyword, @"ping");
	XCTAssertFalse(original.matchIsExcluded);
	XCTAssertEqualObjects(mutableCopy.matchKeyword, @"pong");
	XCTAssertTrue(mutableCopy.matchIsExcluded);

	IRCHighlightMatchCondition *unique = [original uniqueCopy];
	XCTAssertEqualObjects(unique.matchKeyword, @"ping");
	XCTAssertNotEqualObjects(unique.uniqueIdentifier, original.uniqueIdentifier);
}

#pragma mark - Server

- (void)testServerDefaultsAndDictionaryRoundTrip
{
	IRCServer *server = [[IRCServer alloc] initWithDictionary:@{
		@"serverAddress" : @"irc.example.test",
		@"serverPort" : @6697,
		@"prefersSecuredConnection" : @YES
	}];

	XCTAssertEqualObjects(server.serverAddress, @"irc.example.test");
	XCTAssertEqual(server.serverPort, 6697);
	XCTAssertTrue(server.prefersSecuredConnection);
	XCTAssertGreaterThan(server.uniqueIdentifier.length, 0);

	IRCServer *empty = [IRCServer new];
	XCTAssertEqual(empty.serverPort, 6667);
	XCTAssertEqualObjects(empty.serverAddress, @"");
}

- (void)testServerMutablePasswordAndUniqueCopy
{
	IRCServerMutable *mutable = [IRCServerMutable new];
	mutable.serverAddress = @"chat.example.test";
	mutable.serverPort = 6667;
	mutable.serverPassword = @"s3cret";
	mutable.prefersSecuredConnection = NO;

	XCTAssertEqualObjects(mutable.serverPassword, @"s3cret");

	IRCServer *unique = [mutable uniqueCopy];
	XCTAssertEqualObjects(unique.serverAddress, @"chat.example.test");
	XCTAssertNotEqualObjects(unique.uniqueIdentifier, mutable.uniqueIdentifier);
	XCTAssertEqualObjects(unique.serverPassword, @"s3cret");
}

#pragma mark - Highlight log entry

- (void)testHighlightLogEntryMutableStoresLineClientAndChannel
{
	TVCLogLineMutable *line = [TVCLogLineMutable new];
	line.messageBody = @"hello world";
	line.nickname = @"alice";
	line.lineType = TVCLogLineTypePrivateMessage;
	line.receivedAt = [NSDate dateWithTimeIntervalSince1970:1700000000];

	IRCHighlightLogEntryMutable *entry = [IRCHighlightLogEntryMutable new];
	entry.lineLogged = line;
	entry.clientId = @"client-a";
	entry.channelId = @"channel-b";

	XCTAssertEqualObjects(entry.clientId, @"client-a");
	XCTAssertEqualObjects(entry.channelId, @"channel-b");
	XCTAssertEqualObjects(entry.lineNumber, line.uniqueIdentifier);
	XCTAssertEqualObjects(entry.timeLogged, line.receivedAt);
	XCTAssertGreaterThan(entry.renderedMessage.length, 0);
	XCTAssertGreaterThan(entry.timeLoggedFormatted.length, 0);
}

#pragma mark - Persistent store

- (void)testUserPersistentStoreHoldsRelationsAndTimerSlot
{
	IRCUserPersistentStore *store = [IRCUserPersistentStore new];
	IRCUserRelations *relations = [IRCUserRelations new];

	store.relations = relations;
	store.presentAwayMessageFor301LastEvent = 12.5;

	XCTAssertEqual(store.relations, relations);
	XCTAssertEqual(store.presentAwayMessageFor301LastEvent, 12.5);
	XCTAssertNil(store.removeUserTimer);
}

@end

NS_ASSUME_NONNULL_END
