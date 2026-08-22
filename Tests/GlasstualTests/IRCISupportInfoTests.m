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
#import "IRCISupportInfoPrivate.h"
#import "IRCModeInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCISupportInfo (GLTTestAccess)
- (BOOL)modeHasParameter:(NSString *)modeSymbol whenModeIsSet:(BOOL)whenModeIsSet;
@end

@interface IRCISupportInfoTests : XCTestCase
@end

@implementation IRCISupportInfoTests

- (IRCISupportInfo *)supportInfoWithConfiguration:(NSString *)configuration
{
	GLTTestClient *client = [GLTTestClient testClient];

	IRCISupportInfo *supportInfo = [[IRCISupportInfo alloc] initWithClient:client];

	[supportInfo processConfigurationData:configuration];

	return supportInfo;
}

- (void)testDefaultCaseMappingIsRFC1459
{
	IRCISupportInfo *supportInfo = [self supportInfoWithConfiguration:@"NETWORK=Example"];

	XCTAssertEqual(supportInfo.caseMapping, IRCISupportInfoCaseMappingRFC1459);
	XCTAssertEqualObjects([supportInfo casefoldString:@"Nick[]\\~"], @"nick{}|^");
}

- (void)testASCIICaseMappingLeavesBracketsAlone
{
	IRCISupportInfo *supportInfo = [self supportInfoWithConfiguration:@"CASEMAPPING=ascii"];

	XCTAssertEqual(supportInfo.caseMapping, IRCISupportInfoCaseMappingASCII);
	XCTAssertEqualObjects([supportInfo casefoldString:@"Nick[]\\~"], @"nick[]\\~");
}

- (void)testStrictRFC1459DoesNotFoldTilde
{
	IRCISupportInfo *supportInfo = [self supportInfoWithConfiguration:@"CASEMAPPING=strict-rfc1459"];

	XCTAssertEqual(supportInfo.caseMapping, IRCISupportInfoCaseMappingStrictRFC1459);
	XCTAssertEqualObjects([supportInfo casefoldString:@"A[]\\~"], @"a{}|~");
}

- (void)testNonASCIICharactersAreNotFolded
{
	IRCISupportInfo *rfc = [self supportInfoWithConfiguration:@"CASEMAPPING=rfc1459"];
	IRCISupportInfo *ascii = [self supportInfoWithConfiguration:@"CASEMAPPING=ascii"];

	XCTAssertEqualObjects([rfc casefoldString:@"ÄbÇ"], @"ÄbÇ");
	XCTAssertEqualObjects([rfc casefoldString:@"ÄB[Ç]"], @"Äb{Ç}");
	XCTAssertEqualObjects([ascii casefoldString:@"ÄbÇ"], @"ÄbÇ");
	XCTAssertEqualObjects([ascii casefoldString:@"ŞİRİN"], @"Şİrİn");
}

- (void)testChannelModesAreParsedIntoParameterClasses
{
	IRCISupportInfo *supportInfo = [self supportInfoWithConfiguration:@"CHANMODES=beI,k,l,imnpst"];

	XCTAssertEqualObjects(supportInfo.channelModes[@"b"], @(1));
	XCTAssertEqualObjects(supportInfo.channelModes[@"k"], @(2));
	XCTAssertEqualObjects(supportInfo.channelModes[@"l"], @(3));
	XCTAssertEqualObjects(supportInfo.channelModes[@"t"], @(4));

	XCTAssertTrue([supportInfo modeHasParameter:@"b" whenModeIsSet:YES]);
	XCTAssertTrue([supportInfo modeHasParameter:@"b" whenModeIsSet:NO]);
	XCTAssertTrue([supportInfo modeHasParameter:@"k" whenModeIsSet:NO]);
	XCTAssertTrue([supportInfo modeHasParameter:@"l" whenModeIsSet:YES]);
	XCTAssertFalse([supportInfo modeHasParameter:@"l" whenModeIsSet:NO]);
	XCTAssertFalse([supportInfo modeHasParameter:@"t" whenModeIsSet:YES]);
}

- (void)testPrefixIsParsedInRankOrder
{
	IRCISupportInfo *supportInfo = [self supportInfoWithConfiguration:@"PREFIX=(qaohv)~&@%+"];

	XCTAssertEqualObjects(supportInfo.userModeSymbols[IRCISupportUserModeSymbolsSymbolsKey],
						  (@[ @"q", @"a", @"o", @"h", @"v" ]));
	XCTAssertEqualObjects(supportInfo.userModeSymbols[IRCISupportUserModeSymbolsCharactersKey],
						  (@[ @"~", @"&", @"@", @"%", @"+" ]));

	XCTAssertEqualObjects([supportInfo modeSymbolForUserPrefix:@"@"], @"o");
	XCTAssertEqualObjects([supportInfo userPrefixForModeSymbol:@"v"], @"+");
	XCTAssertTrue([supportInfo characterIsUserPrefix:@"%"]);
	XCTAssertFalse([supportInfo characterIsUserPrefix:@"#"]);
	XCTAssertEqual([supportInfo rankForUserPrefixWithMode:@"q"], IRCISupportInfoHighestUserPrefixRank);
	XCTAssertTrue([supportInfo rankForUserPrefixWithMode:@"v"] < [supportInfo rankForUserPrefixWithMode:@"o"]);

	/* Prefix modes always take a parameter. */
	XCTAssertTrue([supportInfo modeHasParameter:@"o" whenModeIsSet:NO]);
}

- (void)testParseModesUsesChannelModeClasses
{
	IRCISupportInfo *supportInfo = [self supportInfoWithConfiguration:@"CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+"];

	NSArray<IRCModeInfo *> *modes = [supportInfo parseModes:@"+nt-k+l secret 10"];

	XCTAssertEqual(modes.count, 4);

	XCTAssertEqualObjects(modes[0].modeSymbol, @"n");
	XCTAssertTrue(modes[0].modeIsSet);
	XCTAssertEqualObjects(modes[2].modeSymbol, @"k");
	XCTAssertFalse(modes[2].modeIsSet);
	XCTAssertEqualObjects(modes[2].modeParameter, @"secret");
	XCTAssertEqualObjects(modes[3].modeSymbol, @"l");
	XCTAssertEqualObjects(modes[3].modeParameter, @"10");
}

@end

NS_ASSUME_NONNULL_END
