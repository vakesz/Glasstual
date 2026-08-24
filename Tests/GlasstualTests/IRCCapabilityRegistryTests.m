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

#import "IRCCapability.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCCapabilityRegistryTests : XCTestCase
@end

@implementation IRCCapabilityRegistryTests

- (IRCCapabilityRegistry *)registryWithGateAllowed:(BOOL)gateAllowed
{
	IRCCapability *tags = [IRCCapability capabilityNamed:@"message-tags"
											  identifier:ClientIRCv3SupportedCapabilityMessageTags];

	IRCCapability *gated = [[IRCCapability alloc] initWithName:@"echo-message"
													identifier:ClientIRCv3SupportedCapabilityEchoMessage
											requestedByDefault:YES
												preferenceGate:^BOOL {
													return gateAllowed;
												}
												  dependencies:nil
											   negotiationHook:nil];

	IRCCapability *dependent = [[IRCCapability alloc] initWithName:@"draft/typing"
														identifier:0
												requestedByDefault:YES
													preferenceGate:nil
													  dependencies:@[ @"message-tags" ]
												   negotiationHook:nil];

	IRCCapability *optional = [IRCCapability capabilityNamed:@"draft/opt-in" identifier:0 requestedByDefault:NO];

	return [[IRCCapabilityRegistry alloc] initWithCapabilities:@[ tags, gated, dependent, optional ]];
}

- (void)testParseCapabilityList
{
	NSDictionary *offered =
		[IRCCapabilityRegistry parseCapabilityList:@"multi-prefix SASL=PLAIN,EXTERNAL  cap-notify x="];

	XCTAssertEqualObjects(offered[@"multi-prefix"], @[]);
	XCTAssertEqualObjects(offered[@"sasl"], (@[ @"PLAIN", @"EXTERNAL" ]));
	XCTAssertEqualObjects(offered[@"cap-notify"], @[]);
	XCTAssertEqualObjects(offered[@"x"], @[]);
	XCTAssertEqual(offered.count, 4);

	NSDictionary *empty = @{};

	XCTAssertEqualObjects([IRCCapabilityRegistry parseCapabilityList:@""], empty);
}

- (void)testParseCapabilityListUsesLastDuplicateAndIgnoresEmptyNamesAndValues
{
	NSDictionary *offered = [IRCCapabilityRegistry parseCapabilityList:@"SASL=PLAIN sasl=EXTERNAL,,SCRAM-SHA-256 =bad"];

	XCTAssertEqualObjects(offered[@"sasl"], (@[ @"EXTERNAL", @"SCRAM-SHA-256" ]));
	XCTAssertEqual(offered.count, 1);
}

- (void)testLookupIsCaseInsensitive
{
	IRCCapabilityRegistry *registry = [self registryWithGateAllowed:YES];

	XCTAssertEqualObjects([registry capabilityNamed:@"Message-Tags"].name, @"message-tags");
	XCTAssertNil([registry capabilityNamed:@"unknown"]);
	XCTAssertEqualObjects([registry capabilityForIdentifier:ClientIRCv3SupportedCapabilityEchoMessage].name,
						  @"echo-message");
	XCTAssertNil([registry capabilityForIdentifier:ClientIRCv3SupportedCapabilityBatch]);
}

- (void)testRequestListRespectsPreferenceGate
{
	NSDictionary *offered = @{@"message-tags" : @[], @"echo-message" : @[]};

	NSArray<IRCCapability *> *allowed = [[self registryWithGateAllowed:YES] capabilitiesToRequestFromOffered:offered];

	XCTAssertEqualObjects([allowed valueForKey:@"name"], (@[ @"message-tags", @"echo-message" ]));

	NSArray<IRCCapability *> *denied = [[self registryWithGateAllowed:NO] capabilitiesToRequestFromOffered:offered];

	XCTAssertEqualObjects([denied valueForKey:@"name"], @[ @"message-tags" ]);

	XCTAssertTrue([[self registryWithGateAllowed:YES] isCapabilitySupported:@"echo-message"]);
	XCTAssertFalse([[self registryWithGateAllowed:NO] isCapabilitySupported:@"echo-message"]);
}

