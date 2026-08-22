/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
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

#import "TPCPreferencesUserDefaults.h"
#import "IRCSTSPolicy.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const IRCSTSPolicyStoreDefaultsKey = @"IRC -> STS Policies";

static NSString *const IRCSTSPolicyPortKey = @"port";
static NSString *const IRCSTSPolicyExpiresAtKey = @"expiresAt";
static NSString *const IRCSTSPolicyPreloadKey = @"preload";

@interface IRCSTSPolicy ()
- (nullable instancetype)initWithDictionary:(NSDictionary<NSString *, id> *)dictionary;

@property(readonly, copy) NSDictionary<NSString *, id> *dictionaryValue;
@end

@interface IRCSTSCapabilityValues ()
@property(nonatomic, assign, readwrite) uint16_t port;
@property(nonatomic, assign, readwrite) BOOL hasDuration;
@property(nonatomic, assign, readwrite) NSTimeInterval duration;
@property(nonatomic, assign, readwrite) BOOL preload;
@end

@implementation IRCSTSCapabilityValues

+ (nullable instancetype)valuesFromCapabilityValues:(NSArray<NSString *> *)values
{
	NSParameterAssert(values != nil);

	IRCSTSCapabilityValues *result = [self new];

	BOOL anyKeyRecognised = NO;

	for (NSString *value in values) {
		NSRange equalsRange = [value rangeOfString:@"="];

		NSString *key = value;
		NSString *keyValue = @"";

		if (equalsRange.location != NSNotFound) {
			key = [value substringToIndex:equalsRange.location];
			keyValue = [value substringFromIndex:NSMaxRange(equalsRange)];
		}

		key = key.lowercaseString;

		if ([key isEqualToString:@"port"]) {
			NSInteger port = keyValue.integerValue;

			if (keyValue.length > 0 && port > 0 && port <= 65535 &&
				[keyValue onlyContainsCharactersFromCharacterSet:[NSCharacterSet decimalDigitCharacterSet]]) {
				result.port = (uint16_t)port;
			}

			anyKeyRecognised = YES;
		} else if ([key isEqualToString:@"duration"]) {
			if (keyValue.length > 0 &&
				[keyValue onlyContainsCharactersFromCharacterSet:[NSCharacterSet decimalDigitCharacterSet]]) {
				result.hasDuration = YES;
				result.duration = keyValue.doubleValue;
			}

			anyKeyRecognised = YES;
		} else if ([key isEqualToString:@"preload"]) {
			result.preload = YES;

			anyKeyRecognised = YES;
		}
	}

	if (anyKeyRecognised == NO) {
		return nil;
	}

	return result;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ port=%hu duration=%.0f preload=%d>",
									  self.className,
									  self.port,
									  self.duration,
									  self.preload];
}

@end

#pragma mark -

@implementation IRCSTSPolicy

- (instancetype)initWithPort:(uint16_t)port expiresAt:(NSDate *)expiresAt preload:(BOOL)preload
{
	NSParameterAssert(port > 0);
	NSParameterAssert(expiresAt != nil);

	if ((self = [super init])) {
		self->_port = port;
		self->_expiresAt = [expiresAt copy];
		self->_preload = preload;

		return self;
	}

	return nil;
}

- (nullable instancetype)initWithDictionary:(NSDictionary<NSString *, id> *)dictionary
{
	NSNumber *port = dictionary[IRCSTSPolicyPortKey];
	NSNumber *expiresAt = dictionary[IRCSTSPolicyExpiresAtKey];

	if ([port isKindOfClass:[NSNumber class]] == NO || [expiresAt isKindOfClass:[NSNumber class]] == NO) {
		return nil;
	}

	NSInteger portValue = port.integerValue;

	if (portValue <= 0 || portValue > 65535) {
		return nil;
	}

	return [self initWithPort:(uint16_t)portValue
					expiresAt:[NSDate dateWithTimeIntervalSince1970:expiresAt.doubleValue]
					  preload:[dictionary[IRCSTSPolicyPreloadKey] boolValue]];
}

- (NSDictionary<NSString *, id> *)dictionaryValue
{
	return @{
		IRCSTSPolicyPortKey : @(self.port),
		IRCSTSPolicyExpiresAtKey : @(self.expiresAt.timeIntervalSince1970),
		IRCSTSPolicyPreloadKey : @(self.preload)
	};
}

- (BOOL)isExpired
{
	return (self.expiresAt.timeIntervalSinceNow <= 0);
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ port=%hu expiresAt=%@>", self.className, self.port, self.expiresAt];
}

@end

#pragma mark -

@interface IRCSTSPolicyStore ()
@property(nonatomic, strong, nullable) NSUserDefaults *userDefaults;
@property(nonatomic, strong) NSMutableDictionary<NSString *, IRCSTSPolicy *> *policies;
@end

