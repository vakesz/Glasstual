/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */
#import <XCTest/XCTest.h>

#import "GLTTestClient.h"
#import "IRCChannelMemberList.h"
#import "IRCChannelPrivate.h"
#import "IRCChannelUserPrivate.h"
#import "IRCISupportInfoPrivate.h"
#import "IRCMessage.h"
#import "IRCTreeItemPrivate.h"
#import "IRCUser.h"
#import "TVCLogLine.h"

NS_ASSUME_NONNULL_BEGIN

/* account-notify, extended-join, account-tag, setname, invite-notify,
 WHOX and pre-away. */
@interface IRCClientUserIdentityTests : XCTestCase
@end

@implementation IRCClientUserIdentityTests

- (IRCMessage *)message:(NSString *)line onClient:(IRCClient *)client
{
	IRCMessage *message = [[IRCMessage alloc] initWithLine:line onClient:client];

	XCTAssertNotNil(message, @"Failed to parse: %@", line);

	return message;
}

- (GLTTestClient *)clientNamed:(NSString *)nickname
{
	return [GLTTestClient testClientWithConfigDictionary:@{@"nickname" : nickname, @"username" : nickname}];
}

- (IRCChannel *)joinChannel:(NSString *)name onClient:(GLTTestClient *)client
{
	IRCChannel *channel = [[IRCChannel alloc] initWithConfigDictionary:@{@"channelName" : name}];

	channel.associatedClient = client;

	[client addChannel:channel];

	[channel activate];

	return channel;
}

- (IRCUser *)addUserNamed:(NSString *)nickname toChannel:(IRCChannel *)channel onClient:(GLTTestClient *)client
{
	IRCUser *user = [client findUserOrCreate:nickname];

	[channel addMember:[[IRCChannelUser alloc] initWithUser:user]];

	return user;
}

#pragma mark -
#pragma mark account-notify

- (void)testAccountNotifyUpdatesAccount
{
	GLTTestClient *client = [self clientNamed:@"me"];

	IRCChannel *channel = [self joinChannel:@"#chat" onClient:client];

	[self addUserNamed:@"alice" toChannel:channel onClient:client];

	[client receiveAccountNotify:[self message:@":alice!a@example.org ACCOUNT alice_acct" onClient:client]];

	XCTAssertEqualObjects([client findUser:@"alice"].account, @"alice_acct");

	[client receiveAccountNotify:[self message:@":alice!a@example.org ACCOUNT *" onClient:client]];

	XCTAssertNil([client findUser:@"alice"].account);

	/* A nickname we do not track (extended-monitor) is ignored. */
	[client receiveAccountNotify:[self message:@":stranger!s@example.org ACCOUNT acct" onClient:client]];

	XCTAssertNil([client findUser:@"stranger"]);
}

#pragma mark -
#pragma mark extended-join

- (void)testExtendedJoinReadsAccountAndRealName
{
	GLTTestClient *client = [self clientNamed:@"me"];

	[self joinChannel:@"#chat" onClient:client];

	[client enableCapability:ClientIRCv3SupportedCapabilityExtendedJoin];

	[client receiveJoin:[self message:@":alice!a@example.org JOIN #chat alice_acct :Alice Liddell" onClient:client]];

	IRCUser *alice = [client findUser:@"alice"];

	XCTAssertNotNil(alice);
	XCTAssertEqualObjects(alice.account, @"alice_acct");
	XCTAssertEqualObjects(alice.realName, @"Alice Liddell");

	[client receiveJoin:[self message:@":bob!b@example.org JOIN #chat * :Bob" onClient:client]];

	IRCUser *bob = [client findUser:@"bob"];

	XCTAssertNil(bob.account);
	XCTAssertEqualObjects(bob.realName, @"Bob");
}

- (void)testJoinParametersAreIgnoredWithoutExtendedJoin
{
	GLTTestClient *client = [self clientNamed:@"me"];

	[self joinChannel:@"#chat" onClient:client];

	[client receiveJoin:[self message:@":alice!a@example.org JOIN #chat alice_acct :Alice Liddell" onClient:client]];

	IRCUser *alice = [client findUser:@"alice"];

	XCTAssertNotNil(alice);
	XCTAssertNil(alice.account);
	XCTAssertNil(alice.realName);
}

#pragma mark -
#pragma mark account-tag and bot tag

