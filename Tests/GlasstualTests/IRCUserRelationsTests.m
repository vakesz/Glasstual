/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "GLTTestClient.h"
#import "IRCChannelPrivate.h"
#import "IRCChannelUserPrivate.h"
#import "IRCTreeItemPrivate.h"
#import "IRCUser.h"
#import "IRCUserRelationsPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCUserRelationsTests : XCTestCase
@property(nonatomic, strong) GLTTestClient *client;
@property(nonatomic, strong) IRCUserRelations *relations;
@end

@implementation IRCUserRelationsTests

- (void)setUp
{
	[super setUp];

	self.client = [GLTTestClient testClient];
	self.relations = [IRCUserRelations new];
}

- (IRCChannel *)channelNamed:(NSString *)name
{
	IRCChannel *channel = [[IRCChannel alloc] initWithConfigDictionary:@{@"channelName" : name}];

	channel.associatedClient = self.client;

	return channel;
}

- (IRCChannelUser *)memberNamed:(NSString *)nickname
{
	IRCUser *user = [[IRCUser alloc] initWithNickname:nickname onClient:self.client];

	return [[IRCChannelUser alloc] initWithUser:user];
}

- (void)testAssociatingAndDisassociatingChannelMember
{
	IRCChannel *channel = [self channelNamed:@"#chat"];
	IRCChannelUser *member = [self memberNamed:@"alice"];

	[self.relations associateUser:member withChannel:channel];

	XCTAssertEqual(self.relations.numberOfRelations, 1);
	XCTAssertEqualObjects(self.relations.relatedChannels, @[ channel ]);
	XCTAssertEqualObjects(self.relations.relatedUsers, @[ member ]);
	XCTAssertEqual([self.relations userAssociatedWithChannel:channel], member);

	[self.relations disassociateUserWithChannel:channel];

	XCTAssertEqual(self.relations.numberOfRelations, 0);
	XCTAssertNil([self.relations userAssociatedWithChannel:channel]);
}

- (void)testReplacingRelationForSameChannel
{
	IRCChannel *channel = [self channelNamed:@"#chat"];
	IRCChannelUser *first = [self memberNamed:@"alice"];
	IRCChannelUser *second = [self memberNamed:@"bob"];

	[self.relations associateUser:first withChannel:channel];
	[self.relations associateUser:second withChannel:channel];

	XCTAssertEqual(self.relations.numberOfRelations, 1);
	XCTAssertEqual([self.relations userAssociatedWithChannel:channel], second);
}

- (void)testEnumerationUsesSnapshotAndHonorsStop
{
	[self.relations associateUser:[self memberNamed:@"alice"] withChannel:[self channelNamed:@"#one"]];
	[self.relations associateUser:[self memberNamed:@"bob"] withChannel:[self channelNamed:@"#two"]];

	__block NSUInteger visitedCount = 0;

	[self.relations enumerateRelations:^(IRCChannel *channel, IRCChannelUser *member, BOOL *stop) {
		visitedCount += 1;
		*stop = YES;
	}];

	XCTAssertEqual(visitedCount, 1);
}

- (void)testPrivateMessageChannelsAreNotStored
{
	IRCChannel *privateMessage = [[IRCChannel alloc]
		initWithConfigDictionary:@{@"channelName" : @"alice", @"channelType" : @(IRCChannelTypePrivateMessage)}];

	privateMessage.associatedClient = self.client;

	IRCChannelUser *member = [self memberNamed:@"alice"];

	[self.relations associateUser:member withChannel:privateMessage];

	XCTAssertEqual(self.relations.numberOfRelations, 0);
	XCTAssertNil([self.relations userAssociatedWithChannel:privateMessage]);
}

@end

NS_ASSUME_NONNULL_END
