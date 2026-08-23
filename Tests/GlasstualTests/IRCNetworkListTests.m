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

#import "IRCNetworkList.h"
#import "TPCPreferencesLocal.h"
#import "TPCPreferencesLocalPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCNetworkListTests : XCTestCase
@end

@implementation IRCNetworkListTests

#pragma mark -
#pragma mark Bundled List

- (void)testBundledListParses
{
	IRCNetworkList *list = [IRCNetworkList new];

	XCTAssertGreaterThan(list.listOfNetworks.count, 20u);

	for (IRCNetwork *network in list.listOfNetworks) {
		XCTAssertGreaterThan(network.networkName.length, 0u);
		XCTAssertGreaterThan(network.serverAddress.length, 0u, @"%@ has no address", network.networkName);
		XCTAssertNotEqual(network.serverPort, 0, @"%@ has no port", network.networkName);
		XCTAssertNotNil(network.networkDescription);
		XCTAssertNotNil(network.suggestedChannels);
	}
}

- (void)testBundledListIsSortedAlphabetically
{
	IRCNetworkList *list = [IRCNetworkList new];

	NSArray<IRCNetwork *> *networks = list.listOfNetworks;

	for (NSUInteger i = 1; i < networks.count; i++) {
		NSComparisonResult result = [networks[i - 1].networkName caseInsensitiveCompare:networks[i].networkName];

		XCTAssertNotEqual(
			result, NSOrderedDescending, @"%@ sorts after %@", networks[i - 1].networkName, networks[i].networkName);
	}
}

- (void)testPopularSubsetIsPresentAndOrdered
{
	IRCNetworkList *list = [IRCNetworkList new];

	NSArray<NSString *> *expected = @[
		@"Libera.Chat",
		@"OFTC",
		@"EFnet",
		@"IRCnet",
		@"Undernet",
		@"QuakeNet",
		@"Rizon",
		@"DALnet",
		@"hackint",
		@"Snoonet",
		@"Tilde.Chat"
	];

	NSMutableArray<NSString *> *actual = [NSMutableArray array];

	for (IRCNetwork *network in list.popularNetworks) {
		[actual addObject:network.networkName];

		XCTAssertTrue([list.listOfNetworks containsObject:network]);
	}

	XCTAssertEqualObjects(actual, expected);
}

- (void)testDeadNetworksAreGone
{
	IRCNetworkList *list = [IRCNetworkList new];

	NSArray<NSString *> *dead = @[
		@"freenode",
		@"PonyChat",
		@"IdleChat",
		@"GeeksIRC",
		@"NixtrixIRC",
		@"Mozor",
		@"Thinkstack",
		@"StormBit",
		@"Snyde",
		@"Mibbit",
		@"Ewnix",
		@"TinyCrab"
	];

	for (NSString *name in dead) {
		XCTAssertNil([list networkNamed:name], @"%@ should have been removed", name);
	}

	XCTAssertNil([list networkWithServerAddress:@"chat.freenode.net"]);
}

- (void)testLiberaChatEntry
{
	IRCNetworkList *list = [IRCNetworkList new];

	IRCNetwork *libera = [list networkNamed:@"libera.chat"];

	XCTAssertNotNil(libera);
	XCTAssertEqualObjects(libera.serverAddress, @"irc.libera.chat");
	XCTAssertEqual(libera.serverPort, 6697);
	XCTAssertTrue(libera.prefersSecuredConnection);
	XCTAssertTrue(libera.saslSupported);
	XCTAssertEqual(libera.registration, IRCNetworkRegistrationOptional);
	XCTAssertNotNil(libera.registrationNote);
	XCTAssertNotNil(libera.website);
	XCTAssertTrue(libera.accountFieldsApply);

	XCTAssertEqual([list networkWithServerAddress:@"IRC.LIBERA.CHAT"], libera);
}

- (void)testNetworkWithoutServicesHidesAccountFields
{
	IRCNetworkList *list = [IRCNetworkList new];

	IRCNetwork *efnet = [list networkNamed:@"EFnet"];

	XCTAssertNotNil(efnet);
	XCTAssertEqual(efnet.registration, IRCNetworkRegistrationNone);
	XCTAssertFalse(efnet.saslSupported);
	XCTAssertFalse(efnet.accountFieldsApply);
}

#pragma mark -
#pragma mark Entry Parsing

- (void)testEntryWithoutAddressIsRejected
{
	IRCNetwork *network = [[IRCNetwork alloc] initWithDictionary:@{@"name" : @"Nowhere"}];

	XCTAssertNil(network);
}

- (void)testEntryDefaultsPortFromSecurity
{
	IRCNetwork *secured = [[IRCNetwork alloc]
		initWithDictionary:@{@"name" : @"A", @"serverAddress" : @"a.example", @"prefersSecuredConnection" : @YES}];

	IRCNetwork *plain = [[IRCNetwork alloc] initWithDictionary:@{@"name" : @"B", @"serverAddress" : @"b.example"}];

	XCTAssertEqual(secured.serverPort, 6697);
	XCTAssertEqual(plain.serverPort, 6667);
	XCTAssertEqualObjects(plain.networkDescription, @"");
	XCTAssertEqualObjects(plain.suggestedChannels, @[]);
	XCTAssertNil(plain.registrationNote);
}

- (void)testRegistrationParsing
{
	XCTAssertEqual([IRCNetworkList registrationFromString:@"required"], IRCNetworkRegistrationRequired);
	XCTAssertEqual([IRCNetworkList registrationFromString:@"Optional"], IRCNetworkRegistrationOptional);
	XCTAssertEqual([IRCNetworkList registrationFromString:@"none"], IRCNetworkRegistrationNone);
	XCTAssertEqual([IRCNetworkList registrationFromString:nil], IRCNetworkRegistrationNone);
	XCTAssertEqual([IRCNetworkList registrationFromString:@"bogus"], IRCNetworkRegistrationNone);
}

#pragma mark -
#pragma mark Account Field Visibility

- (void)testAccountFieldsVisibility
{
	XCTAssertFalse([IRCNetworkList accountFieldsApplyToRegistration:IRCNetworkRegistrationNone saslSupported:NO]);
	XCTAssertTrue([IRCNetworkList accountFieldsApplyToRegistration:IRCNetworkRegistrationNone saslSupported:YES]);
	XCTAssertTrue([IRCNetworkList accountFieldsApplyToRegistration:IRCNetworkRegistrationOptional saslSupported:NO]);
	XCTAssertTrue([IRCNetworkList accountFieldsApplyToRegistration:IRCNetworkRegistrationOptional saslSupported:YES]);
	XCTAssertTrue([IRCNetworkList accountFieldsApplyToRegistration:IRCNetworkRegistrationRequired saslSupported:NO]);
	XCTAssertTrue([IRCNetworkList accountFieldsApplyToRegistration:IRCNetworkRegistrationRequired saslSupported:YES]);
}

#pragma mark -
#pragma mark Onboarding Flag

- (void)testOnboardingCompletedFlagRoundTrips
{
	BOOL original = [TPCPreferences onboardingCompleted];

	[TPCPreferences setOnboardingCompleted:NO];
	XCTAssertFalse([TPCPreferences onboardingCompleted]);

	[TPCPreferences setOnboardingCompleted:YES];
	XCTAssertTrue([TPCPreferences onboardingCompleted]);

	[TPCPreferences setOnboardingCompleted:original];
}

@end

NS_ASSUME_NONNULL_END
