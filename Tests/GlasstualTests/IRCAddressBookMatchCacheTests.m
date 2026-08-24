/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
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
#import "IRCAddressBook.h"
#import "IRCAddressBookMatchCachePrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCAddressBookMatchCacheTests : XCTestCase
@property(nonatomic, strong) GLTTestClient *client;
@end

@implementation IRCAddressBookMatchCacheTests

- (IRCAddressBookMatchCache *)cacheWithIgnoreList:(NSArray<NSDictionary<NSString *, id> *> *)ignoreList
{
	self.client = [GLTTestClient testClientWithConfigDictionary:@{@"ignoreList" : ignoreList}];

	return [[IRCAddressBookMatchCache alloc] initWithClient:self.client];
}

- (void)testSingleMatchingEntryIsReturned
{
	IRCAddressBookMatchCache *cache = [self cacheWithIgnoreList:@[ @{
												@"entryType" : @(IRCAddressBookEntryTypeIgnore),
												@"hostmask" : @"nick!*@example.com",
												@"ignorePrivateMessages" : @YES
											} ]];

	IRCAddressBookEntry *match = [cache findAddressBookEntryForHostmask:@"Nick!user@example.com"];

	XCTAssertNotNil(match);
	XCTAssertEqual(match.entryType, IRCAddressBookEntryTypeIgnore);
	XCTAssertTrue(match.ignorePrivateMessages);
	XCTAssertEqual([cache findIgnoresForHostmask:@"Nick!user@example.com"].count, 1);
}

- (void)testMultipleMatchesAreMerged
{
	IRCAddressBookMatchCache *cache = [self cacheWithIgnoreList:@[
		@{
			@"entryType" : @(IRCAddressBookEntryTypeIgnore),
			@"hostmask" : @"*!user@example.com",
			@"ignorePrivateMessages" : @YES
		},
		@{
			@"entryType" : @(IRCAddressBookEntryTypeIgnore),
			@"hostmask" : @"nick!*@example.com",
			@"ignorePublicMessages" : @YES
		}
	]];

	IRCAddressBookEntry *match = [cache findAddressBookEntryForHostmask:@"nick!user@example.com"];

	XCTAssertEqual(match.entryType, IRCAddressBookEntryTypeMixed);
	XCTAssertEqual(match.parentEntries.count, 2);
	XCTAssertTrue(match.ignorePrivateMessages);
	XCTAssertTrue(match.ignorePublicMessages);
	XCTAssertEqual([cache findIgnoresForHostmask:@"nick!user@example.com"].count, 2);
	XCTAssertTrue(match == [cache findAddressBookEntryForHostmask:@"nick!user@example.com"]);
}

- (void)testAbsentMatchReturnsNilAndNoIgnores
{
	IRCAddressBookMatchCache *cache = [self cacheWithIgnoreList:@[
		@{@"entryType" : @(IRCAddressBookEntryTypeIgnore), @"hostmask" : @"nick!*@example.com"}
	]];

	XCTAssertNil([cache findAddressBookEntryForHostmask:@"someone!user@elsewhere.test"]);
	XCTAssertEqual([cache findIgnoresForHostmask:@"someone!user@elsewhere.test"].count, 0);

	[cache clearCachedMatchesForHostmask:@"someone!user@elsewhere.test"];
	[cache clearCachedMatches];
}

@end

NS_ASSUME_NONNULL_END
