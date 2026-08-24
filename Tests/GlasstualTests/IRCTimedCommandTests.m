/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_
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
#import "IRCTimerCommandPrivate.h"
#import "IRCTreeItemPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCTimedCommandTests : XCTestCase
@end

@implementation IRCTimedCommandTests

- (void)testInitializationCapturesCommandContextAndUniqueIdentifiers
{
	GLTTestClient *client = [GLTTestClient testClient];
	IRCChannel *channel = [[IRCChannel alloc] initWithConfigDictionary:@{@"channelName" : @"#chat"}];

	channel.associatedClient = client;

	IRCTimedCommand *first = [[IRCTimedCommand alloc] initWithCommand:@"WHO #chat" onClient:client inChannel:channel];
	IRCTimedCommand *second = [[IRCTimedCommand alloc] initWithCommand:@"PING" onClient:client];

	XCTAssertEqualObjects(first.command, @"WHO #chat");
	XCTAssertEqualObjects(first.clientId, client.uniqueIdentifier);
	XCTAssertEqualObjects(first.channelId, channel.uniqueIdentifier);
	XCTAssertNil(second.channelId);
	XCTAssertNotEqualObjects(first.identifier, second.identifier);
}

- (void)testRestartRequiresPreviousStartAndPreservesTimerConfiguration
{
	GLTTestClient *client = [GLTTestClient testClient];
	IRCTimedCommand *command = [[IRCTimedCommand alloc] initWithCommand:@"PING" onClient:client];

	XCTAssertFalse(command.restart);

	[command start:30 onRepeat:YES iterations:3];

	XCTAssertTrue(command.timerIsActive);
	XCTAssertEqual(command.timerInterval, 30);
	XCTAssertTrue(command.repeatTimer);
	XCTAssertEqual(command.iterations, 3);

	[command stop];

	XCTAssertFalse(command.timerIsActive);
	XCTAssertTrue(command.restart);
	XCTAssertTrue(command.timerIsActive);

	[command stop];
}

@end

NS_ASSUME_NONNULL_END