- (void)testAccountTagAndBotTagUpdateSender
{
	GLTTestClient *client = [self clientNamed:@"me"];

	IRCChannel *channel = [self joinChannel:@"#chat" onClient:client];

	[self addUserNamed:@"alice" toChannel:channel onClient:client];

	[client receivePrivmsgAndNotice:[self message:@"@account=alice_acct :alice!a@example.org PRIVMSG #chat :hi"
										 onClient:client]];

	XCTAssertEqualObjects([client findUser:@"alice"].account, @"alice_acct");
	XCTAssertFalse([client findUser:@"alice"].isBot);

	[client receivePrivmsgAndNotice:[self message:@"@bot :alice!a@example.org NOTICE #chat :beep" onClient:client]];

	XCTAssertTrue([client findUser:@"alice"].isBot);

	/* The account survives messages without the tag. */
	XCTAssertEqualObjects([client findUser:@"alice"].account, @"alice_acct");

	[client receiveTagMessage:[self message:@"@account=other;+typing=active :alice!a@example.org TAGMSG #chat"
								   onClient:client]];

	XCTAssertEqualObjects([client findUser:@"alice"].account, @"other");
}

#pragma mark -
#pragma mark setname

- (void)testSetNameUpdatesRealName
{
	GLTTestClient *client = [self clientNamed:@"me"];

	IRCChannel *channel = [self joinChannel:@"#chat" onClient:client];

	[self addUserNamed:@"alice" toChannel:channel onClient:client];

	[client receiveSetName:[self message:@":alice!a@example.org SETNAME :Alice P. Liddell" onClient:client]];

	XCTAssertEqualObjects([client findUser:@"alice"].realName, @"Alice P. Liddell");
}

- (void)testSetNameCommandRequiresCapability
{
	GLTTestClient *client = [self clientNamed:@"me"];

	[client markAsLoggedIn];

	[client sendCommand:@"SETNAME New Name" completeTarget:NO target:nil];

	XCTAssertEqual(client.sentLines.count, 0);
	XCTAssertEqual(client.printedLines.count, 1);

	[client enableCapability:ClientIRCv3SupportedCapabilitySetName];

	[client sendCommand:@"SETNAME New Name" completeTarget:NO target:nil];

	XCTAssertEqualObjects(client.sentLines, @[ @"SETNAME :New Name" ]);
}

#pragma mark -
#pragma mark invite-notify

- (void)testInviteForSomebodyElseIsPrintedInChannel
{
	GLTTestClient *client = [self clientNamed:@"me"];

	IRCChannel *channel = [self joinChannel:@"#chat" onClient:client];

	[client receiveInvite:[self message:@":alice!a@example.org INVITE bob #chat" onClient:client]];

	XCTAssertEqual(client.printedLines.count, 1);
	XCTAssertEqual(client.printedLines[0][@"channel"], channel);
	XCTAssertEqual([client.printedLines[0][@"lineType"] unsignedIntegerValue], TVCLogLineTypeInvite);

	NSString *body = client.printedLines[0][@"messageBody"];

	XCTAssertTrue([body containsString:@"alice"]);
	XCTAssertTrue([body containsString:@"bob"]);
	XCTAssertTrue([body containsString:@"#chat"]);

	/* Invites to channels we are not in have nowhere to go. */
	[client receiveInvite:[self message:@":alice!a@example.org INVITE bob #other" onClient:client]];

	XCTAssertEqual(client.printedLines.count, 1);
}

- (void)testInviteForMyselfStillUsesInvitePrompt
{
	GLTTestClient *client = [self clientNamed:@"me"];

	[client receiveInvite:[self message:@":alice!a@example.org INVITE me #chat" onClient:client]];

	XCTAssertEqual(client.printedLines.count, 1);
	XCTAssertNil(client.printedLines[0][@"channel"]);
	XCTAssertTrue([client.printedLines[0][@"messageBody"] containsString:@"invited you"]);
}

#pragma mark -
#pragma mark WHOX

- (void)testWhoUsesWhoxWhenSupported
{
	GLTTestClient *client = [self clientNamed:@"me"];

	[client markAsLoggedIn];

	[client sendWhoToChannelNamed:@"#chat"];

	XCTAssertEqualObjects(client.sentLines.lastObject, @"WHO #chat");

	[client.supportInfo processConfigurationData:@"WHOX"];

	[client sendWhoToChannelNamed:@"#chat"];

	XCTAssertEqualObjects(client.sentLines.lastObject, @"WHO #chat %tcuhnfar,152");
}

