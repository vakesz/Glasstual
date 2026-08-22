/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *	* Redistributions of source code must retain the above copyright
 *	  notice, this list of conditions and the following disclaimer.
 *	* Redistributions in binary form must reproduce the above copyright
 *	  notice, this list of conditions and the following disclaimer in the
 *	  documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual and/or Codeux Software, nor the names of
 *    its contributors may be used to endorse or promote products derived
 * 	  from this software without specific prior written permission.
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
#import "NSStringHelper.h"
#import "TLOLocalization.h"
#import "IRC.h"
#import "IRCClientPrivate.h"
#import "IRCModeInfo.h"
#import "IRCISupportInfoPrivate.h"

NS_ASSUME_NONNULL_BEGIN

#define _channelUserModeValue 100

@interface IRCISupportInfo ()
@property(nonatomic, weak, nullable) IRCClient *client;
@property(nonatomic, copy) NSArray<NSDictionary *> *cachedConfiguration;
@property(nonatomic, assign, readwrite) NSUInteger maximumAwayLength;
@property(nonatomic, assign, readwrite) NSUInteger maximumChannelNameLength;
@property(nonatomic, assign, readwrite) NSUInteger maximumKeyLength;
@property(nonatomic, assign, readwrite) NSUInteger maximumKickLength;
@property(nonatomic, assign, readwrite) NSUInteger maximumNicknameLength;
@property(nonatomic, assign, readwrite) NSUInteger maximumTopicLength;
@property(nonatomic, assign, readwrite) NSUInteger maximumModeCount;
@property(nonatomic, assign, readwrite) NSUInteger maximumLineLength;
@property(nonatomic, assign, readwrite) NSUInteger maximumTargets;
@property(nonatomic, assign, readwrite) NSUInteger maximumSilenceEntries;
@property(nonatomic, assign, readwrite) BOOL silenceSupported;
@property(nonatomic, assign, readwrite) BOOL safeListSupported;
@property(nonatomic, assign, readwrite) BOOL whoxSupported;
@property(nonatomic, assign, readwrite) BOOL utf8Only;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *channelNamePrefixes;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *statusMessageModeSymbols;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *extendedBanTypes;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *extendedListTokens;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *clientTagDenyList;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSNumber *> *channelModes;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSNumber *> *channelLimits;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSNumber *> *maximumListEntries;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSNumber *> *maximumTargetsByCommand;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSArray *> *userModeSymbols;
@property(nonatomic, copy, readwrite, nullable) NSString *banExceptionModeSymbol;
@property(nonatomic, copy, readwrite, nullable) NSString *inviteExceptionModeSymbol;
@property(nonatomic, copy, readwrite, nullable) NSString *botModeSymbol;
@property(nonatomic, copy, readwrite, nullable) NSString *callerIDModeSymbol;
@property(nonatomic, copy, readwrite, nullable) NSString *deafModeSymbol;
@property(nonatomic, copy, readwrite, nullable) NSString *extendedBanPrefix;
@property(nonatomic, copy, readwrite, nullable) NSString *networkName;
@property(nonatomic, copy, readwrite, nullable) NSString *networkNameFormatted;
@property(nonatomic, assign, readwrite) IRCISupportInfoCaseMapping caseMapping;
@end

@implementation IRCISupportInfo

- (instancetype)init
{
	return [self initWithClient:nil];
}

- (instancetype)initWithClient:(nullable IRCClient *)client
{
	if ((self = [super init])) {
		self.client = client;

		[self prepareInitialState];

		return self;
	}

	return nil;
}

- (void)prepareInitialState
{
	[self reset];
}

- (void)reset
{
	self.cachedConfiguration = @[];

	self.serverAddress = nil;

	self.userModeSymbols = @{@"modeSymbols" : @[ @"o", @"v" ], @"characters" : @[ @"@", @"+" ]};

	self.channelModes = @{@"o" : @(_channelUserModeValue), @"v" : @(_channelUserModeValue)};

	for (NSString *key in [self.class resettableSettings]) {
		[self resetSetting:key];
	}
}

+ (NSArray<NSString *> *)resettableSettings
{
	static NSArray<NSString *> *settings = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		settings = @[
			@"AWAYLEN",		  @"BOT",	  @"CALLERID",	@"CASEMAPPING", @"CHANLIMIT", @"CHANNELLEN", @"CHANTYPES",
			@"CLIENTTAGDENY", @"DEAF",	  @"ELIST",		@"EXCEPTS",		@"EXTBAN",	  @"INVEX",		 @"KEYLEN",
			@"KICKLEN",		  @"LINELEN", @"MAXLIST",	@"MAXTARGETS",	@"MODES",	  @"NETWORK",	 @"NICKLEN",
			@"SAFELIST",	  @"SILENCE", @"STATUSMSG", @"TARGMAX",		@"TOPICLEN",  @"UTF8ONLY",	 @"WHOX"
		];
	});

	return settings;
}

/* Restores the default for a single token. Used by -reset and by
 "-TOKEN" negation entries in an 005 reply. */
