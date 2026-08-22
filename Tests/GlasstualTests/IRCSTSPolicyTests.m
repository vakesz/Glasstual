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

#import "IRCSTSPolicy.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCSTSPolicyTests : XCTestCase
@end

@implementation IRCSTSPolicyTests

- (IRCSTSPolicyStore *)store
{
	/* A nil user defaults store keeps everything in memory. */
	return [[IRCSTSPolicyStore alloc] initWithUserDefaults:nil];
}

#pragma mark -
#pragma mark Parsing

- (void)testParseFullCapabilityValues
{
	IRCSTSCapabilityValues *values =
		[IRCSTSCapabilityValues valuesFromCapabilityValues:@[ @"port=6697", @"duration=300", @"preload" ]];

	XCTAssertNotNil(values);
	XCTAssertEqual(values.port, 6697);
	XCTAssertTrue(values.hasDuration);
	XCTAssertEqual(values.duration, 300);
	XCTAssertTrue(values.preload);
}

- (void)testParseDurationOnly
{
	IRCSTSCapabilityValues *values = [IRCSTSCapabilityValues valuesFromCapabilityValues:@[ @"duration=0" ]];

	XCTAssertNotNil(values);
	XCTAssertEqual(values.port, 0);
	XCTAssertTrue(values.hasDuration);
	XCTAssertEqual(values.duration, 0);
	XCTAssertFalse(values.preload);
}

- (void)testParseRejectsInvalidPortAndUnknownKeys
{
	IRCSTSCapabilityValues *values =
		[IRCSTSCapabilityValues valuesFromCapabilityValues:@[ @"port=notaport", @"port=99999" ]];

	XCTAssertNotNil(values); // "port" was recognised even though invalid
	XCTAssertEqual(values.port, 0);

	XCTAssertNil([IRCSTSCapabilityValues valuesFromCapabilityValues:@[]]);
	XCTAssertNil([IRCSTSCapabilityValues valuesFromCapabilityValues:@[ @"vendor=thing" ]]);
}

#pragma mark -
#pragma mark Storage and expiry

- (void)testStoreAndRetrievePolicy
{
	IRCSTSPolicyStore *store = [self store];

	IRCSTSPolicy *policy = [[IRCSTSPolicy alloc] initWithPort:6697
													expiresAt:[NSDate dateWithTimeIntervalSinceNow:300]
													  preload:NO];

	[store setPolicy:policy forHost:@"irc.example.net"];

	IRCSTSPolicy *stored = [store policyForHost:@"IRC.EXAMPLE.NET"]; // Case insensitive

	XCTAssertNotNil(stored);
	XCTAssertEqual(stored.port, 6697);
}

- (void)testExpiredPolicyIsForgotten
{
	IRCSTSPolicyStore *store = [self store];

	IRCSTSPolicy *policy = [[IRCSTSPolicy alloc] initWithPort:6697
													expiresAt:[NSDate dateWithTimeIntervalSinceNow:-1]
													  preload:NO];

	[store setPolicy:policy forHost:@"irc.example.net"];

	XCTAssertNil([store policyForHost:@"irc.example.net"]);
}

#pragma mark -
#pragma mark Applying a policy to connection parameters

- (void)testApplyPolicyForcesSecuredConnectionOnPolicyPort
{
	IRCSTSPolicyStore *store = [self store];

	[store setPolicy:[[IRCSTSPolicy alloc] initWithPort:6697
											  expiresAt:[NSDate dateWithTimeIntervalSinceNow:300]
												preload:NO]
			 forHost:@"irc.example.net"];

	uint16_t port = 6667;
	BOOL secured = NO;

	BOOL applied = [store applyPolicyForHost:@"irc.example.net" toPort:&port secured:&secured];

	XCTAssertTrue(applied);
	XCTAssertEqual(port, 6697);
	XCTAssertTrue(secured);
}

- (void)testApplyPolicyNeverDowngrades
{
	IRCSTSPolicyStore *store = [self store];

	uint16_t port = 6697;
	BOOL secured = YES;

	/* No policy: parameters are left untouched, never downgraded. */
	BOOL applied = [store applyPolicyForHost:@"irc.example.net" toPort:&port secured:&secured];

	XCTAssertFalse(applied);
	XCTAssertEqual(port, 6697);
	XCTAssertTrue(secured);
}

#pragma mark -
#pragma mark Upgrade / store decisions

- (void)testPlaintextConnectionWithPortDecidesUpgrade
{
	IRCSTSPolicyStore *store = [self store];

	IRCSTSCapabilityValues *values =
		[IRCSTSCapabilityValues valuesFromCapabilityValues:@[ @"port=6697", @"duration=300" ]];

	uint16_t upgradePort = 0;

	IRCSTSPolicyAction action = [store applyCapabilityValues:values
													 forHost:@"irc.example.net"
											   connectedPort:6667
													 secured:NO
												 upgradePort:&upgradePort];

	XCTAssertEqual(action, IRCSTSPolicyActionUpgrade);
	XCTAssertEqual(upgradePort, 6697);

	/* Nothing is stored from an insecure connection. */
	XCTAssertNil([store policyForHost:@"irc.example.net"]);
}

- (void)testSecuredConnectionStoresPolicy
{
	IRCSTSPolicyStore *store = [self store];

	IRCSTSCapabilityValues *values = [IRCSTSCapabilityValues valuesFromCapabilityValues:@[ @"duration=300" ]];

	IRCSTSPolicyAction action = [store applyCapabilityValues:values
													 forHost:@"irc.example.net"
											   connectedPort:6697
													 secured:YES
												 upgradePort:NULL];

	XCTAssertEqual(action, IRCSTSPolicyActionStored);

	IRCSTSPolicy *policy = [store policyForHost:@"irc.example.net"];

	XCTAssertNotNil(policy);
	XCTAssertEqual(policy.port, 6697); // The connected port when none advertised
}

- (void)testSecuredConnectionWithZeroDurationClearsPolicy
{
	IRCSTSPolicyStore *store = [self store];

	[store setPolicy:[[IRCSTSPolicy alloc] initWithPort:6697
											  expiresAt:[NSDate dateWithTimeIntervalSinceNow:300]
												preload:NO]
			 forHost:@"irc.example.net"];

	IRCSTSCapabilityValues *values = [IRCSTSCapabilityValues valuesFromCapabilityValues:@[ @"duration=0" ]];

	IRCSTSPolicyAction action = [store applyCapabilityValues:values
													 forHost:@"irc.example.net"
											   connectedPort:6697
													 secured:YES
												 upgradePort:NULL];

	XCTAssertEqual(action, IRCSTSPolicyActionCleared);
	XCTAssertNil([store policyForHost:@"irc.example.net"]);
}

@end

NS_ASSUME_NONNULL_END
