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
#import "IRCChannelPrivate.h"
#import "IRCISupportInfoPrivate.h"
#import "IRCMessage.h"
#import "IRCTreeItemPrivate.h"
#import "TVCLogControllerHistoricLogFilePrivate.h"
#import "TPCPreferencesUserDefaults.h"
#import "TVCLogLinePrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCClientHistoryTests : XCTestCase
@end

@implementation IRCClientHistoryTests

- (IRCMessage *)message:(NSString *)line onClient:(IRCClient *)client
{
	IRCMessage *message = [[IRCMessage alloc] initWithLine:line onClient:client];

	XCTAssertNotNil(message, @"Failed to parse: %@", line);

	return message;
}

- (void)feedLines:(NSArray<NSString *> *)lines toClient:(GLTTestClient *)client
{
	for (NSString *line in lines) {
		IRCMessage *message = [self message:line onClient:client];

		if ([client filterBatchCommandIncomingData:message]) {
			continue;
		}

		if ([message.command isEqualToString:@"BATCH"]) {
			[client receiveBatch:message];
		} else {
			[client processIncomingMessage:message];
		}
	}
}

- (IRCChannel *)channelNamed:(NSString *)name onClient:(GLTTestClient *)client
{
	IRCChannel *channel = [[IRCChannel alloc] initWithConfigDictionary:@{@"channelName" : name}];

	channel.associatedClient = client;

	[client addChannel:channel];

	return channel;
}

- (GLTTestClient *)historyClient
{
	GLTTestClient *client = [GLTTestClient testClient];

	[client enableCapability:ClientIRCv3SupportedCapabilityBatch];
	[client enableCapability:ClientIRCv3SupportedCapabilityServerTime];
	[client enableCapability:ClientIRCv3SupportedCapabilityMessageTags];
	[client enableCapability:ClientIRCv3SupportedCapabilityChatHistory];

	client.isLoggedIn = YES;

	return client;
}

- (TVCLogLine *)logLineWithMessageIdentifier:(nullable NSString *)messageIdentifier
									nickname:(NSString *)nickname
										text:(NSString *)text
										date:(NSDate *)date
{
	TVCLogLineMutable *logLine = [TVCLogLineMutable new];

	logLine.command = @"privmsg";
	logLine.lineType = TVCLogLineTypePrivateMessage;
	logLine.messageIdentifier = messageIdentifier;
	logLine.nickname = nickname;
	logLine.messageBody = text;
	logLine.receivedAt = date;

	return [logLine copy];
}

#pragma mark -
#pragma mark Capability and ISUPPORT

- (void)testChatHistoryIsRequestedOnlyWithItsDependencies
{
	GLTTestClient *client = [GLTTestClient testClient];

	[client receiveCapabilityOrAuthenticationRequest:
				[self message:@":irc.example.net CAP * LS :draft/chathistory draft/read-marker" onClient:client]];

	/* No batch, server-time or message-tags: chathistory stays out. */
	XCTAssertEqualObjects(client.sentCapabilityCommands, @[ @"REQ draft/read-marker" ]);

	GLTTestClient *complete = [GLTTestClient testClient];

	[complete receiveCapabilityOrAuthenticationRequest:
				  [self message:@":irc.example.net CAP * LS :batch server-time message-tags chathistory read-marker"
					   onClient:complete]];

	XCTAssertEqualObjects(complete.sentCapabilityCommands, @[ @"REQ message-tags" ]);
	XCTAssertEqualObjects(complete.pendingCapabilityRequests,
						  (@[ @"batch", @"chathistory", @"read-marker", @"server-time" ]));

	[complete receiveCapabilityOrAuthenticationRequest:[self message:@":irc.example.net CAP me ACK :chathistory"
															onClient:complete]];

	XCTAssertTrue([complete isCapabilityEnabled:ClientIRCv3SupportedCapabilityChatHistory]);
}

