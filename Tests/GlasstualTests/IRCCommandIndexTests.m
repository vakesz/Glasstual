/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
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

#import "IRCCommandIndexPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCCommandIndexTests : XCTestCase
@end

@implementation IRCCommandIndexTests

+ (void)setUp
{
	[super setUp];

	[IRCCommandIndex populateCommandIndex];
}

- (void)testCommandIndexesAreCaseInsensitive
{
	XCTAssertEqual([IRCCommandIndex indexOfRemoteCommand:@"privmsg"], IRCRemoteCommandPrivmsg);
	XCTAssertEqual([IRCCommandIndex indexOfRemoteCommand:@"PRIVMSG"], IRCRemoteCommandPrivmsg);
	XCTAssertEqual([IRCCommandIndex indexOfLocalCommand:@"join"], IRCLocalCommandJoin);
	XCTAssertEqual([IRCCommandIndex indexOfLocalCommand:@"JOIN"], IRCLocalCommandJoin);
}

- (void)testUnknownCommandsReturnNotFound
{
	XCTAssertEqual([IRCCommandIndex indexOfRemoteCommand:@"not-a-command"], NSNotFound);
	XCTAssertEqual([IRCCommandIndex indexOfLocalCommand:@"not-a-command"], NSNotFound);
	XCTAssertEqual([IRCCommandIndex colonPositionForRemoteCommand:@"not-a-command"], NSNotFound);
}

- (void)testOutgoingColonPositionsComeFromRemoteCommandMetadata
{
	XCTAssertEqual([IRCCommandIndex colonPositionForRemoteCommand:@"PRIVMSG"], 1);
	XCTAssertEqual([IRCCommandIndex colonPositionForRemoteCommand:@"FAIL"], 2);
	XCTAssertEqual([IRCCommandIndex colonPositionForRemoteCommand:@"PASS"], NSNotFound);
}

- (void)testLocalCommandSyntaxAndCompletionList
{
	XCTAssertEqualObjects([IRCCommandIndex syntaxForLocalCommand:@"away"], @"AWAY [comment]");
	XCTAssertEqualObjects([IRCCommandIndex syntaxForLocalCommand:@"back"], @"BACK");
	XCTAssertNil([IRCCommandIndex syntaxForLocalCommand:@"not-a-command"]);

	NSArray<NSString *> *commands = [IRCCommandIndex localCommandList];

	XCTAssertTrue([commands containsObject:@"JOIN"]);
	XCTAssertFalse([commands containsObject:@"Reserved Information"]);
}

@end

NS_ASSUME_NONNULL_END
