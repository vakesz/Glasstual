/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "GLTTestClient.h"
#import "IRCChannelPrivate.h"
#import "IRCChannelMemberListPrivate.h"
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

- (void)testChannelUserCopiesPreserveIdentityModesAndConversationWeights
{
	IRCUser *user = [[IRCUser alloc] initWithNickname:@"alice" onClient:self.client];
	IRCChannelUserMutable *member = [[IRCChannelUserMutable alloc] initWithUser:user];
	member.modes = @"ov";
	[member incomingConversation];
	[member outgoingConversation];

	IRCChannelUser *copy = [member copy];
	IRCChannelUserMutable *uniqueMutableCopy = [member uniqueCopyMutable];

	XCTAssertEqual(copy.user, user);
	XCTAssertEqualObjects(copy.modes, @"ov");
	XCTAssertEqual(copy.ranks, IRCUserRankNormalOperator | IRCUserRankVoiced);
	XCTAssertEqual(copy.incomingWeight, 100.0);
	XCTAssertEqual(copy.outgoingWeight, 20.0);
	XCTAssertEqual(copy.creationTime, member.creationTime);

	XCTAssertEqual(uniqueMutableCopy.user, user);
	XCTAssertEqualObjects(uniqueMutableCopy.modes, @"ov");
	XCTAssertEqual(uniqueMutableCopy.incomingWeight, 100.0);
	XCTAssertEqual(uniqueMutableCopy.outgoingWeight, 20.0);
}

- (void)testChannelMemberListAddsSortsAndRemovesMembers
{
	IRCChannel *channel = [self channelNamed:@"#chat"];
	IRCChannelMemberList *memberList = [[IRCChannelMemberList alloc] initWithChannel:channel];
	IRCChannelUser *bob = [self memberNamed:@"bob"];
	IRCChannelUser *alice = [self memberNamed:@"alice"];

	[memberList addMember:bob];
	[memberList addMember:alice];

	XCTAssertEqual(memberList.numberOfMembers, 2);
	XCTAssertEqualObjects([memberList.memberList valueForKeyPath:@"user.nickname"], (@[ @"alice", @"bob" ]));

	[memberList removeMember:alice];

	XCTAssertEqual(memberList.numberOfMembers, 1);
	XCTAssertEqualObjects(memberList.memberList, @[ bob ]);
	XCTAssertNil([alice.user userAssociatedWithChannel:channel]);
}

- (void)testChannelMemberListDuplicateCheckReplacesExistingRelation
{
	IRCChannel *channel = [self channelNamed:@"#chat"];
	IRCChannelMemberList *memberList = [[IRCChannelMemberList alloc] initWithChannel:channel];
	IRCUser *user = [[IRCUser alloc] initWithNickname:@"alice" onClient:self.client];
	IRCChannelUser *original = [[IRCChannelUser alloc] initWithUser:user];
	IRCChannelUser *replacement = [[IRCChannelUser alloc] initWithUser:user];

	[memberList addMember:original];
	[memberList addMember:replacement checkForDuplicates:YES];

	XCTAssertEqual(memberList.numberOfMembers, 1);
	XCTAssertEqual(memberList.memberList.firstObject, replacement);
	XCTAssertEqual([user userAssociatedWithChannel:channel], replacement);
}

@end

NS_ASSUME_NONNULL_END