- (void)testChatHistoryLimitComesFromISupport
{
	GLTTestClient *client = [self historyClient];

	XCTAssertEqual(client.chatHistoryRequestLimit, 100);

	[client.supportInfo processConfigurationData:@"CHATHISTORY=50"];

	XCTAssertEqual(client.supportInfo.chatHistoryMaximumLines, 50);
	XCTAssertEqual(client.chatHistoryRequestLimit, 50);

	[client.supportInfo processConfigurationData:@"draft/CHATHISTORY=20"];

	XCTAssertEqual(client.chatHistoryRequestLimit, 20);

	/* The client never asks for more than its own batch size. */
	[client.supportInfo processConfigurationData:@"CHATHISTORY=1000"];

	XCTAssertEqual(client.chatHistoryRequestLimit, 100);
}

#pragma mark -
#pragma mark Requests

- (void)testLatestRequestUsesStarWithoutLocalScrollbackAndTimestampWithIt
{
	GLTTestClient *client = [self historyClient];

	IRCChannel *channel = [self channelNamed:@"#chat" onClient:client];

	[client requestChatHistoryForChannel:channel];

	XCTAssertEqualObjects(client.sentLines, @[ @"CHATHISTORY LATEST #chat * 100" ]);

	/* A line in the local store: only the gap after it is wanted. */
	NSDate *date = [NSDate dateWithTimeIntervalSince1970:1700000000.5];

	[TVCLogControllerHistoricLogSharedInstance() indexLogLine:[self logLineWithMessageIdentifier:@"m1"
																						nickname:@"a"
																							text:@"hi"
																							date:date]
													  forItem:channel];

	[client requestChatHistoryForChannel:channel];

	XCTAssertEqualObjects(client.sentLines.lastObject,
						  @"CHATHISTORY LATEST #chat timestamp=2023-11-14T22:13:20.500Z 100");
}

- (void)testLatestRequestNeedsTheCapability
{
	GLTTestClient *client = [GLTTestClient testClient];

	client.isLoggedIn = YES;

	IRCChannel *channel = [self channelNamed:@"#chat" onClient:client];

	[client requestChatHistoryForChannel:channel];

	XCTAssertEqual(client.sentLines.count, 0);
}

- (void)testBeforeRequestIsSentOncePerTargetUntilAnswered
{
	GLTTestClient *client = [self historyClient];

	IRCChannel *channel = [self channelNamed:@"#chat" onClient:client];

	NSDate *oldest = [NSDate dateWithTimeIntervalSince1970:1700000000];

	[client requestChatHistoryBeforeDate:oldest inChannel:channel];
	[client requestChatHistoryBeforeDate:oldest inChannel:channel];

	XCTAssertEqualObjects(client.sentLines, @[ @"CHATHISTORY BEFORE #chat timestamp=2023-11-14T22:13:20.000Z 100" ]);

	/* The reply releases the target for the next request. */
	[self feedLines:@[
		@":irc.example.net BATCH +h1 chathistory #chat",
		@"@batch=h1;msgid=x1;time=2023-11-14T22:00:00.000Z :a!u@h PRIVMSG #chat :older",
		@":irc.example.net BATCH -h1",
	]
		   toClient:client];

	XCTAssertEqual(client.processedMessages.count, 1);

	[client requestChatHistoryBeforeDate:[NSDate dateWithTimeIntervalSince1970:1699999200] inChannel:channel];

	XCTAssertEqual(client.sentLines.count, 2);
}