@implementation IRCSTSPolicyStore

+ (IRCSTSPolicyStore *)sharedStore
{
	static IRCSTSPolicyStore *store = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		store = [[self alloc] initWithUserDefaults:RZUserDefaults()];
	});

	return store;
}

- (instancetype)initWithUserDefaults:(nullable NSUserDefaults *)userDefaults
{
	if ((self = [super init])) {
		self.userDefaults = userDefaults;

		self.policies = [NSMutableDictionary dictionary];

		[self load];

		return self;
	}

	return nil;
}

+ (NSString *)keyForHost:(NSString *)host
{
	return host.lowercaseString;
}

- (void)load
{
	NSDictionary *stored = [self.userDefaults dictionaryForKey:IRCSTSPolicyStoreDefaultsKey];

	[stored enumerateKeysAndObjectsUsingBlock:^(NSString *host, id value, BOOL *stop) {
		if ([host isKindOfClass:[NSString class]] == NO || [value isKindOfClass:[NSDictionary class]] == NO) {
			return;
		}

		IRCSTSPolicy *policy = [[IRCSTSPolicy alloc] initWithDictionary:value];

		if (policy == nil || policy.isExpired) {
			return;
		}

		self.policies[[self.class keyForHost:host]] = policy;
	}];
}

- (void)save
{
	if (self.userDefaults == nil) {
		return;
	}

	NSMutableDictionary<NSString *, NSDictionary *> *stored = [NSMutableDictionary dictionary];

	[self.policies enumerateKeysAndObjectsUsingBlock:^(NSString *host, IRCSTSPolicy *policy, BOOL *stop) {
		stored[host] = policy.dictionaryValue;
	}];

	[self.userDefaults setObject:[stored copy] forKey:IRCSTSPolicyStoreDefaultsKey];
}

- (nullable IRCSTSPolicy *)policyForHost:(NSString *)host
{
	NSParameterAssert(host != nil);

	NSString *key = [self.class keyForHost:host];

	IRCSTSPolicy *policy = self.policies[key];

	if (policy == nil) {
		return nil;
	}

	if (policy.isExpired) {
		[self.policies removeObjectForKey:key];

		[self save];

		return nil;
	}

	return policy;
}

- (void)setPolicy:(IRCSTSPolicy *)policy forHost:(NSString *)host
{
	NSParameterAssert(policy != nil);
	NSParameterAssert(host != nil);

	self.policies[[self.class keyForHost:host]] = policy;

	[self save];
}

- (void)removePolicyForHost:(NSString *)host
{
	NSParameterAssert(host != nil);

	NSString *key = [self.class keyForHost:host];

	if (self.policies[key] == nil) {
		return;
	}

	[self.policies removeObjectForKey:key];

	[self save];
}

- (BOOL)applyPolicyForHost:(NSString *)host toPort:(inout uint16_t *)port secured:(inout BOOL *)secured
{
	NSParameterAssert(host != nil);
	NSParameterAssert(port != NULL);
	NSParameterAssert(secured != NULL);

	IRCSTSPolicy *policy = [self policyForHost:host];

	if (policy == nil) {
		return NO;
	}

	*port = policy.port;
	*secured = YES;

	return YES;
}

- (IRCSTSPolicyAction)applyCapabilityValues:(IRCSTSCapabilityValues *)values
									forHost:(NSString *)host
							  connectedPort:(uint16_t)connectedPort
									secured:(BOOL)secured
								upgradePort:(nullable uint16_t *)upgradePort
{
	NSParameterAssert(values != nil);
	NSParameterAssert(host != nil);

	if (secured == NO) {
		/* A plaintext connection only learns where TLS lives. The policy
		 is written once the secure connection sees the capability. */
		if (values.port == 0) {
			return IRCSTSPolicyActionNone;
		}

		if (upgradePort) {
			*upgradePort = values.port;
		}

		return IRCSTSPolicyActionUpgrade;
	}

	if (values.hasDuration == NO) {
		return IRCSTSPolicyActionNone;
	}

	if (values.duration <= 0) {
		[self removePolicyForHost:host];

		return IRCSTSPolicyActionCleared;
	}

	uint16_t policyPort = values.port;

	if (policyPort == 0) {
		policyPort = connectedPort;
	}

	if (policyPort == 0) {
		return IRCSTSPolicyActionNone;
	}

	IRCSTSPolicy *policy = [[IRCSTSPolicy alloc] initWithPort:policyPort
													expiresAt:[NSDate dateWithTimeIntervalSinceNow:values.duration]
													  preload:values.preload];

	[self setPolicy:policy forHost:host];

	return IRCSTSPolicyActionStored;
}

@end

NS_ASSUME_NONNULL_END
