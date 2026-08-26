/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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
#import "IRCTreeItemPrivate.h"
#import "IRCTypingTrackerPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCTypingTrackerTests : XCTestCase
@property(nonatomic, strong) GLTTestClient *client;
@property(nonatomic, strong) IRCTypingTracker *tracker;
@end

@implementation IRCTypingTrackerTests

- (void)setUp
{
	[super setUp];

	self.client = [GLTTestClient testClient];
	self.tracker = [[IRCTypingTracker alloc] initWithClient:self.client];
}

- (void)tearDown
{
	[self.tracker removeAll];

	[super tearDown];
}

- (IRCChannel *)channelNamed:(NSString *)name
{
	IRCChannel *channel = [[IRCChannel alloc] initWithConfigDictionary:@{@"channelName" : name}];

	channel.associatedClient = self.client;

	return channel;
}

- (void)testStateParsing
{
	XCTAssertEqual([IRCTypingTracker stateForTagValue:@"active"], IRCTypingStateActive);
	XCTAssertEqual([IRCTypingTracker stateForTagValue:@"paused"], IRCTypingStatePaused);
	XCTAssertEqual([IRCTypingTracker stateForTagValue:@"ACTIVE"], IRCTypingStateDone);
	XCTAssertEqual([IRCTypingTracker stateForTagValue:@"done"], IRCTypingStateDone);
	XCTAssertEqual([IRCTypingTracker stateForTagValue:nil], IRCTypingStateDone);
}

- (void)testOrderingCaseFoldingAndNotificationSuppression
{
	IRCChannel *channel = [self channelNamed:@"#chat"];
	NSDate *start = [NSDate dateWithTimeIntervalSince1970:1000.0];
	__block NSUInteger notificationCount = 0;
	__block IRCChannel *notifiedChannel = nil;

	id token = [RZNotificationCenter() addObserverForName:IRCTypingTrackerDidChangeNotification
												   object:self.client
													queue:nil
											   usingBlock:^(NSNotification *notification) {
												   notificationCount += 1;
												   notifiedChannel = notification.userInfo[IRCTypingTrackerChannelKey];
											   }];

	[self.tracker noteTypingState:IRCTypingStateActive fromNickname:@"Alice" inChannel:channel atDate:start];
	[self.tracker noteTypingState:IRCTypingStateActive
					 fromNickname:@"bob"
						inChannel:channel
						   atDate:[start dateByAddingTimeInterval:1.0]];
	[self.tracker noteTypingState:IRCTypingStatePaused
					 fromNickname:@"ALICE"
						inChannel:channel
						   atDate:[start dateByAddingTimeInterval:2.0]];
	[self.tracker noteTypingState:IRCTypingStatePaused
					 fromNickname:@"alice"
						inChannel:channel
						   atDate:[start dateByAddingTimeInterval:3.0]];

	XCTAssertEqualObjects([self.tracker typingNicknamesInChannel:channel atDate:[start dateByAddingTimeInterval:4.0]],
						  (@[ @"Alice", @"bob" ]));
	XCTAssertEqual(notificationCount, 3u);
	XCTAssertEqual(notifiedChannel, channel);

	[RZNotificationCenter() removeObserver:token];
}

- (void)testEmptyNicknameIsIgnored
{
	IRCChannel *channel = [self channelNamed:@"#chat"];
	__block NSUInteger notificationCount = 0;

	id token = [RZNotificationCenter() addObserverForName:IRCTypingTrackerDidChangeNotification
												   object:self.client
													queue:nil
											   usingBlock:^(NSNotification *notification) {
												   notificationCount += 1;
											   }];

	[self.tracker noteTypingState:IRCTypingStateActive fromNickname:@"" inChannel:channel];

	XCTAssertEqualObjects([self.tracker typingNicknamesInChannel:channel], @[]);
	XCTAssertEqual(notificationCount, 0u);

	[RZNotificationCenter() removeObserver:token];
}

- (void)testRemoveNicknameAcrossChannels
{
	IRCChannel *firstChannel = [self channelNamed:@"#one"];
	IRCChannel *secondChannel = [self channelNamed:@"#two"];
	NSDate *start = [NSDate date];

	[self.tracker noteTypingState:IRCTypingStateActive fromNickname:@"Mara" inChannel:firstChannel atDate:start];
	[self.tracker noteTypingState:IRCTypingStatePaused fromNickname:@"mara" inChannel:secondChannel atDate:start];

	[self.tracker removeNickname:@"MARA"];

	XCTAssertEqualObjects([self.tracker typingNicknamesInChannel:firstChannel atDate:start], @[]);
	XCTAssertEqualObjects([self.tracker typingNicknamesInChannel:secondChannel atDate:start], @[]);
}

- (void)testTimeoutBoundaryAndExplicitExpiry
{
	IRCChannel *channel = [self channelNamed:@"#chat"];
	NSDate *start = [NSDate dateWithTimeIntervalSince1970:1000.0];

	[self.tracker noteTypingState:IRCTypingStateActive fromNickname:@"active" inChannel:channel atDate:start];
	[self.tracker noteTypingState:IRCTypingStatePaused fromNickname:@"paused" inChannel:channel atDate:start];

	XCTAssertEqualObjects([self.tracker typingNicknamesInChannel:channel atDate:[start dateByAddingTimeInterval:6.0]],
						  (@[ @"active", @"paused" ]));

	[self.tracker expireEntriesAtDate:[start dateByAddingTimeInterval:6.001]];

	XCTAssertEqualObjects([self.tracker typingNicknamesInChannel:channel atDate:[start dateByAddingTimeInterval:30.0]],
						  @[ @"paused" ]);

	[self.tracker expireEntriesAtDate:[start dateByAddingTimeInterval:30.001]];

	XCTAssertEqualObjects([self.tracker typingNicknamesInChannel:channel atDate:start], @[]);
}

@end

NS_ASSUME_NONNULL_END