- (void)testWhoxReplyIsParsed
{
	GLTTestClient *client = [self clientNamed:@"me"];

	[client.supportInfo processConfigurationData:@"WHOX BOT=B PREFIX=(ov)@+"];

	IRCChannel *channel = [self joinChannel:@"#chat" onClient:client];

	[client receiveNumericReply:
				[self message:@":irc.example.net 354 me 152 #chat ~alice host.example.org alice H*@B alice_acct :Alice"
					 onClient:client]];

	IRCUser *alice = [client findUser:@"alice"];

	XCTAssertNotNil(alice);
	XCTAssertEqualObjects(alice.username, @"~alice");
	XCTAssertEqualObjects(alice.address, @"host.example.org");
	XCTAssertEqualObjects(alice.realName, @"Alice");
	XCTAssertEqualObjects(alice.account, @"alice_acct");
	XCTAssertTrue(alice.isIRCop);
	XCTAssertTrue(alice.isBot);
	XCTAssertFalse(alice.isAway);

	IRCChannelUser *member = [channel findMember:@"alice"];

	XCTAssertNotNil(member);
	XCTAssertEqualObjects(member.modes, @"o");

	/* "0" means no account. */
	[client receiveNumericReply:[self message:@":irc.example.net 354 me 152 #chat ~bob host.example.org bob G 0 :Bob"
									 onClient:client]];

	IRCUser *bob = [client findUser:@"bob"];

	XCTAssertNotNil(bob);
	XCTAssertNil(bob.account);
	XCTAssertFalse(bob.isIRCop);
	XCTAssertFalse(bob.isBot);

	/* Replies to other tokens are not ours. */
	[client receiveNumericReply:[self message:@":irc.example.net 354 me 999 #chat ~eve host eve H 0 :Eve"
									 onClient:client]];

	XCTAssertNil([client findUser:@"eve"]);
}

- (void)testWhoReplyStillParsesWithoutWhox
{
	GLTTestClient *client = [self clientNamed:@"me"];

	[client.supportInfo processConfigurationData:@"PREFIX=(ov)@+"];

	IRCChannel *channel = [self joinChannel:@"#chat" onClient:client];

	IRCUser *existing = [self addUserNamed:@"alice" toChannel:channel onClient:client];

	[client modifyUser:existing
			 withBlock:^(IRCUserMutable *userMutable) {
				 userMutable.account = @"kept";
			 }];

	[client receiveNumericReply:
				[self message:@":irc.example.net 352 me #chat ~alice host.example.org irc.example.net alice H+ :0 Alice"
					 onClient:client]];

	IRCUser *alice = [client findUser:@"alice"];

	XCTAssertEqualObjects(alice.username, @"~alice");
	XCTAssertEqualObjects(alice.realName, @"Alice");
	XCTAssertEqualObjects(alice.account, @"kept");
}

#pragma mark -
#pragma mark pre-away

- (void)testPreAwayIsRequestedAndRestoresAwayOnReconnect
{
	GLTTestClient *client = [self clientNamed:@"me"];

	[client receiveCapabilityOrAuthenticationRequest:[self message:@":irc.example.net CAP * LS :pre-away"
														  onClient:client]];

	XCTAssertEqualObjects(client.sentCapabilityCommands, @[ @"REQ pre-away" ]);

	[client receiveCapabilityOrAuthenticationRequest:[self message:@":irc.example.net CAP me ACK :pre-away"
														  onClient:client]];

	XCTAssertTrue([client isCapabilityEnabled:ClientIRCv3SupportedCapabilityPreAway]);

	/* A fresh connection has no away message to restore. */
	XCTAssertEqualObjects(client.sentCapabilityCommands.lastObject, @"END");
	XCTAssertEqual(client.sentLines.count, 0);
}

- (void)testPreAwaySendsAwayBeforeCapEndWhenReconnecting
{
	GLTTestClient *client = [self clientNamed:@"me"];

	[client markAsLoggedIn];

	[client toggleAwayStatus:YES withComment:@"brb"];

	XCTAssertEqualObjects(client.sentLines, @[ @"AWAY :brb" ]);

	[client.sentLines removeAllObjects];

	/* The connection dropped and is being re-established. */
	[client setValue:@NO forKey:@"isLoggedIn"];

	client.connectType = IRCClientConnectModeReconnect;

	[client enableCapability:ClientIRCv3SupportedCapabilityPreAway];

	[client sendNextCapability];

	XCTAssertEqualObjects(client.sentLines, @[ @"AWAY :brb" ]);
	XCTAssertEqualObjects(client.sentCapabilityCommands, @[ @"END" ]);
}

- (void)testPreAwayDoesNothingWithoutCapability
{
	GLTTestClient *client = [self clientNamed:@"me"];

	[client markAsLoggedIn];

	[client toggleAwayStatus:YES withComment:@"brb"];

	[client.sentLines removeAllObjects];

	[client setValue:@NO forKey:@"isLoggedIn"];

	client.connectType = IRCClientConnectModeReconnect;

	[client sendNextCapability];

	XCTAssertEqual(client.sentLines.count, 0);
	XCTAssertEqualObjects(client.sentCapabilityCommands, @[ @"END" ]);
}

@end

NS_ASSUME_NONNULL_END
