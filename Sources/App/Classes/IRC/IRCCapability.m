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

#import "NSObjectHelperPrivate.h"
#import "TPCPreferencesLocal.h"
#import "IRCClientPrivate.h"
#import "IRCCapability.h"

NS_ASSUME_NONNULL_BEGIN

@implementation IRCCapability

+ (instancetype)capabilityNamed:(NSString *)name identifier:(ClientIRCv3SupportedCapability)identifier
{
	return [self capabilityNamed:name identifier:identifier requestedByDefault:YES];
}

+ (instancetype)capabilityNamed:(NSString *)name
					 identifier:(ClientIRCv3SupportedCapability)identifier
			 requestedByDefault:(BOOL)requestedByDefault
{
	return [[self alloc] initWithName:name
						   identifier:identifier
				   requestedByDefault:requestedByDefault
					   preferenceGate:nil
						 dependencies:nil
					  negotiationHook:nil];
}

- (instancetype)initWithName:(NSString *)name
				  identifier:(ClientIRCv3SupportedCapability)identifier
		  requestedByDefault:(BOOL)requestedByDefault
			  preferenceGate:(nullable IRCCapabilityPreferenceGate)preferenceGate
				dependencies:(nullable NSArray<NSString *> *)dependencies
			 negotiationHook:(nullable IRCCapabilityNegotiationHook)negotiationHook
{
	NSParameterAssert(name.length > 0);

	if ((self = [super init])) {
		self->_name = [name.lowercaseString copy];
		self->_identifier = identifier;
		self->_requestedByDefault = requestedByDefault;
		self->_preferenceGate = [preferenceGate copy];
		self->_dependencies = [(dependencies ?: @[]) copy];
		self->_negotiationHook = [negotiationHook copy];

		return self;
	}

	return nil;
}

- (BOOL)isEnabledByPreferences
{
	IRCCapabilityPreferenceGate gate = self.preferenceGate;

	if (gate == nil) {
		return YES;
	}

	return gate();
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %@>", self.className, self.name];
}

@end

#pragma mark -

@implementation IRCCapabilityRegistry

+ (IRCCapabilityRegistry *)defaultRegistry
{
	static IRCCapabilityRegistry *registry = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		registry = [[self alloc] initWithCapabilities:[self defaultCapabilities]];
	});

	return registry;
}

+ (NSArray<IRCCapability *> *)defaultCapabilities
{
	IRCCapabilityPreferenceGate echoMessageGate = ^BOOL {
		return [TPCPreferences enableEchoMessageCapability];
	};

	IRCCapabilityNegotiationHook saslHook = ^BOOL(IRCClient *client, NSArray<NSString *> *mechanisms) {
		return [client selectSASLMechanismFromOffered:mechanisms];
	};

	/* Order here is the order of CAP REQ. Dependencies are listed
	 before the capabilities that depend on them. */
	return @[
		[IRCCapability capabilityNamed:@"cap-notify" identifier:ClientIRCv3SupportedCapabilityCapNotify],
		[IRCCapability capabilityNamed:@"message-tags" identifier:ClientIRCv3SupportedCapabilityMessageTags],
		[IRCCapability capabilityNamed:@"away-notify" identifier:ClientIRCv3SupportedCapabilityAwayNotify],
		[IRCCapability capabilityNamed:@"batch" identifier:ClientIRCv3SupportedCapabilityBatch],
		[IRCCapability capabilityNamed:@"chghost" identifier:ClientIRCv3SupportedCapabilityChangeHost],
		[[IRCCapability alloc] initWithName:@"echo-message"
								 identifier:ClientIRCv3SupportedCapabilityEchoMessage
						 requestedByDefault:YES
							 preferenceGate:echoMessageGate
							   dependencies:nil
							negotiationHook:nil],
		[[IRCCapability alloc] initWithName:@"labeled-response"
								 identifier:ClientIRCv3SupportedCapabilityLabeledResponse
						 requestedByDefault:YES
							 preferenceGate:nil
							   dependencies:@[ @"message-tags" ]
							negotiationHook:nil],
		[IRCCapability capabilityNamed:@"multi-prefix" identifier:ClientIRCv3SupportedCapabilityMultiPrefix],
		[[IRCCapability alloc] initWithName:@"sasl"
								 identifier:ClientIRCv3SupportedCapabilitySASLGeneric
						 requestedByDefault:YES
							 preferenceGate:nil
							   dependencies:nil
							negotiationHook:saslHook],
		[IRCCapability capabilityNamed:@"server-time" identifier:ClientIRCv3SupportedCapabilityServerTime],
		[IRCCapability capabilityNamed:@"standard-replies" identifier:ClientIRCv3SupportedCapabilityStandardReplies],
		[IRCCapability capabilityNamed:@"userhost-in-names" identifier:ClientIRCv3SupportedCapabilityUserhostInNames],
		[IRCCapability
			capabilityNamed:@"znc.in/playback"
				 identifier:(ClientIRCv3SupportedCapabilityPlayback | ClientIRCv3SupportedCapabilityZNCPlaybackModule)],
		[IRCCapability capabilityNamed:@"znc.in/self-message" identifier:ClientIRCv3SupportedCapabilityZNCSelfMessage],
		[IRCCapability
			capabilityNamed:@"znc.in/server-time"
				 identifier:(ClientIRCv3SupportedCapabilityServerTime | ClientIRCv3SupportedCapabilityZNCServerTime)],
		[IRCCapability capabilityNamed:@"znc.in/server-time-iso"
							identifier:(ClientIRCv3SupportedCapabilityServerTime |
										ClientIRCv3SupportedCapabilityZNCServerTimeISO)],
		[IRCCapability capabilityNamed:@"znc.in/tlsinfo" identifier:ClientIRCv3SupportedCapabilityZNCCertInfoModule],
	];
}