- (void)testFailedTargetIsReportedOnceAndNotRetried
{
	GLTTestClient *client = [self historyClient];

	IRCChannel *channel = [self channelNamed:@"#chat" onClient:client];

	[client receiveStandardReply:
				[self message:@":irc.example.net FAIL CHATHISTORY INVALID_TARGET LATEST #chat :No history for #chat"
					 onClient:client]];
	[client receiveStandardReply:
				[self message:@":irc.example.net FAIL CHATHISTORY INVALID_TARGET BEFORE #chat :No history for #chat"
					 onClient:client]];

	XCTAssertEqual(client.printedLines.count, 1);
	XCTAssertEqualObjects(client.printedLines[0][@"messageBody"],
						  @"FAIL CHATHISTORY/INVALID_TARGET: No history for #chat");

	[client requestChatHistoryForChannel:channel];
	[client requestChatHistoryBeforeDate:[NSDate date] inChannel:channel];

	XCTAssertEqual(client.sentLines.count, 0);
}

- (void)testChatHistoryWinsOverZNCPlayback
{
	GLTTestClient *client = [self historyClient];

	[client enableCapability:ClientIRCv3SupportedCapabilityPlayback];

	[client requestPlayback];

	XCTAssertEqual(client.sentLines.count, 0);

	/* Without chathistory the playback module is asked as before. */
	[client disableCapability:ClientIRCv3SupportedCapabilityChatHistory];

	[client requestPlayback];

	XCTAssertEqualObjects(client.sentLines, @[ @"PRIVMSG *playback :play * 0" ]);
}

- (void)testChatHistoryCommandIsPassedThrough
{
	GLTTestClient *client = [self historyClient];

	[client sendCommand:@"/chathistory AROUND #chat timestamp=2023-11-14T22:13:20.000Z 10"
		 completeTarget:NO
				 target:nil];

	XCTAssertEqualObjects(client.sentLines, @[ @"CHATHISTORY AROUND #chat timestamp=2023-11-14T22:13:20.000Z 10" ]);
}

#pragma mark -
#pragma mark Replay

- (void)testReplayedLinesAreHistoricAndDeduplicatedByMessageIdentifier
{
	GLTTestClient *client = [self historyClient];

	IRCChannel *channel = [self channelNamed:@"#chat" onClient:client];

	NSDate *date = [NSDate dateWithTimeIntervalSince1970:1700000000];

	[TVCLogControllerHistoricLogSharedInstance() indexLogLine:[self logLineWithMessageIdentifier:@"seen"
																						nickname:@"a"
																							text:@"one"
																							date:date]
													  forItem:channel];
	[TVCLogControllerHistoricLogSharedInstance() indexLogLine:[self logLineWithMessageIdentifier:nil
																						nickname:@"b"
																							text:@"two"
																							date:date]
													  forItem:channel];

	[self feedLines:@[
		@":irc.example.net BATCH +h1 chathistory #chat",
		@"@batch=h1;msgid=seen;time=2023-11-14T22:13:20.000Z :a!u@h PRIVMSG #chat :one",
		@"@batch=h1;time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two",
		@"@batch=h1;time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two again",
		@"@batch=h1;msgid=new;time=2023-11-14T22:13:21.000Z :c!u@h PRIVMSG #chat :three",
		@":irc.example.net BATCH -h1",
	]
		   toClient:client];

	NSArray<NSString *> *bodies = [client.processedMessages valueForKeyPath:@"sequence"];

	XCTAssertEqualObjects(bodies, (@[ @"two again", @"three" ]));

	for (IRCMessage *message in client.processedMessages) {
		XCTAssertTrue(message.isHistoric);
	}
}

- (void)testDuplicateCheckFallsBackToTimestampSenderAndText
{
	GLTTestClient *client = [self historyClient];

	IRCChannel *channel = [self channelNamed:@"#chat" onClient:client];

	NSDate *date = [NSDate dateWithTimeIntervalSince1970:1700000000];

	[TVCLogControllerHistoricLogSharedInstance() indexLogLine:[self logLineWithMessageIdentifier:nil
																						nickname:@"b"
																							text:@"two"
																							date:date]
													  forItem:channel];

	XCTAssertTrue(
		[client chatHistoryMessageIsDuplicate:[self message:@"@time=2023-11-14T22:13:20.000Z :b!u@h PRIVMSG #chat :two"
												   onClient:client]]);
	XCTAssertFalse(
		[client chatHistoryMessageIsDuplicate:[self message:@"@time=2023-11-14T22:13:20.000Z :c!u@h PRIVMSG #chat :two"
												   onClient:client]]);
	XCTAssertFalse(
		[client chatHistoryMessageIsDuplicate:[self message:@"@time=2023-11-14T22:13:21.000Z :b!u@h PRIVMSG #chat :two"
												   onClient:client]]);

	/* Without a server time there is nothing to match on. */
	XCTAssertFalse([client chatHistoryMessageIsDuplicate:[self message:@":b!u@h PRIVMSG #chat :two" onClient:client]]);
}

