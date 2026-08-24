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

#import "IRCPrefix.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCPrefixTests : XCTestCase
@end

@implementation IRCPrefixTests

- (void)testDefaultsAreNonnullableEmptyStrings
{
	IRCPrefix *prefix = [IRCPrefix new];

	XCTAssertFalse(prefix.isServer);
	XCTAssertEqualObjects(prefix.nickname, @"");
	XCTAssertEqualObjects(prefix.hostmask, @"");
	XCTAssertNil(prefix.username);
	XCTAssertNil(prefix.address);
}

- (void)testMutableCopyCanChangeWithoutChangingOriginal
{
	IRCPrefixMutable *source = [IRCPrefixMutable new];
	source.isServer = YES;
	source.nickname = @"nick";
	source.username = @"user";
	source.address = @"host";
	source.hostmask = @"nick!user@host";

	IRCPrefix *immutable = [source copy];
	IRCPrefixMutable *changed = [immutable mutableCopy];
	changed.nickname = @"other";

	XCTAssertTrue(source.mutable);
	XCTAssertFalse(immutable.mutable);
	XCTAssertTrue(changed.mutable);
	XCTAssertEqualObjects(immutable.nickname, @"nick");
	XCTAssertEqualObjects(changed.nickname, @"other");
	XCTAssertEqualObjects(changed.username, @"user");
	XCTAssertEqualObjects(changed.address, @"host");
	XCTAssertEqualObjects(changed.hostmask, @"nick!user@host");
}

- (void)testUniqueCopyEntryPointsPreserveValuesAndRequestedMutability
{
	IRCPrefixMutable *source = [IRCPrefixMutable new];
	source.nickname = @"nick";
	source.hostmask = @"nick!user@host";

	IRCPrefix *immutable = [source copy];
	IRCPrefix *unique = [immutable uniqueCopy];
	IRCPrefixMutable *uniqueMutable = [immutable uniqueCopyMutable];

	XCTAssertNotEqual(unique, immutable);
	XCTAssertEqualObjects(unique, immutable);
	XCTAssertFalse(unique.mutable);
	XCTAssertTrue(uniqueMutable.mutable);
	XCTAssertEqualObjects(uniqueMutable, immutable);
}

- (void)testImmutableCopyReturnsSameObject
{
	IRCPrefixMutable *mutable = [IRCPrefixMutable new];
	mutable.nickname = @"nick";

	IRCPrefix *immutable = [mutable copy];

	XCTAssertEqual([immutable copy], immutable);
}

- (void)testEqualityAndHashUseAllFields
{
	IRCPrefixMutable *first = [IRCPrefixMutable new];
	first.nickname = @"nick";
	first.username = @"user";
	first.address = @"host";
	first.hostmask = @"nick!user@host";

	IRCPrefixMutable *second = [first mutableCopy];

	XCTAssertEqualObjects(first, second);
	XCTAssertEqual(first.hash, second.hash);

	second.isServer = YES;

	XCTAssertNotEqualObjects(first, second);
}

@end

NS_ASSUME_NONNULL_END