- (instancetype)initWithCapabilities:(NSArray<IRCCapability *> *)capabilities
{
	NSParameterAssert(capabilities != nil);

	if ((self = [super init])) {
		self->_capabilities = [capabilities copy];

		return self;
	}

	return nil;
}

- (nullable IRCCapability *)capabilityNamed:(NSString *)name
{
	NSParameterAssert(name != nil);

	NSString *nameLowercase = name.lowercaseString;

	for (IRCCapability *capability in self.capabilities) {
		if ([capability.name isEqualToString:nameLowercase]) {
			return capability;
		}
	}

	return nil;
}

- (nullable IRCCapability *)capabilityForIdentifier:(ClientIRCv3SupportedCapability)identifier
{
	if (identifier == 0) {
		return nil;
	}

	for (IRCCapability *capability in self.capabilities) {
		if ((capability.identifier & identifier) == identifier) {
			return capability;
		}
	}

	return nil;
}

- (BOOL)isCapabilitySupported:(NSString *)name
{
	NSParameterAssert(name != nil);

	IRCCapability *capability = [self capabilityNamed:name];

	if (capability == nil) {
		return NO;
	}

	return capability.isEnabledByPreferences;
}

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)parseCapabilityList:(NSString *)list
{
	NSParameterAssert(list != nil);

	NSMutableDictionary<NSString *, NSArray<NSString *> *> *offered = [NSMutableDictionary dictionary];

	NSArray<NSString *> *tokens = [list componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

	for (NSString *token in tokens) {
		if (token.length == 0) {
			continue;
		}

		NSRange equalsRange = [token rangeOfString:@"="];

		if (equalsRange.location == NSNotFound) {
			offered[token.lowercaseString] = @[];

			continue;
		}

		NSString *name = [token substringToIndex:equalsRange.location];
		NSString *value = [token substringFromIndex:NSMaxRange(equalsRange)];

		if (name.length == 0) {
			continue;
		}

		NSMutableArray<NSString *> *values = [NSMutableArray array];

		for (NSString *component in [value componentsSeparatedByString:@","]) {
			if (component.length > 0) {
				[values addObject:component];
			}
		}

		offered[name.lowercaseString] = [values copy];
	}

	return [offered copy];
}

- (NSArray<IRCCapability *> *)capabilitiesToRequestFromOffered:
	(NSDictionary<NSString *, NSArray<NSString *> *> *)offered
{
	NSParameterAssert(offered != nil);

	NSMutableArray<IRCCapability *> *request = [NSMutableArray array];

	for (IRCCapability *capability in self.capabilities) {
		if ([self _capability:capability isRequestableFromOffered:offered depth:0]) {
			[request addObject:capability];
		}
	}

	return [request copy];
}

- (BOOL)_capability:(IRCCapability *)capability
	isRequestableFromOffered:(NSDictionary<NSString *, NSArray<NSString *> *> *)offered
					   depth:(NSUInteger)depth
{
	/* Dependency chains are short; a bound guards against a cycle. */
	if (depth > 8) {
		return NO;
	}

	if (capability.requestedByDefault == NO || capability.isEnabledByPreferences == NO) {
		return NO;
	}

	if (offered[capability.name] == nil) {
		return NO;
	}

	for (NSString *dependencyName in capability.dependencies) {
		IRCCapability *dependency = [self capabilityNamed:dependencyName];

		if (dependency == nil) {
			return NO;
		}

		if ([self _capability:dependency isRequestableFromOffered:offered depth:(depth + 1)] == NO) {
			return NO;
		}
	}

	return YES;
}

@end

NS_ASSUME_NONNULL_END
