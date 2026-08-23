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
#import "IRCMessage.h"
#import "IRCPrefix.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCMessageTests : XCTestCase
@end

@implementation IRCMessageTests

- (void)testParsesPrefixCommandAndTrailingParameter
{
	IRCMessage *message = [[IRCMessage alloc] initWithLine:@":nick!user@host PRIVMSG #channel :hello  world"];

	XCTAssertNotNil(message);
	XCTAssertEqualObjects(message.command, @"PRIVMSG");
	XCTAssertEqual(message.commandNumeric, 0);
	XCTAssertEqualObjects(message.senderNickname, @"nick");
	XCTAssertEqualObjects(message.senderUsername, @"user");
	XCTAssertEqualObjects(message.senderAddress, @"host");
	XCTAssertFalse(message.senderIsServer);
	XCTAssertEqual(message.paramsCount, 2);
	XCTAssertEqualObjects([message paramAt:0], @"#channel");
	XCTAssertEqualObjects([message paramAt:1], @"hello  world");
	NSDictionary *noTags = @{};

	XCTAssertEqualObjects(message.messageTags, noTags);
}

- (void)testParsesServerPrefixAndNumeric
{
	IRCMessage *message = [[IRCMessage alloc] initWithLine:@":irc.example.net 001 me :Welcome"];

	XCTAssertNotNil(message);
	XCTAssertEqual(message.commandNumeric, 1);
	XCTAssertTrue(message.senderIsServer);
	XCTAssertEqualObjects(message.senderNickname, @"irc.example.net");
	XCTAssertEqualObjects([message paramAt:1], @"Welcome");
}

- (void)testLowercaseCommandIsUppercased
{
	IRCMessage *message = [[IRCMessage alloc] initWithLine:@"ping :token"];

	XCTAssertEqualObjects(message.command, @"PING");
	XCTAssertEqualObjects([message paramAt:0], @"token");
}

- (void)testParsesTagsWithEscapes
{
	IRCMessage *message =
		[[IRCMessage alloc] initWithLine:@"@a=b\\:c\\sd\\\\e;flag;+draft/reply=x\\ny :nick!u@h TAGMSG #c"];

	XCTAssertNotNil(message);
	XCTAssertEqualObjects(message.command, @"TAGMSG");
	XCTAssertEqualObjects(message.messageTags[@"a"], @"b;c d\\e");
	XCTAssertEqualObjects(message.messageTags[@"flag"], @"");
	XCTAssertEqualObjects(message.messageTags[@"+draft/reply"], @"x\ny");
	XCTAssertEqualObjects([message paramAt:0], @"#c");
}

- (void)testEscapedBackslashFollowedByLetterIsNotAnEscape
{
	/* "\\s" is an escaped backslash followed by a literal s. */
	IRCMessage *message = [[IRCMessage alloc] initWithLine:@"@k=a\\\\sb PING :x"];

	XCTAssertEqualObjects(message.messageTags[@"k"], @"a\\sb");
}

- (void)testParsesMessageIdentifierAndAccount
{
	IRCMessage *message = [[IRCMessage alloc] initWithLine:@"@msgid=63E1033A0;account=alice :alice!a@h PRIVMSG #c :hi"];

	XCTAssertEqualObjects(message.messageIdentifier, @"63E1033A0");
	XCTAssertEqualObjects(message.senderAccount, @"alice");

	IRCMessage *plain = [[IRCMessage alloc] initWithLine:@":alice!a@h PRIVMSG #c :hi"];

	XCTAssertNil(plain.messageIdentifier);
	XCTAssertNil(plain.senderAccount);
}

- (void)testMessageIdentifierSurvivesCopy
{
	IRCMessage *message = [[IRCMessage alloc] initWithLine:@"@msgid=abc;account=bob :bob!b@h PRIVMSG #c :hi"];

	IRCMessageMutable *mutableCopy = [message mutableCopy];

	XCTAssertEqualObjects(mutableCopy.messageIdentifier, @"abc");
	XCTAssertEqualObjects(mutableCopy.senderAccount, @"bob");

	mutableCopy.messageIdentifier = @"def";

	IRCMessage *copy = [mutableCopy copy];

	XCTAssertEqualObjects(copy.messageIdentifier, @"def");
	XCTAssertEqualObjects(message.messageIdentifier, @"abc");
}

- (void)testServerTimeIsAppliedWhenCapabilityIsEnabled
{
	GLTTestClient *client = [GLTTestClient testClient];

	IRCMessage *ignored = [[IRCMessage alloc] initWithLine:@"@time=2024-01-02T03:04:05.000Z :n!u@h PRIVMSG #c :hi"
												  onClient:client];

	XCTAssertFalse(ignored.isHistoric);

	[client enableCapability:ClientIRCv3SupportedCapabilityServerTime];

	IRCMessage *message = [[IRCMessage alloc] initWithLine:@"@time=2024-01-02T03:04:05.000Z :n!u@h PRIVMSG #c :hi"
												  onClient:client];

	XCTAssertTrue(message.isHistoric);

	NSDateComponents *components = [NSDateComponents new];
	components.year = 2024;
	components.month = 1;
	components.day = 2;
	components.hour = 3;
	components.minute = 4;
	components.second = 5;
	components.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];

	NSDate *expected =
		[[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian] dateFromComponents:components];

	XCTAssertEqualWithAccuracy(message.receivedAt.timeIntervalSince1970, expected.timeIntervalSince1970, 0.001);
}

- (void)testMissingSenderFallsBackToServerAddress
{
	IRCMessage *message = [[IRCMessage alloc] initWithLine:@"NOTICE * :*** Looking up your hostname"];

	XCTAssertTrue(message.senderIsServer);
	XCTAssertEqualObjects(message.senderNickname, @"");
	XCTAssertEqualObjects([message paramAt:1], @"*** Looking up your hostname");
}

- (void)testEmptyTagSectionFailsToParse
{
	XCTAssertNil([[IRCMessage alloc] initWithLine:@"@ PING :x"]);
	XCTAssertNil([[IRCMessage alloc] initWithLine:@": PING :x"]);
	XCTAssertNil([[IRCMessage alloc] initWithLine:@""]);
}

@end

NS_ASSUME_NONNULL_END