#pragma mark -
#pragma mark Read markers

- (void)testReceivedReadMarkerAtNewestLineClearsUnreadCounts
{
	GLTTestClient *client = [self historyClient];

	[client enableCapability:ClientIRCv3SupportedCapabilityReadMarker];

	IRCChannel *channel = [self channelNamed:@"#chat" onClient:client];

	NSDate *date = [NSDate dateWithTimeIntervalSince1970:1700000000];

	[TVCLogControllerHistoricLogSharedInstance() indexLogLine:[self logLineWithMessageIdentifier:@"r1"
																						nickname:@"a"
																							text:@"hi"
																							date:date]
													  forItem:channel];

	channel.treeUnreadCount = 3;
	channel.nicknameHighlightCount = 1;

	/* A marker before the newest line leaves the counts alone. */
	[client receiveReadMarker:[self message:@":irc.example.net MARKREAD #chat timestamp=2023-11-14T22:13:19.000Z"
								   onClient:client]];

	XCTAssertEqual(channel.treeUnreadCount, 3);
	XCTAssertEqual(channel.nicknameHighlightCount, 1);

	[client receiveReadMarker:[self message:@":irc.example.net MARKREAD #chat timestamp=2023-11-14T22:13:20.000Z"
								   onClient:client]];

	XCTAssertEqual(channel.treeUnreadCount, 0);
	XCTAssertEqual(channel.nicknameHighlightCount, 0);
	XCTAssertFalse(channel.isUnread);

	/* "*" means no marker and changes nothing. */
	channel.treeUnreadCount = 1;

	[client receiveReadMarker:[self message:@":irc.example.net MARKREAD #chat *" onClient:client]];

	XCTAssertEqual(channel.treeUnreadCount, 1);
}

- (void)testReadMarkerIsSentOncePerNewestLine
{
	GLTTestClient *client = [self historyClient];

	[client enableCapability:ClientIRCv3SupportedCapabilityReadMarker];

	IRCChannel *channel = [self channelNamed:@"#chat" onClient:client];

	/* Nothing to mark in an empty channel. */
	[client markChannelAsRead:channel];
	[client onReadMarkerTimer];

	XCTAssertEqual(client.sentLines.count, 0);

	NSDate *date = [NSDate dateWithTimeIntervalSince1970:1700000000];

	[TVCLogControllerHistoricLogSharedInstance() indexLogLine:[self logLineWithMessageIdentifier:@"r1"
																						nickname:@"a"
																							text:@"hi"
																							date:date]
													  forItem:channel];

	[client markChannelAsRead:channel];
	[client markChannelAsRead:channel];
	[client onReadMarkerTimer];

	XCTAssertEqualObjects(client.sentLines, @[ @"MARKREAD #chat timestamp=2023-11-14T22:13:20.000Z" ]);

	/* The same newest line is not reported twice. */
	[client markChannelAsRead:channel];
	[client onReadMarkerTimer];

	XCTAssertEqual(client.sentLines.count, 1);

	/* A newer line is. */
	[TVCLogControllerHistoricLogSharedInstance()
		indexLogLine:[self logLineWithMessageIdentifier:@"r2"
											   nickname:@"a"
												   text:@"again"
												   date:[date dateByAddingTimeInterval:5]]
			 forItem:channel];

	[client markChannelAsRead:channel];
	[client onReadMarkerTimer];

	XCTAssertEqualObjects(client.sentLines.lastObject, @"MARKREAD #chat timestamp=2023-11-14T22:13:25.000Z");
	XCTAssertEqual(client.sentLines.count, 2);
}

