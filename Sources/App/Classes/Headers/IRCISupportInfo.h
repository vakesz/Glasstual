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

NS_ASSUME_NONNULL_BEGIN

@class IRCModeInfo;

typedef NS_ENUM(NSUInteger, IRCISupportInfoListType) {
	IRCISupportInfoListTypeBan,
	IRCISupportInfoListTypeBanException,
	IRCISupportInfoListTypeInviteException,
	IRCISupportInfoListTypeQuiet
};

typedef NS_ENUM(NSUInteger, IRCISupportInfoCaseMapping) {
	IRCISupportInfoCaseMappingRFC1459 = 0,	 // [ ] \ ~ fold to { } | ^ (default)
	IRCISupportInfoCaseMappingStrictRFC1459, // [ ] \ fold to { } |
	IRCISupportInfoCaseMappingASCII
};

#define IRCISupportInfoHighestUserPrefixRank 100

#define IRCISupportUserModeSymbolsSymbolsKey @"modeSymbols"
#define IRCISupportUserModeSymbolsCharactersKey @"characters"

@interface IRCISupportInfo : NSObject
@property(readonly) BOOL configurationReceived;
@property(readonly) NSUInteger maximumAwayLength;		 // 0 = no limit
@property(readonly) NSUInteger maximumChannelNameLength; // 0 = no limit - unused
@property(readonly) NSUInteger maximumKeyLength;		 // 0 = no limit
@property(readonly) NSUInteger maximumKickLength;		 // 0 = no limit
@property(readonly) NSUInteger maximumNicknameLength;
@property(readonly) NSUInteger maximumTopicLength; // 0 = no limit
@property(readonly) NSUInteger maximumModeCount;
@property(readonly, copy) NSArray<NSString *> *channelNamePrefixes;
@property(readonly, copy) NSArray<NSString *> *statusMessageModeSymbols;
@property(readonly, copy) NSDictionary<NSString *, NSNumber *> *channelModes;
@property(readonly, copy) NSDictionary<NSString *, NSArray *> *userModeSymbols;
@property(readonly, copy, nullable) NSString *banExceptionModeSymbol;
@property(readonly, copy, nullable) NSString *inviteExceptionModeSymbol;
@property(readonly, copy, nullable) NSString *serverAddress;
@property(readonly, copy, nullable) NSString *networkName;
@property(readonly, copy, nullable) NSString *networkNameFormatted;
@property(readonly) IRCISupportInfoCaseMapping caseMapping;

/* Tokens below are 0, nil, NO or empty when the server has not advertised them. */
@property(readonly) NSUInteger maximumLineLength;				   // LINELEN (bytes, includes CRLF). 0 = assume 512
@property(readonly) NSUInteger maximumTargets;					   // MAXTARGETS. 0 = no limit advertised
@property(readonly) NSUInteger maximumSilenceEntries;			   // SILENCE=<n>. 0 = no limit advertised
@property(readonly) BOOL silenceSupported;						   // SILENCE
@property(readonly) BOOL safeListSupported;						   // SAFELIST
@property(readonly) BOOL whoxSupported;							   // WHOX
@property(readonly) BOOL utf8Only;								   // UTF8ONLY
@property(readonly, copy, nullable) NSString *botModeSymbol;	   // BOT=<mode>
@property(readonly, copy, nullable) NSString *callerIDModeSymbol;  // CALLERID[=<mode>]
@property(readonly, copy, nullable) NSString *deafModeSymbol;	   // DEAF[=<mode>]
@property(readonly, copy, nullable) NSString *extendedBanPrefix;   // EXTBAN=<prefix>,<types>
@property(readonly, copy) NSArray<NSString *> *extendedBanTypes;   // EXTBAN=<prefix>,<types>
@property(readonly, copy) NSArray<NSString *> *extendedListTokens; // ELIST=<tokens> (uppercase)
@property(readonly, copy) NSArray<NSString *> *clientTagDenyList;  // CLIENTTAGDENY=<entries>
@property(readonly, copy) NSDictionary<NSString *, NSNumber *> *channelLimits;			 // CHANLIMIT: prefix -> limit
@property(readonly, copy) NSDictionary<NSString *, NSNumber *> *maximumListEntries;		 // MAXLIST: mode -> limit
@property(readonly, copy) NSDictionary<NSString *, NSNumber *> *maximumTargetsByCommand; // TARGMAX

/* Creates an instance that is not attached to a client.
 Tokens that trigger client side effects (NAMESX, UHNAMES, ...)
 are parsed but produce no side effects. */
- (instancetype)init;

/* CHANLIMIT: maximum number of channels with the prefix of channel that
 the user may join at once. 0 = no limit known. */
- (NSUInteger)channelLimitForChannelNamed:(NSString *)channel;

/* TARGMAX / MAXTARGETS: maximum number of targets that command (e.g. "PRIVMSG")
 accepts at once. 0 = no limit known. */
- (NSUInteger)maximumTargetsForCommand:(NSString *)command;

/* MAXLIST: maximum number of entries the list mode (e.g. "b") can hold. 0 = unknown. */
- (NSUInteger)maximumListEntriesForModeSymbol:(NSString *)modeSymbol;

/* ELIST: whether the server accepts the given search token (e.g. "U", "M"). */
- (BOOL)extendedListSupportsToken:(NSString *)token;

/* EXTBAN: localized description of an extended ban mask, or nil when
 mask is not an extended ban on this server. */
- (nullable NSString *)descriptionForExtendedBanMask:(NSString *)mask;

/* CLIENTTAGDENY: whether the server will drop the given client-only tag. */
- (BOOL)isClientTagDenied:(NSString *)tagName;

/* Splits targets into groups no larger than limit. A limit of 0
 returns every target in its own group (the conservative default). */
+ (NSArray<NSArray<NSString *> *> *)chunkTargets:(NSArray<NSString *> *)targets limit:(NSUInteger)limit;

/* Returns a casefolded copy of string according to the CASEMAPPING
 advertised by the server. Two nicknames (or channel names) are equal
 on the server if and only if their casefolded forms are equal. */
- (NSString *)casefoldString:(NSString *)string;

- (nullable NSString *)modeSymbolForUserPrefix:(NSString *)character;
- (nullable NSString *)userPrefixForModeSymbol:(NSString *)modeSymbol;

- (BOOL)characterIsUserPrefix:(NSString *)character;
- (BOOL)modeSymbolIsUserPrefix:(NSString *)modeSymbol;

- (nullable NSString *)statusMessagePrefixForModeSymbol:(NSString *)modeSymbol;
- (NSString *)extractStatusMessagePrefixFromChannelNamed:(NSString *)channel;

- (NSUInteger)rankForUserPrefixWithMode:(NSString *)modeSymbol; // Starts at 100; 100 = highest rank

- (IRCModeInfo *)createModeWithSymbol:(NSString *)modeSymbol;
- (IRCModeInfo *)createModeWithSymbol:(NSString *)modeSymbol
							modeIsSet:(BOOL)modeIsSet
						modeParameter:(nullable NSString *)modeParameter;

- (BOOL)isListSupported:(IRCISupportInfoListType)listType;

- (nullable NSString *)modeSymbolForList:(IRCISupportInfoListType)listType;
@end

NS_ASSUME_NONNULL_END
