/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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
#import "IRCISupportInfoPrivate.h"
#import "IRCModeInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCModeInfoTests : XCTestCase
@end

@implementation IRCModeInfoTests

- (void)testConvenienceInitializers
{
	IRCModeInfo *unset = [[IRCModeInfo alloc] initWithModeSymbol:@"n"];
	IRCModeInfo *set = [[IRCModeInfo alloc] initWithModeSymbol:@"t" modeIsSet:YES];

	XCTAssertEqualObjects(unset.modeSymbol, @"n");
	XCTAssertFalse(unset.modeIsSet);
	XCTAssertNil(unset.modeParameter);
	XCTAssertEqualObjects(set.modeSymbol, @"t");
	XCTAssertTrue(set.modeIsSet);
}

- (void)testMutableCopyCanChangeWithoutChangingOriginal
{
	IRCModeInfo *original = [[IRCModeInfo alloc] initWithModeSymbol:@"k" modeIsSet:YES modeParameter:@"secret"];
	IRCModeInfoMutable *changed = [original mutableCopy];
	changed.modeIsSet = NO;
	changed.modeParameter = nil;

	XCTAssertFalse(original.mutable);
	XCTAssertTrue(changed.mutable);
	XCTAssertTrue(original.modeIsSet);
	XCTAssertEqualObjects(original.modeParameter, @"secret");
	XCTAssertFalse(changed.modeIsSet);
	XCTAssertNil(changed.modeParameter);
}

- (void)testUniqueCopyEntryPointsPreserveValuesAndRequestedMutability
{
	IRCModeInfo *original = [[IRCModeInfo alloc] initWithModeSymbol:@"k" modeIsSet:YES modeParameter:@"secret"];
	IRCModeInfo *unique = [original uniqueCopy];
	IRCModeInfoMutable *uniqueMutable = [original uniqueCopyMutable];

	XCTAssertNotEqual(unique, original);
	XCTAssertEqualObjects(unique, original);
	XCTAssertFalse(unique.mutable);
	XCTAssertTrue(uniqueMutable.mutable);
	XCTAssertEqualObjects(uniqueMutable, original);
}

- (void)testEqualityAndHashUseAllFields
{
	IRCModeInfo *first = [[IRCModeInfo alloc] initWithModeSymbol:@"k" modeIsSet:YES modeParameter:@"secret"];
	IRCModeInfoMutable *second = [first mutableCopy];

	XCTAssertEqualObjects(first, second);
	XCTAssertEqual(first.hash, second.hash);

	second.modeParameter = @"other";

	XCTAssertNotEqualObjects(first, second);
}

- (void)testMemberModeRequiresAParameterAndPrefixMode
{
	GLTTestClient *client = [GLTTestClient testClient];
	[client.supportInfo processConfigurationData:@"PREFIX=(ov)@+"];

	IRCModeInfo *memberMode = [[IRCModeInfo alloc] initWithModeSymbol:@"o" modeIsSet:YES modeParameter:@"nick"];
	IRCModeInfo *missingParameter = [[IRCModeInfo alloc] initWithModeSymbol:@"o" modeIsSet:YES];
	IRCModeInfo *channelMode = [[IRCModeInfo alloc] initWithModeSymbol:@"n" modeIsSet:YES modeParameter:@"nick"];

	XCTAssertTrue([memberMode isModeForChangingMemberModeOn:client]);
	XCTAssertFalse([missingParameter isModeForChangingMemberModeOn:client]);
	XCTAssertFalse([channelMode isModeForChangingMemberModeOn:client]);
}

@end

NS_ASSUME_NONNULL_END