- (void)testReadMarkerIsQueriedOnActivation
{
	GLTTestClient *client = [self historyClient];

	[client enableCapability:ClientIRCv3SupportedCapabilityReadMarker];

	IRCChannel *channel = [self channelNamed:@"#chat" onClient:client];

	[client noteChannelActivated:channel];

	XCTAssertEqualObjects(client.sentLines, (@[ @"CHATHISTORY LATEST #chat * 100", @"MARKREAD #chat" ]));
}

- (void)testReadMarkerIsNotSentWithoutTheCapability
{
	GLTTestClient *client = [self historyClient];

	IRCChannel *channel = [self channelNamed:@"#chat" onClient:client];

	[TVCLogControllerHistoricLogSharedInstance() indexLogLine:[self logLineWithMessageIdentifier:@"r1"
																						nickname:@"a"
																							text:@"hi"
																							date:[NSDate date]]
													  forItem:channel];

	[client sendReadMarkerForChannel:channel];

	XCTAssertEqual(client.sentLines.count, 0);
}

#pragma mark -
#pragma mark Netsplit

static NSString *const _joinLeavePreferenceKey = @"DisplayEventInLogView -> Join, Part, Quit";

- (GLTTestClient *)netsplitClientShowingJoinsAndQuits:(BOOL)showJoinLeave
{
	/* The summary follows the join/quit print preference. */
	id previous = [RZUserDefaults() objectForKey:_joinLeavePreferenceKey];

	[self addTeardownBlock:^{
		if (previous) {
			[RZUserDefaults() setObject:previous forKey:_joinLeavePreferenceKey];
		} else {
			[RZUserDefaults() removeObjectForKey:_joinLeavePreferenceKey];
		}
	}];

	[RZUserDefaults() setBool:showJoinLeave forKey:_joinLeavePreferenceKey];

	GLTTestClient *client = [GLTTestClient testClient];

	[client enableCapability:ClientIRCv3SupportedCapabilityBatch];

	client.forwardsProcessedMessages = YES;

	return client;
}

- (void)testNetsplitSummaryIsHiddenWithJoinsAndQuits
{
	GLTTestClient *client = [self netsplitClientShowingJoinsAndQuits:NO];

	IRCChannel *channel = [self channelNamed:@"#chat" onClient:client];

	[channel activate];

	[self feedLines:@[ @":alice!u@h JOIN #chat" ] toClient:client];

	NSUInteger linesBefore = client.printedLines.count;

	[self feedLines:@[
		@":irc.example.net BATCH +ns netsplit irc.hub irc.leaf",
		@"@batch=ns :alice!u@h QUIT :irc.hub irc.leaf",
		@":irc.example.net BATCH -ns",
	]
		   toClient:client];

	XCTAssertFalse([channel memberExists:@"alice"]);
	XCTAssertEqual(client.printedLines.count, linesBefore);
}