- (void)testRequestListRespectsDependencies
{
	IRCCapabilityRegistry *registry = [self registryWithGateAllowed:YES];

	NSArray<IRCCapability *> *withoutTags = [registry capabilitiesToRequestFromOffered:@{@"draft/typing" : @[]}];

	XCTAssertEqual(withoutTags.count, 0);

	NSArray<IRCCapability *> *withTags =
		[registry capabilitiesToRequestFromOffered:@{@"draft/typing" : @[], @"message-tags" : @[]}];

	XCTAssertEqualObjects([withTags valueForKey:@"name"], (@[ @"message-tags", @"draft/typing" ]));
}

- (void)testCapabilitiesNotRequestedByDefaultAreSkipped
{
	IRCCapabilityRegistry *registry = [self registryWithGateAllowed:YES];

	NSArray<IRCCapability *> *request = [registry capabilitiesToRequestFromOffered:@{@"draft/opt-in" : @[]}];

	XCTAssertEqual(request.count, 0);
}

- (void)testUnknownCapabilitiesAreNeverRequested
{
	IRCCapabilityRegistry *registry = [self registryWithGateAllowed:YES];

	NSArray<IRCCapability *> *request = [registry capabilitiesToRequestFromOffered:@{@"example.com/vendor" : @[]}];

	XCTAssertEqual(request.count, 0);
}

- (void)testCyclicDependenciesAreNeverRequested
{
	IRCCapability *first = [[IRCCapability alloc] initWithName:@"first"
													identifier:0
											requestedByDefault:YES
												preferenceGate:nil
												  dependencies:@[ @"second" ]
											   negotiationHook:nil];
	IRCCapability *second = [[IRCCapability alloc] initWithName:@"second"
													 identifier:0
											 requestedByDefault:YES
												 preferenceGate:nil
												   dependencies:@[ @"first" ]
												negotiationHook:nil];
	IRCCapabilityRegistry *registry = [[IRCCapabilityRegistry alloc] initWithCapabilities:@[ first, second ]];
	NSDictionary *offered = @{@"first" : @[], @"second" : @[]};

	XCTAssertEqual([registry capabilitiesToRequestFromOffered:offered].count, 0);
}

- (void)testDefaultRegistryContents
{
	IRCCapabilityRegistry *registry = [IRCCapabilityRegistry defaultRegistry];

	for (NSString *name in @[
			 @"away-notify",
			 @"batch",
			 @"cap-notify",
			 @"chghost",
			 @"echo-message",
			 @"message-tags",
			 @"multi-prefix",
			 @"sasl",
			 @"server-time",
			 @"standard-replies",
			 @"userhost-in-names",
			 @"znc.in/playback",
			 @"znc.in/self-message",
			 @"znc.in/server-time",
			 @"znc.in/server-time-iso",
			 @"znc.in/tlsinfo"
		 ]) {
		XCTAssertNotNil([registry capabilityNamed:name], @"%@ is missing from the default registry", name);
	}

	XCTAssertNil([registry capabilityNamed:@"identify-msg"]);
	XCTAssertNil([registry capabilityNamed:@"identify-ctcp"]);
	XCTAssertNil([registry capabilityNamed:@"plan.io/playback"]);

	XCTAssertNotNil([registry capabilityNamed:@"sasl"].negotiationHook);

	/* Vendor variants switch on the generic bit too. */
	ClientIRCv3SupportedCapability zncServerTime = [registry capabilityNamed:@"znc.in/server-time-iso"].identifier;

	XCTAssertEqual((zncServerTime & ClientIRCv3SupportedCapabilityServerTime),
				   ClientIRCv3SupportedCapabilityServerTime);

	ClientIRCv3SupportedCapability zncPlayback = [registry capabilityNamed:@"znc.in/playback"].identifier;

	XCTAssertEqual((zncPlayback & ClientIRCv3SupportedCapabilityPlayback), ClientIRCv3SupportedCapabilityPlayback);
}

@end

NS_ASSUME_NONNULL_END