- (void)resetSetting:(NSString *)key
{
	NSParameterAssert(key != nil);

	key = key.uppercaseString;

	if ([key isEqualToString:@"AWAYLEN"]) {
		self.maximumAwayLength = 0;
	} else if ([key isEqualToString:@"BOT"]) {
		self.botModeSymbol = nil;
	} else if ([key isEqualToString:@"CALLERID"]) {
		self.callerIDModeSymbol = nil;
	} else if ([key isEqualToString:@"CASEMAPPING"]) {
		self.caseMapping = IRCISupportInfoCaseMappingRFC1459;
	} else if ([key isEqualToString:@"CHANLIMIT"]) {
		self.channelLimits = @{};
	} else if ([key isEqualToString:@"CHANNELLEN"]) {
		self.maximumChannelNameLength = 0;
	} else if ([key isEqualToString:@"CHANTYPES"]) {
		self.channelNamePrefixes = @[ @"#" ];
	} else if ([key isEqualToString:@"CLIENTTAGDENY"]) {
		self.clientTagDenyList = @[];
	} else if ([key isEqualToString:@"DEAF"]) {
		self.deafModeSymbol = nil;
	} else if ([key isEqualToString:@"ELIST"]) {
		self.extendedListTokens = @[];
	} else if ([key isEqualToString:@"EXCEPTS"]) {
		self.banExceptionModeSymbol = nil;
	} else if ([key isEqualToString:@"EXTBAN"]) {
		self.extendedBanPrefix = nil;
		self.extendedBanTypes = @[];
	} else if ([key isEqualToString:@"INVEX"]) {
		self.inviteExceptionModeSymbol = nil;
	} else if ([key isEqualToString:@"KEYLEN"]) {
		self.maximumKeyLength = 0;
	} else if ([key isEqualToString:@"KICKLEN"]) {
		self.maximumKickLength = 0;
	} else if ([key isEqualToString:@"LINELEN"]) {
		self.maximumLineLength = 0;
	} else if ([key isEqualToString:@"MAXLIST"]) {
		self.maximumListEntries = @{};
	} else if ([key isEqualToString:@"MAXTARGETS"]) {
		self.maximumTargets = 0;
	} else if ([key isEqualToString:@"MODES"]) {
		self.maximumModeCount = TXMaximumNodesPerModeCommand;
	} else if ([key isEqualToString:@"NETWORK"]) {
		self.networkName = nil;
		self.networkNameFormatted = nil;
	} else if ([key isEqualToString:@"NICKLEN"]) {
		self.maximumNicknameLength = IRCProtocolDefaultNicknameMaximumLength;
	} else if ([key isEqualToString:@"SAFELIST"]) {
		self.safeListSupported = NO;
	} else if ([key isEqualToString:@"SILENCE"]) {
		self.silenceSupported = NO;
		self.maximumSilenceEntries = 0;
	} else if ([key isEqualToString:@"STATUSMSG"]) {
		self.statusMessageModeSymbols = @[];
	} else if ([key isEqualToString:@"TARGMAX"]) {
		self.maximumTargetsByCommand = @{};
	} else if ([key isEqualToString:@"TOPICLEN"]) {
		self.maximumTopicLength = 0;
	} else if ([key isEqualToString:@"UTF8ONLY"]) {
		self.utf8Only = NO;
	} else if ([key isEqualToString:@"WHOX"]) {
		self.whoxSupported = NO;
	}
}

- (void)removeCachedSetting:(NSString *)key
{
	NSParameterAssert(key != nil);

	NSMutableArray<NSDictionary *> *cachedConfiguration =
		[NSMutableArray arrayWithCapacity:self.cachedConfiguration.count];

	for (NSDictionary *configuration in self.cachedConfiguration) {
		NSMutableDictionary *configurationMutable = [configuration mutableCopy];

		for (NSString *cachedKey in configuration) {
			if ([cachedKey isEqualToStringIgnoringCase:key]) {
				[configurationMutable removeObjectForKey:cachedKey];
			}
		}

		if (configurationMutable.count > 0) {
			[cachedConfiguration addObject:[configurationMutable copy]];
		}
	}

	self.cachedConfiguration = cachedConfiguration;
}

