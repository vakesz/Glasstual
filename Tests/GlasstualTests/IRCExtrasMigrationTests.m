/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "IRCExtrasPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCExtrasMigrationTests : XCTestCase
@end

@implementation IRCExtrasMigrationTests

- (void)testParseIRCProtocolURIRejectsMalformedSlashCounts
{
	/* Too few slashes — should no-op without crashing. */
	XCTAssertNoThrow([IRCExtras parseIRCProtocolURI:@"irc:example"]);
	/* Too many slashes — should no-op without crashing. */
	XCTAssertNoThrow([IRCExtras parseIRCProtocolURI:@"irc://a/b/c/d"]);
}

- (void)testParseIRCProtocolURIAcceptsBasicIrcURL
{
	/* Parsing only: connection creation is a no-op under XCTest so the
	 host app's saved servers are not mutated and merge prompts are skipped. */
	XCTAssertNoThrow([IRCExtras parseIRCProtocolURI:@"irc://irc.example.test/#chat"]);
}

@end

NS_ASSUME_NONNULL_END
