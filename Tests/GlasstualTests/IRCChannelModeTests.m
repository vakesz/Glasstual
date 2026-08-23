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
#import "IRCChannelModePrivate.h"
#import "IRCChannelPrivate.h"
#import "IRCISupportInfoPrivate.h"
#import "IRCTreeItemPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCChannelModeTests : XCTestCase
@end

@implementation IRCChannelModeTests

- (IRCChannelMode *)channelModeWithCurrentModes:(NSString *)modeString
{
	GLTTestClient *client = [GLTTestClient testClient];

	[client.supportInfo processConfigurationData:@"CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+"];

	IRCChannel *channel = [[IRCChannel alloc] initWithConfigDictionary:@{@"channelName" : @"#chat"}];

	channel.associatedClient = client;

	IRCChannelMode *channelMode = [[IRCChannelMode alloc] initWithChannel:channel];

	[channelMode updateModes:modeString];

	return channelMode;
}

- (void)testRemovedModeParametersPrecedeAddedOnes
{
	IRCChannelMode *channelMode = [self channelModeWithCurrentModes:@"+nk secret"];

	IRCChannelModeContainer *modes = [channelMode.modes copy];

	[modes changeMode:@"k" modeIsSet:NO modeParameter:@"secret"];
	[modes changeMode:@"l" modeIsSet:YES modeParameter:@"10"];

	/* "-k+l secret 10": the server consumes parameters in the order
	 the letters appear. */
	XCTAssertEqualObjects([channelMode getChangeCommand:modes], @"-k+l secret 10");
}

- (void)testUnchangedModesProduceNoCommand
{
	IRCChannelMode *channelMode = [self channelModeWithCurrentModes:@"+nt"];

	XCTAssertEqualObjects([channelMode getChangeCommand:[channelMode.modes copy]], @"");
}

- (void)testModeStringListsParametersAfterLetters
{
	IRCChannelMode *channelMode = [self channelModeWithCurrentModes:@"+ntk secret +l 5"];

	XCTAssertEqualObjects(channelMode.string, @"+klnt secret 5");
	XCTAssertEqualObjects(channelMode.stringWithMaskedPassword, @"+klnt ****** 5");
}

@end

NS_ASSUME_NONNULL_END
