/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "IRCAddressBook.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCAddressBookTests : XCTestCase
@end

@implementation IRCAddressBookTests

- (void)testIgnoreEntryTreatsRegularExpressionCharactersLiterally
{
	IRCAddressBookEntry *entry = [IRCAddressBookEntry newIgnoreEntryForHostmask:@"nick[1]!*@example.com"];

	XCTAssertTrue([entry checkMatch:@"NICK[1]!user@example.com"]);
	XCTAssertFalse([entry checkMatch:@"nick1!user@example.com"]);
	XCTAssertEqualObjects(entry.hostmaskRegularExpression, @"^nick\\[1]!.*?@example\\.com$");
}

- (void)testIgnoreEntrySupportsIRCWildcardsAndAnchorsTheMatch
{
	IRCAddressBookEntry *entry = [IRCAddressBookEntry newIgnoreEntryForHostmask:@"n?ck!*@*.example"];

	XCTAssertTrue([entry checkMatch:@"nick!user@irc.example"]);
	XCTAssertFalse([entry checkMatch:@"prefix-nick!user@irc.example"]);
	XCTAssertFalse([entry checkMatch:@"noock!user@irc.example"]);
}

- (void)testUserTrackingEntryDerivesNicknameAndMatchesFullHostmask
{
	IRCAddressBookEntryMutable *entry = [IRCAddressBookEntryMutable newUserTrackingEntry];

	entry.hostmask = @"Alice";

	XCTAssertEqualObjects(entry.trackingNickname, @"Alice");
	XCTAssertTrue([entry checkMatch:@"alice!user@example.com"]);
	XCTAssertFalse([entry checkMatch:@"alice"]);
}

- (void)testMixedEntryHasNoMatcherState
{
	IRCAddressBookEntryMutable *entry = [IRCAddressBookEntryMutable newIgnoreEntry];

	entry.entryType = IRCAddressBookEntryTypeMixed;

	XCTAssertEqualObjects(entry.hostmaskRegularExpression, @"");
	XCTAssertNil(entry.trackingNickname);
	XCTAssertFalse([entry checkMatch:@""]);
}

@end

NS_ASSUME_NONNULL_END
