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
#import "IRCChannelMemberListControllerPrivate.h"
#import "IRCChannelUserPrivate.h"
#import "IRCUser.h"
#import "TVCMemberListPrivate.h"

NS_ASSUME_NONNULL_BEGIN

/* Row geometry of the member list: header rows are interleaved with
 member rows only while more than one rank is present, and every
 insertion and removal keeps the two in step. */
@interface TVCMemberListSectionTests : XCTestCase
@property(nonatomic, strong) GLTTestClient *client;
@property(nonatomic, strong) TVCMemberList *memberList;
@property(nonatomic, strong) IRCChannelMemberListController *controller;
@end

@implementation TVCMemberListSectionTests

- (void)setUp
{
	[super setUp];

	self.client = [GLTTestClient testClient];

	self.memberList = [[TVCMemberList alloc] initWithFrame:NSMakeRect(0.0, 0.0, 150.0, 400.0)];

	[self.memberList addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"member"]];

	[self.memberList awakeFromNib];

	self.controller = [IRCChannelMemberListController new];

	[self.controller setValue:self.memberList forKey:@"tableView"];

	[self.memberList setValue:self.controller forKey:@"contentController"];

	[self.controller replaceContents:@[]];
}

- (IRCChannelUser *)memberNamed:(NSString *)nickname modes:(NSString *)modes
{
	IRCUser *user = [[IRCUser alloc] initWithNickname:nickname onClient:self.client];

	IRCChannelUserMutable *member = [[IRCChannelUserMutable alloc] initWithUser:user];

	member.modes = modes;

	return [member copy];
}

- (void)insertMember:(IRCChannelUser *)member atIndex:(NSUInteger)index
{
	[self.controller insertObject:member atArrangedObjectIndex:index];
}

- (NSArray<NSString *> *)rowDescriptions
{
	NSMutableArray<NSString *> *rows = [NSMutableArray array];

	for (NSInteger row = 0; row < self.memberList.numberOfRows; row++) {
		if ([self.memberList isGroupRow:row]) {
			TVCMemberListSection *section = [self.memberList.dataSource tableView:self.memberList
														objectValueForTableColumn:nil
																			  row:row];

			[rows addObject:[NSString stringWithFormat:@"[%@]", section.title]];
		} else {
			IRCChannelUser *member = [self.memberList itemAtRow:row];

			[rows addObject:member.user.nickname];
		}
	}

	return rows;
}

- (void)testSingleRankIsAFlatList
{
	[self insertMember:[self memberNamed:@"alice" modes:@""] atIndex:0];
	[self insertMember:[self memberNamed:@"bob" modes:@""] atIndex:1];

	XCTAssertEqual(self.memberList.numberOfRows, 2);
	XCTAssertFalse([self.memberList isGroupRow:0]);
	XCTAssertEqualObjects([self rowDescriptions], (@[ @"alice", @"bob" ]));
}

- (void)testSecondRankAddsHeadersForEverySection
{
	[self insertMember:[self memberNamed:@"alice" modes:@""] atIndex:0];
	[self insertMember:[self memberNamed:@"bob" modes:@""] atIndex:1];

	/* The operator sorts first. */
	[self insertMember:[self memberNamed:@"carol" modes:@"o"] atIndex:0];

	XCTAssertEqualObjects([self rowDescriptions], (@[ @"[Operators]", @"carol", @"[Members]", @"alice", @"bob" ]));

	XCTAssertTrue([self.memberList isGroupRow:0]);
	XCTAssertTrue([self.memberList isGroupRow:2]);
	XCTAssertEqual([self.memberList rowForMemberAtIndex:0], 1);
	XCTAssertEqual([self.memberList rowForMemberAtIndex:1], 3);
	XCTAssertEqual([self.memberList rowForMemberAtIndex:2], 4);
	XCTAssertNil([self.memberList itemAtRow:2]);
}

- (void)testRowForItemMatchesItemAtRow
{
	IRCChannelUser *alice = [self memberNamed:@"alice" modes:@""];
	IRCChannelUser *carol = [self memberNamed:@"carol" modes:@"o"];
	IRCChannelUser *dave = [self memberNamed:@"dave" modes:@"v"];

	[self insertMember:alice atIndex:0];
	[self insertMember:carol atIndex:0];
	[self insertMember:dave atIndex:1];

	for (IRCChannelUser *member in @[ alice, carol, dave ]) {
		NSInteger row = [self.memberList rowForItem:member];

		XCTAssertEqual([self.memberList itemAtRow:row], member);
	}
}

- (void)testRemovingLastMemberOfASectionDropsItsHeader
{
	[self insertMember:[self memberNamed:@"alice" modes:@""] atIndex:0];
	[self insertMember:[self memberNamed:@"carol" modes:@"o"] atIndex:0];
	[self insertMember:[self memberNamed:@"dave" modes:@"v"] atIndex:1];

	XCTAssertEqualObjects([self rowDescriptions],
						  (@[ @"[Operators]", @"carol", @"[Voiced]", @"dave", @"[Members]", @"alice" ]));

	[self.controller removeObjectAtArrangedObjectIndex:1]; // dave

	XCTAssertEqualObjects([self rowDescriptions], (@[ @"[Operators]", @"carol", @"[Members]", @"alice" ]));

	[self.controller removeObjectAtArrangedObjectIndex:0]; // carol

	XCTAssertEqualObjects([self rowDescriptions], (@[ @"alice" ]));
	XCTAssertEqual(self.memberList.numberOfRows, 1);
}

- (void)testReplacingContentsRebuildsSections
{
	NSArray *members = @[
		[self memberNamed:@"carol" modes:@"o"],
		[self memberNamed:@"alice" modes:@""],
		[self memberNamed:@"bob" modes:@""],
	];

	[self.controller replaceContents:members];

	XCTAssertEqualObjects([self rowDescriptions], (@[ @"[Operators]", @"carol", @"[Members]", @"alice", @"bob" ]));

	[self.controller replaceContents:@[]];

	XCTAssertEqual(self.memberList.numberOfRows, 0);
}

- (void)testHeaderRowsAreNeitherSelectableNorTypeSelectable
{
	[self insertMember:[self memberNamed:@"alice" modes:@""] atIndex:0];
	[self insertMember:[self memberNamed:@"carol" modes:@"o"] atIndex:0];

	XCTAssertFalse([self.memberList.delegate tableView:self.memberList shouldSelectRow:0]);
	XCTAssertTrue([self.memberList.delegate tableView:self.memberList shouldSelectRow:1]);

	XCTAssertNil([self.memberList.delegate tableView:self.memberList typeSelectStringForTableColumn:nil row:0]);
	XCTAssertEqualObjects([self.memberList.delegate tableView:self.memberList typeSelectStringForTableColumn:nil row:1],
						  @"carol");
}

@end

NS_ASSUME_NONNULL_END
