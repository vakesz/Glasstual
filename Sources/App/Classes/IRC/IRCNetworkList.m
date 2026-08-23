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

#import "NSObjectHelperPrivate.h"
#import "TPCResourceManager.h"
#import "IRCNetworkList.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCNetworkList ()
@property(nonatomic, copy, readwrite) NSArray<IRCNetwork *> *listOfNetworks;
@property(nonatomic, copy, readwrite) NSArray<IRCNetwork *> *popularNetworks;
@end

@interface IRCNetwork ()
@property(nonatomic, copy, readwrite) NSString *networkName;
@property(nonatomic, copy, readwrite) NSString *networkDescription;
@property(nonatomic, copy, readwrite) NSString *serverAddress;
@property(nonatomic, assign, readwrite) uint16_t serverPort;
@property(nonatomic, assign, readwrite) BOOL prefersSecuredConnection;
@property(nonatomic, copy, readwrite, nullable) NSString *website;
@property(nonatomic, assign, readwrite) BOOL saslSupported;
@property(nonatomic, assign, readwrite) IRCNetworkRegistration registration;
@property(nonatomic, copy, readwrite, nullable) NSString *registrationNote;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *suggestedChannels;
@end

@implementation IRCNetworkList

- (instancetype)init
{
	if ((self = [super init])) {
		[self prepareInitialState];

		return self;
	}

	return nil;
}

- (void)prepareInitialState
{
	NSMutableArray<IRCNetwork *> *listOfNetworks = [NSMutableArray array];

	NSArray *resource = [TPCResourceManager arrayFromResources:@"IRCNetworks" cacheValue:NO];

	if (resource) {
		for (id entry in resource) {
			if ([entry isKindOfClass:[NSDictionary class]] == NO) {
				continue;
			}

			IRCNetwork *network = [[IRCNetwork alloc] initWithDictionary:entry];

			if (network) {
				[listOfNetworks addObject:network];
			}
		}
	} else {
		/* The list was a dictionary keyed by network name before it carried
		 descriptions. Accept that shape so that an old copy keeps working. */
		NSDictionary *legacyList = [TPCResourceManager dictionaryFromResources:@"IRCNetworks" cacheValue:NO];

		[legacyList enumerateKeysAndObjectsUsingBlock:^(NSString *name, id configuration, BOOL *stop) {
			if ([configuration isKindOfClass:[NSDictionary class]] == NO) {
				return;
			}

			NSMutableDictionary *entry = [configuration mutableCopy];

			entry[@"name"] = name;

			IRCNetwork *network = [[IRCNetwork alloc] initWithDictionary:entry];

			if (network) {
				[listOfNetworks addObject:network];
			}
		}];
	}

	[listOfNetworks sortUsingComparator:^NSComparisonResult(IRCNetwork *network1, IRCNetwork *network2) {
		return [network1.networkName caseInsensitiveCompare:network2.networkName];
	}];

	self.listOfNetworks = listOfNetworks;

	/* Order matters: this is the order the onboarding flow shows them in. */
	NSArray<NSString *> *popularNames = @[
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

	NSMutableArray<IRCNetwork *> *popularNetworks = [NSMutableArray array];

	for (NSString *name in popularNames) {
		IRCNetwork *network = [self networkNamed:name];

		if (network) {
			[popularNetworks addObject:network];
		}
	}

	self.popularNetworks = popularNetworks;
}

- (nullable IRCNetwork *)networkNamed:(NSString *)networkName
{
	NSParameterAssert(networkName != nil);

	IRCNetwork *network =
		[self.listOfNetworks objectPassingTest:^BOOL(IRCNetwork *network, NSUInteger index, BOOL *stop) {
			return [network.networkName isEqualToStringIgnoringCase:networkName];
		}];

	return network;
}

- (nullable IRCNetwork *)networkWithServerAddress:(NSString *)serverAddress
{
	NSParameterAssert(serverAddress != nil);

	IRCNetwork *network =
		[self.listOfNetworks objectPassingTest:^BOOL(IRCNetwork *network, NSUInteger index, BOOL *stop) {
			return [network.serverAddress isEqualToStringIgnoringCase:serverAddress];
		}];

	return network;
}

+ (BOOL)accountFieldsApplyToRegistration:(IRCNetworkRegistration)registration saslSupported:(BOOL)saslSupported
{
	if (saslSupported) {
		return YES;
	}

	return (registration != IRCNetworkRegistrationNone);
}

+ (IRCNetworkRegistration)registrationFromString:(nullable NSString *)string
{
	if ([string isEqualToStringIgnoringCase:@"required"]) {
		return IRCNetworkRegistrationRequired;
	}

	if ([string isEqualToStringIgnoringCase:@"optional"]) {
		return IRCNetworkRegistrationOptional;
	}

	return IRCNetworkRegistrationNone;
}

@end

#pragma mark -

@implementation IRCNetwork

- (nullable instancetype)initWithDictionary:(NSDictionary<NSString *, id> *)dictionary
{
	NSParameterAssert(dictionary != nil);

	if ((self = [super init])) {
		NSString *name = [dictionary stringForKey:@"name"];
		NSString *serverAddress = [dictionary stringForKey:@"serverAddress"];

		if (name.length == 0 || serverAddress.length == 0) {
			return nil;
		}

		self.networkName = name;
		self.serverAddress = serverAddress;
		self.networkDescription = [dictionary stringForKey:@"description" orUseDefault:@""];
		self.serverPort = [dictionary unsignedShortForKey:@"serverPort"];
		self.prefersSecuredConnection = [dictionary boolForKey:@"prefersSecuredConnection"];
		self.website = [dictionary stringForKey:@"website"];
		self.saslSupported = [dictionary boolForKey:@"saslSupported"];
		self.registration = [IRCNetworkList registrationFromString:[dictionary stringForKey:@"registration"]];
		self.suggestedChannels = [dictionary arrayForKey:@"suggestedChannels" orUseDefault:@[]];

		NSString *registrationNote = [dictionary stringForKey:@"registrationNote"];

		if (registrationNote.length > 0) {
			self.registrationNote = registrationNote;
		}

		if (self.serverPort == 0) {
			self.serverPort = (self.prefersSecuredConnection ? 6697 : 6667);
		}

		return self;
	}

	return nil;
}

- (BOOL)accountFieldsApply
{
	return [IRCNetworkList accountFieldsApplyToRegistration:self.registration saslSupported:self.saslSupported];
}

- (NSString *)description
{
	return [NSString
		stringWithFormat:@"<%@ %@ %@:%hu>", self.className, self.networkName, self.serverAddress, self.serverPort];
}

@end

NS_ASSUME_NONNULL_END