- (void)processConfigurationData:(NSString *)configurationData
{
	NSParameterAssert(configurationData != nil);

	configurationData = configurationData.trim;

	if (configurationData.length == 0) {
		return;
	}

	IRCClient *client = self.client;

	NSMutableDictionary *configuration = [NSMutableDictionary dictionary];

	NSArray *segments =
		[configurationData componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

	for (NSString *segment in segments) {
		if (segment.length == 0) { // Blank
			continue;
		}

		NSString *segmentKey = segment;
		NSString *segmentValue = nil;

		NSInteger equalSignPosition = [segment stringPosition:@"="];

		if (equalSignPosition > 0) {
			segmentKey = [segment substringToIndex:equalSignPosition];
			segmentValue = [segment substringAfterIndex:equalSignPosition];

			if (segmentValue.length == 0) {
				segmentValue = nil;
			}
		}

		/* "-TOKEN" withdraws a token advertised earlier. */
		if ([segmentKey hasPrefix:@"-"] && segmentKey.length > 1) {
			NSString *negatedKey = [segmentKey substringFromIndex:1];

			[self resetSetting:negatedKey];

			[self removeCachedSetting:negatedKey];

			[configuration removeObjectForKey:negatedKey];

			continue;
		}

		if (segmentValue) {
			configuration[segmentKey] = segmentValue;
		} else {
			configuration[segmentKey] = @(YES);
		}

		if (segmentValue) {
			if ([segmentKey isEqualToStringIgnoringCase:@"AWAYLEN"]) {
				NSInteger awayLength = segmentValue.integerValue;

				if (awayLength > 0) {
					self.maximumAwayLength = awayLength;
				}
			} else if ([segmentKey isEqualToStringIgnoringCase:@"CASEMAPPING"]) {
				[self parseCaseMapping:segmentValue];
			} else if ([segmentKey isEqualToStringIgnoringCase:@"CHANLIMIT"]) {
				[self parseChannelLimits:segmentValue];
			} else if ([segmentKey isEqualToStringIgnoringCase:@"CHANMODES"]) {
				[self parseChannelModes:segmentValue];
			} else if ([segmentKey isEqualToStringIgnoringCase:@"CHANNELLEN"]) {
				NSInteger channelNameLength = segmentValue.integerValue;

				if (channelNameLength > 0) {
					self.maximumChannelNameLength = channelNameLength;
				}
			} else if ([segmentKey isEqualToStringIgnoringCase:@"CHANTYPES"]) {
				NSArray *channelNamePrefixes = segmentValue.characterStringBuffer;

				if (channelNamePrefixes.count > 0) {
					self.channelNamePrefixes = channelNamePrefixes;
				}
			} else if ([segmentKey isEqualToStringIgnoringCase:@"CLIENTTAGDENY"]) {
				self.clientTagDenyList = [segmentValue split:@","];
			} else if ([segmentKey isEqualToStringIgnoringCase:@"ELIST"]) {
				self.extendedListTokens = segmentValue.uppercaseString.characterStringBuffer;
			} else if ([segmentKey isEqualToStringIgnoringCase:@"EXTBAN"]) {
				[self parseExtendedBans:segmentValue];
			} else if ([segmentKey isEqualToStringIgnoringCase:@"KEYLEN"]) {
				NSInteger maximumKeyLength = segmentValue.integerValue;

				if (maximumKeyLength > 0) {
					self.maximumKeyLength = maximumKeyLength;
				}
			} else if ([segmentKey isEqualToStringIgnoringCase:@"KICKLEN"]) {
				NSInteger maximumKickLength = segmentValue.integerValue;

				if (maximumKickLength > 0) {
					self.maximumKickLength = maximumKickLength;
				}
			} else if ([segmentKey isEqualToStringIgnoringCase:@"LINELEN"]) {
				NSInteger maximumLineLength = segmentValue.integerValue;

				if (maximumLineLength > 0) {
					self.maximumLineLength = maximumLineLength;
				}
			} else if ([segmentKey isEqualToStringIgnoringCase:@"MAXLIST"]) {
				[self parseMaximumListEntries:segmentValue];
			} else if ([segmentKey isEqualToStringIgnoringCase:@"MAXTARGETS"]) {
				NSInteger maximumTargets = segmentValue.integerValue;

				if (maximumTargets > 0) {
					self.maximumTargets = maximumTargets;
				}
			} else if ([segmentKey isEqualToStringIgnoringCase:@"MODES"]) {
				NSInteger maximumModesCount = segmentValue.integerValue;

				if (maximumModesCount > 0) {
					self.maximumModeCount = maximumModesCount;
				}
			} else if ([segmentKey isEqualToStringIgnoringCase:@"NETWORK"]) {
				self.networkName = segmentValue;
				self.networkNameFormatted = TXTLS(@"IRC[8hg-7k]", segmentValue);
			} else if ([segmentKey isEqualToStringIgnoringCase:@"NICKLEN"]) {
				NSInteger maximumNicknameLength = segmentValue.integerValue;

				if (maximumNicknameLength > 0) {
					self.maximumNicknameLength = maximumNicknameLength;
				}
			} else if ([segmentKey isEqualToStringIgnoringCase:@"PREFIX"]) {
				[self parseUserModeSymbols:segmentValue];
			} else if ([segmentKey isEqualToStringIgnoringCase:@"STATUSMSG"]) {
				self.statusMessageModeSymbols = segmentValue.characterStringBuffer;
			} else if ([segmentKey isEqualToStringIgnoringCase:@"TARGMAX"]) {
				[self parseMaximumTargets:segmentValue];
			} else if ([segmentKey isEqualToStringIgnoringCase:@"TOPICLEN"]) {
				NSInteger maximumTopicLength = segmentValue.integerValue;

				if (maximumTopicLength > 0) {
					self.maximumTopicLength = maximumTopicLength;
				}
			}
		}

		if ([segmentKey isEqualToStringIgnoringCase:@"BOT"]) {
			if (segmentValue.isModeSymbol) {
				self.botModeSymbol = segmentValue;
			}
		} else if ([segmentKey isEqualToStringIgnoringCase:@"CALLERID"]) {
			if (segmentValue.isModeSymbol) {
				self.callerIDModeSymbol = segmentValue;
			} else {
				self.callerIDModeSymbol = @"g";
			}
		} else if ([segmentKey isEqualToStringIgnoringCase:@"DEAF"]) {
			if (segmentValue.isModeSymbol) {
				self.deafModeSymbol = segmentValue;
			} else {
				self.deafModeSymbol = @"D";
			}
		} else if ([segmentKey isEqualToStringIgnoringCase:@"EXCEPTS"]) {
			if (segmentValue.isModeSymbol) {
				self.banExceptionModeSymbol = segmentValue;
			} else {
				self.banExceptionModeSymbol = @"e";
			}
		} else if ([segmentKey isEqualToStringIgnoringCase:@"INVEX"]) {
			if (segmentValue.isModeSymbol) {
				self.inviteExceptionModeSymbol = segmentValue;
			} else {
				self.inviteExceptionModeSymbol = @"I";
			}
		} else if ([segmentKey isEqualToStringIgnoringCase:@"MONITOR"]) {
			[client enableCapability:ClientIRCv3SupportedCapabilityMonitorCommand];
		} else if ([segmentKey isEqualToStringIgnoringCase:@"NAMESX"]) {
			if (client && [client isCapabilityEnabled:ClientIRCv3SupportedCapabilityMultiPrefix] == NO) {
				[client sendLine:@"PROTOCTL NAMESX"];

				[client enableCapability:ClientIRCv3SupportedCapabilityMultiPrefix];
			}
		} else if ([segmentKey isEqualToStringIgnoringCase:@"SAFELIST"]) {
			self.safeListSupported = YES;
		} else if ([segmentKey isEqualToStringIgnoringCase:@"SILENCE"]) {
			self.silenceSupported = YES;

			NSInteger maximumSilenceEntries = segmentValue.integerValue;

			if (maximumSilenceEntries > 0) {
				self.maximumSilenceEntries = maximumSilenceEntries;
			}
		} else if ([segmentKey isEqualToStringIgnoringCase:@"UHNAMES"]) {
			if (client && [client isCapabilityEnabled:ClientIRCv3SupportedCapabilityUserhostInNames] == NO) {
				[client sendLine:@"PROTOCTL UHNAMES"];

				[client enableCapability:ClientIRCv3SupportedCapabilityUserhostInNames];
			}
		} else if ([segmentKey isEqualToStringIgnoringCase:@"UTF8ONLY"]) {
			self.utf8Only = YES;
		} else if ([segmentKey isEqualToStringIgnoringCase:@"WATCH"]) {
			[client enableCapability:ClientIRCv3SupportedCapabilityWatchCommand];
		} else if ([segmentKey isEqualToStringIgnoringCase:@"WHOX"]) {
			self.whoxSupported = YES;
		}
	} // while()

	if (configuration.count > 0) {
		self.cachedConfiguration = [self.cachedConfiguration arrayByAddingObject:configuration];
	}
}

#pragma mark -
#pragma mark Limits

- (void)parseChannelLimits:(NSString *)limitString
{
	NSParameterAssert(limitString != nil);

	// Input: CHANLIMIT=#&:50,+:
	//
	// A missing number means that there is no limit for those prefixes.

	NSMutableDictionary<NSString *, NSNumber *> *channelLimits = [NSMutableDictionary dictionary];

	for (NSString *entry in [limitString split:@","]) {
		NSInteger colonPosition = [entry stringPosition:@":"];

		if (colonPosition < 1) {
			continue;
		}

		NSString *prefixes = [entry substringToIndex:colonPosition];

		NSInteger limit = [entry substringAfterIndex:colonPosition].integerValue;

		if (limit < 0) {
			limit = 0;
		}

		for (NSString *prefix in prefixes.characterStringBuffer) {
			channelLimits[prefix] = @(limit);
		}
	}

	self.channelLimits = channelLimits;
}

- (NSUInteger)channelLimitForChannelNamed:(NSString *)channel
{
	NSParameterAssert(channel != nil);

	if (channel.length == 0) {
		return 0;
	}

	NSString *prefix = [channel stringCharacterAtIndex:0];

	return self.channelLimits[prefix].unsignedIntegerValue;
}

- (void)parseMaximumTargets:(NSString *)targetString
{
	NSParameterAssert(targetString != nil);

	// Input: TARGMAX=PRIVMSG:4,NOTICE:4,JOIN:,WHOIS:1
	//
	// A missing number means that there is no limit for that command.

	NSMutableDictionary<NSString *, NSNumber *> *maximumTargets = [NSMutableDictionary dictionary];

	for (NSString *entry in [targetString split:@","]) {
		NSInteger colonPosition = [entry stringPosition:@":"];

		if (colonPosition < 1) {
			continue;
		}

		NSString *command = [entry substringToIndex:colonPosition].uppercaseString;

		NSInteger limit = [entry substringAfterIndex:colonPosition].integerValue;

		if (limit < 0) {
			limit = 0;
		}

		maximumTargets[command] = @(limit);
	}

	self.maximumTargetsByCommand = maximumTargets;
}

- (NSUInteger)maximumTargetsForCommand:(NSString *)command
{
	NSParameterAssert(command != nil);

	NSNumber *limit = self.maximumTargetsByCommand[command.uppercaseString];

	if (limit) {
		return limit.unsignedIntegerValue;
	}

	return self.maximumTargets;
}

+ (NSArray<NSArray<NSString *> *> *)chunkTargets:(NSArray<NSString *> *)targets limit:(NSUInteger)limit
{
	NSParameterAssert(targets != nil);

	if (limit == 0) {
		limit = 1;
	}

	NSMutableArray<NSArray<NSString *> *> *chunks = [NSMutableArray array];

	NSMutableArray<NSString *> *chunk = [NSMutableArray arrayWithCapacity:limit];

	for (NSString *target in targets) {
		[chunk addObject:target];

		if (chunk.count == limit) {
			[chunks addObject:[chunk copy]];

			[chunk removeAllObjects];
		}
	}

	if (chunk.count > 0) {
		[chunks addObject:[chunk copy]];
	}

	return [chunks copy];
}

- (void)parseMaximumListEntries:(NSString *)listString
{
	NSParameterAssert(listString != nil);

	// Input: MAXLIST=beI:60   or   MAXLIST=b:60,e:60,I:60

	NSMutableDictionary<NSString *, NSNumber *> *maximumListEntries = [NSMutableDictionary dictionary];

	for (NSString *entry in [listString split:@","]) {
		NSInteger colonPosition = [entry stringPosition:@":"];

		if (colonPosition < 1) {
			continue;
		}

		NSString *modeSymbols = [entry substringToIndex:colonPosition];

		NSInteger limit = [entry substringAfterIndex:colonPosition].integerValue;

		if (limit <= 0) {
			continue;
		}

		for (NSString *modeSymbol in modeSymbols.characterStringBuffer) {
			maximumListEntries[modeSymbol] = @(limit);
		}
	}

	self.maximumListEntries = maximumListEntries;
}

- (NSUInteger)maximumListEntriesForModeSymbol:(NSString *)modeSymbol
{
	NSParameterAssert(modeSymbol != nil);

	return self.maximumListEntries[modeSymbol].unsignedIntegerValue;
}

- (BOOL)extendedListSupportsToken:(NSString *)token
{
	NSParameterAssert(token != nil);

	return [self.extendedListTokens containsObject:token.uppercaseString];
}

- (BOOL)isClientTagDenied:(NSString *)tagName
{
	NSParameterAssert(tagName != nil);

	// Input: CLIENTTAGDENY=*,-draft/typing,-foo
	//
	// "*" denies everything; "-name" re-allows one tag.

	BOOL denied = NO;

	for (NSString *entry in self.clientTagDenyList) {
		if ([entry isEqualToString:@"*"]) {
			denied = YES;
		} else if ([entry hasPrefix:@"-"]) {
			if ([[entry substringFromIndex:1] isEqualToStringIgnoringCase:tagName]) {
				return NO;
			}
		} else if ([entry isEqualToStringIgnoringCase:tagName]) {
			denied = YES;
		}
	}

	return denied;
}

#pragma mark -
#pragma mark Extended Bans

- (void)parseExtendedBans:(NSString *)banString
{
	NSParameterAssert(banString != nil);

	// Input: EXTBAN=~,qjncrRa   or   EXTBAN=,ACNOQRSTUacjmnprsz (no prefix)

	NSInteger commaPosition = [banString stringPosition:@","];

	if (commaPosition < 0) {
		self.extendedBanPrefix = nil;
		self.extendedBanTypes = banString.characterStringBuffer;

		return;
	}

	NSString *prefix = [banString substringToIndex:commaPosition];

	self.extendedBanPrefix = ((prefix.length == 0) ? nil : prefix);
	self.extendedBanTypes = [banString substringAfterIndex:commaPosition].characterStringBuffer;
}

- (nullable NSString *)descriptionForExtendedBanMask:(NSString *)mask
{
	NSParameterAssert(mask != nil);

	NSArray<NSString *> *types = self.extendedBanTypes;

	if (types.count == 0) {
		return nil;
	}

	NSString *prefix = self.extendedBanPrefix;

	NSString *body = mask;

	if (prefix) {
		if ([mask hasPrefix:prefix] == NO) {
			return nil;
		}

		body = [mask substringFromIndex:prefix.length];
	}

	/* A leading "~" after the prefix negates the match on Solanum/Charybdis. */
	BOOL negated = NO;

	if ([prefix isEqualToString:@"~"] == NO && [body hasPrefix:@"~"] && body.length > 1) {
		negated = YES;

		body = [body substringFromIndex:1];
	}

	if (body.length == 0) {
		return nil;
	}

	NSString *type = [body stringCharacterAtIndex:0];

	if ([types containsObject:type] == NO) {
		return nil;
	}

	NSString *argument = nil;

	if (body.length > 2 && [body characterAtIndex:1] == ':') {
		argument = [body substringFromIndex:2];
	} else if (body.length > 1 || prefix == nil) {
		/* "$a" alone is valid (any logged in user); "$a:" with no argument or a
		 bare letter without a prefix is not something we can describe. */
		return nil;
	}

	NSString *description = [self.class localizedDescriptionForExtendedBanType:type argument:argument];

	if (negated) {
		return TXTLS(@"IRC[6kq-xb]", description);
	}

	return description;
}

+ (NSString *)localizedDescriptionForExtendedBanType:(NSString *)type argument:(nullable NSString *)argument
{
	NSParameterAssert(type != nil);

	/* Letters are not standardized. The table below covers the meanings
	 shared by Solanum/Charybdis ($), UnrealIRCd (~) and InspIRCd. */
	NSDictionary<NSString *, NSString *> *table = @{
		@"a" : @"IRC[2nb-ka]",	// account
		@"c" : @"IRC[2nb-kc]",	// member of channel
		@"j" : @"IRC[2nb-kj]",	// banned from channel
		@"m" : @"IRC[2nb-km]",	// mute
		@"n" : @"IRC[2nb-kn]",	// nick change
		@"o" : @"IRC[2nb-ko]",	// operator
		@"O" : @"IRC[2nb-ko2]", // operator class
		@"q" : @"IRC[2nb-kq]",	// quiet
		@"r" : @"IRC[2nb-kr]",	// real name
		@"R" : @"IRC[2nb-kr2]", // registered account
		@"s" : @"IRC[2nb-ks]",	// server
		@"S" : @"IRC[2nb-ks2]", // security group
		@"t" : @"IRC[2nb-kt]",	// timed
		@"T" : @"IRC[2nb-kt2]", // text
		@"U" : @"IRC[2nb-ku]",	// unregistered
		@"x" : @"IRC[2nb-kx]",	// hostmask with real name
		@"z" : @"IRC[2nb-kz]",	// certificate fingerprint
	};

	NSString *key = table[type];

	if (key == nil) {
		if (argument) {
			return TXTLS(@"IRC[2nb-kk]", type, argument);
		}

		return TXTLS(@"IRC[2nb-kl]", type);
	}

	if (argument == nil) {
		return TXTLS(@"IRC[2nb-kl]", type);
	}

	return TXTLS(key, argument);
}

- (nullable NSString *)stringValueForConfiguration:(NSDictionary<NSString *, id> *)configuration
{
	NSParameterAssert(configuration != nil);

	/* This takes our cached configuration data and builds it into what it would look like if we
	 were to receive an actual 005. The only difference is this method formats each token that
	 is in our configuration cache to make them easier to see. We use bold for the tokens. 
	 This is pretty much only used in developer mode, but it could have other uses? */

	if (configuration.count == 0) {
		return nil;
	}

	NSMutableString *stringValue = [NSMutableString string];

	NSArray *sortedKeys = configuration.sortedDictionaryKeys;

	for (NSString *key in sortedKeys) {
		id value = configuration[key];

		if ([value isKindOfClass:[NSString class]]) {
			[stringValue appendFormat:@"\002%@\002=%@ ", key, value];
		} else {
			[stringValue appendFormat:@"\002%@ \002", key];
		}
	}

	return [stringValue copy];
}

- (nullable NSString *)stringValueForLastUpdate
{
	NSDictionary *configuration = self.cachedConfiguration.lastObject;

	if (configuration == nil) {
		return nil;
	}

	return [self stringValueForConfiguration:configuration];
}

- (NSArray<IRCModeInfo *> *)parseModes:(NSString *)modeString
{
	NSParameterAssert(modeString != nil);

	NSMutableArray<IRCModeInfo *> *modes = [NSMutableArray array];

	NSMutableString *modeStringMutable = [modeString mutableCopy];

	BOOL modeIsSet = NO;

	do {
		NSString *nextToken = modeStringMutable.token;

		if (nextToken.length == 0) {
			break;
		}

		UniChar nextCharacter = [nextToken characterAtIndex:0];

		if (nextCharacter != '+' && nextCharacter != '-') {
			continue;
		}

		modeIsSet = (nextCharacter == '+');

		nextToken = [nextToken substringFromIndex:1];

		for (NSUInteger i = 0; i < nextToken.length; i++) {
			nextCharacter = [nextToken characterAtIndex:i];

			if (nextCharacter == '-') {
				modeIsSet = NO;
			} else if (nextCharacter == '+') {
				modeIsSet = YES;
			} else {
				NSString *modeSymbol = [NSString stringWithUniChar:nextCharacter];

				IRCModeInfoMutable *mode = [[IRCModeInfoMutable alloc] initWithModeSymbol:modeSymbol
																				modeIsSet:modeIsSet];

				if ([self modeHasParameter:modeSymbol whenModeIsSet:modeIsSet]) {
					mode.modeParameter = modeStringMutable.token;
				}

				[modes addObject:[mode copy]];
			}
		}
	} while (modeStringMutable.length > 0);

	return [modes copy];
}

- (void)parseCaseMapping:(NSString *)caseMapping
{
	NSParameterAssert(caseMapping != nil);

	if ([caseMapping isEqualToStringIgnoringCase:@"ascii"]) {
		self.caseMapping = IRCISupportInfoCaseMappingASCII;
	} else if ([caseMapping isEqualToStringIgnoringCase:@"strict-rfc1459"]) {
		self.caseMapping = IRCISupportInfoCaseMappingStrictRFC1459;
	} else {
		/* rfc1459 is the default and also what we fall back
		 to for unknown values (e.g. rfc7613) because it is the
		 most lenient of the three. */
		self.caseMapping = IRCISupportInfoCaseMappingRFC1459;
	}
}

- (NSString *)casefoldString:(NSString *)string
{
	NSParameterAssert(string != nil);

	IRCISupportInfoCaseMapping caseMapping = self.caseMapping;

	NSString *lowercaseString = string.lowercaseString;

	if (caseMapping == IRCISupportInfoCaseMappingASCII) {
		return lowercaseString;
	}

	NSUInteger length = lowercaseString.length;

	if (length == 0) {
		return lowercaseString;
	}

	/* Fast path: most nicknames contain none of the special characters. */
	NSCharacterSet *specialCharacters = [NSCharacterSet characterSetWithCharactersInString:@"[]\\~"];

	if ([lowercaseString rangeOfCharacterFromSet:specialCharacters].location == NSNotFound) {
		return lowercaseString;
	}

	unichar *buffer = malloc(length * sizeof(unichar));

	[lowercaseString getCharacters:buffer range:NSMakeRange(0, length)];

	for (NSUInteger i = 0; i < length; i++) {
		switch (buffer[i]) {
		case '[':
			buffer[i] = '{';
			break;
		case ']':
			buffer[i] = '}';
			break;
		case '\\':
			buffer[i] = '|';
			break;
		case '~':
			if (caseMapping == IRCISupportInfoCaseMappingRFC1459) {
				buffer[i] = '^';
			}

			break;
		default:
			break;
		}
	}

	NSString *result = [NSString stringWithCharacters:buffer length:length];

	free(buffer);

	return result;
}

- (void)parseUserModeSymbols:(NSString *)modeString
{
	NSParameterAssert(modeString != nil);

	// Format: (qaohv)~&@%+

	/* Perform validation on placement of parentheses */
	NSInteger openingParenthesesPosition = [modeString stringPosition:@"("];
	NSInteger closingParenthesesPosition = [modeString stringPosition:@")"];

	/* Opening parenthesis must be the first character and the closing
	 parenthesis must exist with at least one symbol between them.
	 -stringPosition: returns -1 when the needle is not found. */
	if (openingParenthesesPosition != 0 || closingParenthesesPosition <= 1) {
		return;
	}

	/* Extract relevant information and ensure that they are equal length */
	NSString *modeSymbols = [modeString substringWithRange:NSMakeRange(1, (closingParenthesesPosition - 1))];

	NSString *characters = [modeString substringAfterIndex:closingParenthesesPosition];

	if (modeSymbols.length != characters.length) {
		return;
	}

	/* Begin processing modes */
	/* The mode symbols and characters are stored in separate arrays because
	 NSDictionary has no sense of order and the order of the user mode
	 symbols is very important to establish rank. */
	NSArray *modeSymbolsArray = modeSymbols.characterStringBuffer;
	NSArray *charactersArray = characters.characterStringBuffer;

	self.userModeSymbols = @{@"modeSymbols" : modeSymbolsArray, @"characters" : charactersArray};

	/* Update channel modes array so that we know these mode symbols are for user */
	NSMutableDictionary *channelModes = [self.channelModes mutableCopy];

	for (NSString *modeSymbol in modeSymbolsArray) {
		channelModes[modeSymbol] = @(_channelUserModeValue);
	}

	self.channelModes = channelModes;
}

- (BOOL)modeHasParameter:(NSString *)modeSymbol whenModeIsSet:(BOOL)whenModeIsSet
{
	NSParameterAssert(modeSymbol != nil);

	// Input: CHANMODES=A,B,C,D
	//
	// A = Always has a parameter.			Index: 1
	// B = Always has a parameter.			Index: 2
	// C = Only has a parameter when set.	Index: 3
	// D = Never has a parameter.			Index: 4

	NSUInteger modeIndex = [self.channelModes unsignedIntegerForKey:modeSymbol];

	if (modeIndex == 1 || modeIndex == 2 || modeIndex == _channelUserModeValue) {
		return YES;
	} else if (modeIndex == 3) {
		return whenModeIsSet;
	}

	return NO;
}

- (void)parseChannelModes:(NSString *)modeString
{
	NSParameterAssert(modeString != nil);

	// Input: CHANMODES=A,B,C,D
	//
	// A = Always has a parameter.			Index: 1
	// B = Always has a parameter.			Index: 2
	// C = Only has a parameter when set.	Index: 3
	// D = Never has a parameter.			Index: 4

	NSMutableDictionary *channelModes = [self.channelModes mutableCopy];

	NSArray *modes = [modeString split:@","];

	for (NSUInteger i = 0; i < modes.count; i++) {
		NSString *modeSet = modes[i];

		for (NSUInteger j = 0; j < modeSet.length; j++) {
			NSString *modeSymbol = [modeSet stringCharacterAtIndex:j];

			channelModes[modeSymbol] = @(i + 1);
		}
	}

	self.channelModes = channelModes;
}

- (nullable NSString *)userPrefixForModeSymbol:(NSString *)modeSymbol
{
	NSParameterAssert(modeSymbol != nil);

	NSArray *modeSymbols = self.userModeSymbols[@"modeSymbols"];

	NSUInteger modeSymbolIndex = [modeSymbols indexOfObject:modeSymbol];

	if (modeSymbolIndex == NSNotFound) {
		return 0;
	}

	NSArray *characters = self.userModeSymbols[@"characters"];

	return characters[modeSymbolIndex];
}

- (BOOL)modeSymbolIsUserPrefix:(NSString *)modeSymbol
{
	NSParameterAssert(modeSymbol != nil);

	return ([self userPrefixForModeSymbol:modeSymbol] != nil);
}

- (nullable NSString *)modeSymbolForUserPrefix:(NSString *)character
{
	NSParameterAssert(character != nil);

	NSArray *characters = self.userModeSymbols[@"characters"];

	NSUInteger characterIndex = [characters indexOfObject:character];

	if (characterIndex == NSNotFound) {
		return nil;
	}

	NSArray *modeSymbols = self.userModeSymbols[@"modeSymbols"];

	return modeSymbols[characterIndex];
}

- (BOOL)characterIsUserPrefix:(NSString *)character
{
	NSParameterAssert(character != nil);

	return ([self modeSymbolForUserPrefix:character] != nil);
}

- (NSUInteger)rankForUserPrefixWithMode:(NSString *)modeSymbol
{
	NSParameterAssert(modeSymbol != nil);

	NSArray *modeSymbols = self.userModeSymbols[@"modeSymbols"];

	NSUInteger modeSymbolIndex = [modeSymbols indexOfObject:modeSymbol];

	if (modeSymbolIndex == NSNotFound) {
		return 0;
	}

	return (IRCISupportInfoHighestUserPrefixRank - modeSymbolIndex);
}

- (NSString *)extractStatusMessagePrefixFromChannelNamed:(NSString *)channel
{
	NSArray *characters = self.statusMessageModeSymbols;

	return [self _extractCharacters:characters fromChannelNamed:channel];
}

- (NSString *)_extractCharacters:(NSArray<NSString *> *)characters fromChannelNamed:(NSString *)channel
{
	NSParameterAssert(characters != nil);
	NSParameterAssert(channel != nil);

	if (channel.length < 2) {
		return @"";
	}

	NSArray *channelNamePrefixes = self.channelNamePrefixes;

	for (NSString *character in characters) {
		if ([channel hasPrefix:character] == NO) {
			continue;
		}

		NSString *nextCharacter = [channel stringCharacterAtIndex:1];

		if ([channelNamePrefixes containsObject:nextCharacter]) {
			return character;
		}
	}

	return @"";
}

- (IRCModeInfo *)createModeWithSymbol:(NSString *)modeSymbol
{
	NSParameterAssert(modeSymbol != nil);

	return [[IRCModeInfo alloc] initWithModeSymbol:modeSymbol];
}

- (IRCModeInfo *)createModeWithSymbol:(NSString *)modeSymbol
							modeIsSet:(BOOL)modeIsSet
						modeParameter:(nullable NSString *)modeParameter
{
	NSParameterAssert(modeSymbol != nil);

	return [[IRCModeInfo alloc] initWithModeSymbol:modeSymbol modeIsSet:modeIsSet modeParameter:modeParameter];
}

- (BOOL)configurationReceived
{
	return (self.cachedConfiguration.count > 0);
}

- (BOOL)isListSupported:(IRCISupportInfoListType)listType
{
	return ([self modeSymbolForList:listType] != nil);
}

- (nullable NSString *)modeSymbolForList:(IRCISupportInfoListType)listType
{
	switch (listType) {
	case IRCISupportInfoListTypeBan: {
		return @"b";
	}
	case IRCISupportInfoListTypeBanException: {
		return self.banExceptionModeSymbol;
	}
	case IRCISupportInfoListTypeInviteException: {
		return self.inviteExceptionModeSymbol;
	}
	case IRCISupportInfoListTypeQuiet: {
		/* +q is used by some servers as the user mode for channel owner.
			 If this mode is a user mode, then hide the menu item. */
		if ([self modeSymbolIsUserPrefix:@"q"]) {
			return nil;
		}

		return @"q";
	}
	default: {
		return nil;
	}
	} // switch
}

- (nullable NSString *)statusMessagePrefixForModeSymbol:(NSString *)modeSymbol
{
	NSParameterAssert(modeSymbol != nil);

	NSString *character = [self userPrefixForModeSymbol:modeSymbol];

	if (character == nil) {
		return nil;
	}

	if ([self.statusMessageModeSymbols containsObject:character] == NO) {
		return nil;
	}

	return character;
}

@end

NS_ASSUME_NONNULL_END