- (void)testNetsplitBatchProducesOneSummaryLineAndUpdatesMembers
{
	GLTTestClient *client = [self netsplitClientShowingJoinsAndQuits:YES];

	IRCChannel *channel = [self channelNamed:@"#chat" onClient:client];

	[channel activate];

	[self feedLines:@[
		@":alice!u@h JOIN #chat",
		@":bob!u@h JOIN #chat",
		@":carol!u@h JOIN #chat",
	]
		   toClient:client];

	XCTAssertTrue([channel memberExists:@"alice"]);
	XCTAssertTrue([channel memberExists:@"bob"]);
	XCTAssertTrue([channel memberExists:@"carol"]);

	NSUInteger linesBefore = client.printedLines.count;

	[self feedLines:@[
		@":irc.example.net BATCH +ns netsplit irc.hub irc.leaf",
		@"@batch=ns :alice!u@h QUIT :irc.hub irc.leaf",
		@"@batch=ns :bob!u@h QUIT :irc.hub irc.leaf",
		@":irc.example.net BATCH -ns",
	]
		   toClient:client];

	XCTAssertFalse([channel memberExists:@"alice"]);
	XCTAssertFalse([channel memberExists:@"bob"]);
	XCTAssertTrue([channel memberExists:@"carol"]);

	NSArray<NSDictionary *> *newLines =
		[client.printedLines subarrayWithRange:NSMakeRange(linesBefore, client.printedLines.count - linesBefore)];

	XCTAssertEqual(newLines.count, 1);
	XCTAssertEqualObjects(newLines.firstObject[@"messageBody"],
						  @"Netsplit between \002irc.hub\002 and \002irc.leaf\002: 2 users left (alice, bob)");
	XCTAssertEqual([newLines.firstObject[@"lineType"] unsignedIntegerValue], TVCLogLineTypeQuit);
	XCTAssertEqual(newLines.firstObject[@"channel"], channel);

	/* The netjoin brings them back with one line as well. */
	linesBefore = client.printedLines.count;

	[self feedLines:@[
		@":irc.example.net BATCH +nj netjoin irc.hub irc.leaf",
		@"@batch=nj :alice!u@h JOIN #chat",
		@"@batch=nj :bob!u@h JOIN #chat",
		@":irc.example.net BATCH -nj",
	]
		   toClient:client];

	XCTAssertTrue([channel memberExists:@"alice"]);
	XCTAssertTrue([channel memberExists:@"bob"]);

	newLines =
		[client.printedLines subarrayWithRange:NSMakeRange(linesBefore, client.printedLines.count - linesBefore)];

	XCTAssertEqual(newLines.count, 1);
	XCTAssertEqualObjects(newLines.firstObject[@"messageBody"],
						  @"Netjoin between \002irc.hub\002 and \002irc.leaf\002: 2 users rejoined (alice, bob)");
	XCTAssertEqual([newLines.firstObject[@"lineType"] unsignedIntegerValue], TVCLogLineTypeJoin);
}

- (void)testNetsplitSummaryListsAtMostTenNicknames
{
	GLTTestClient *client = [self netsplitClientShowingJoinsAndQuits:YES];

	IRCChannel *channel = [self channelNamed:@"#chat" onClient:client];

	[channel activate];

	NSMutableArray<NSString *> *joins = [NSMutableArray array];
	NSMutableArray<NSString *> *quits = [NSMutableArray array];

	[quits addObject:@":irc.example.net BATCH +ns netsplit irc.hub irc.leaf"];

	for (NSUInteger i = 1; i <= 12; i++) {
		[joins addObject:[NSString stringWithFormat:@":user%lu!u@h JOIN #chat", (unsigned long)i]];
		[quits addObject:[NSString stringWithFormat:@"@batch=ns :user%lu!u@h QUIT :split", (unsigned long)i]];
	}

	[quits addObject:@":irc.example.net BATCH -ns"];

	[self feedLines:joins toClient:client];

	NSUInteger linesBefore = client.printedLines.count;

	[self feedLines:quits toClient:client];

	XCTAssertEqual(client.printedLines.count, linesBefore + 1);
	XCTAssertEqualObjects(client.printedLines.lastObject[@"messageBody"],
						  @"Netsplit between \002irc.hub\002 and \002irc.leaf\002: 12 users left "
						  @"(user1, user2, user3, user4, user5, user6, user7, user8, user9, user10, … and 2 more)");
	XCTAssertFalse([channel memberExists:@"user1"]);
	XCTAssertFalse([channel memberExists:@"user12"]);
}

@end

NS_ASSUME_NONNULL_END
