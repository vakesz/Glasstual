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

#import "IRCClient.h"

NS_ASSUME_NONNULL_BEGIN

/* Answers whether a capability may be requested at all. Used for
 capabilities that the user can switch off in Preferences. */
typedef BOOL (^IRCCapabilityPreferenceGate)(void);

/* Invoked for a capability that carries values on the wire
 (for example "sasl=PLAIN,EXTERNAL") once the server has offered it.
 `values` is the comma separated value list, or an empty array when
 the server advertised the capability without values. Return NO to
 leave the capability unrequested. */
typedef BOOL (^IRCCapabilityNegotiationHook)(IRCClient *client, NSArray<NSString *> *values);

/* One entry of the capability registry.

 A capability is identified on the wire by its name. The identifier is
 the set of ClientIRCv3SupportedCapability bits that are switched on
 when the server acknowledges the capability. Several names may share
 bits: "znc.in/server-time" switches on the same server-time bit as
 "server-time" so that the rest of the client does not have to know
 which of the two was negotiated. Internal pseudo capabilities, such as
 the MONITOR and WATCH command markers, have a name that never meets
 the socket and are never requested. */
@interface IRCCapability : NSObject
@property(readonly, copy) NSString *name;
@property(readonly) ClientIRCv3SupportedCapability identifier;
@property(readonly) BOOL requestedByDefault;
@property(readonly, copy, nullable) IRCCapabilityPreferenceGate preferenceGate;
@property(readonly, copy) NSArray<NSString *> *dependencies;
@property(readonly, copy, nullable) IRCCapabilityNegotiationHook negotiationHook;

/* YES when there is no preference gate or the gate allows the capability. */
@property(readonly) BOOL isEnabledByPreferences;

+ (instancetype)capabilityNamed:(NSString *)name identifier:(ClientIRCv3SupportedCapability)identifier;

+ (instancetype)capabilityNamed:(NSString *)name
					 identifier:(ClientIRCv3SupportedCapability)identifier
			 requestedByDefault:(BOOL)requestedByDefault;

- (instancetype)initWithName:(NSString *)name
				  identifier:(ClientIRCv3SupportedCapability)identifier
		  requestedByDefault:(BOOL)requestedByDefault
			  preferenceGate:(nullable IRCCapabilityPreferenceGate)preferenceGate
				dependencies:(nullable NSArray<NSString *> *)dependencies
			 negotiationHook:(nullable IRCCapabilityNegotiationHook)negotiationHook NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
@end

#pragma mark -

/* The table of capabilities the client knows about. The default registry
 is the one IRCClient negotiates with; tests build their own. */
@interface IRCCapabilityRegistry : NSObject
@property(class, readonly, strong) IRCCapabilityRegistry *defaultRegistry;

@property(readonly, copy) NSArray<IRCCapability *> *capabilities;

- (instancetype)initWithCapabilities:(NSArray<IRCCapability *> *)capabilities NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/* Lookup is case insensitive as capability names are on the wire. */
- (nullable IRCCapability *)capabilityNamed:(NSString *)name;

/* The first registered capability whose identifier covers every bit of
 the identifier given. */
- (nullable IRCCapability *)capabilityForIdentifier:(ClientIRCv3SupportedCapability)identifier;

/* YES when the capability is registered and allowed by preferences. */
- (BOOL)isCapabilitySupported:(NSString *)name;

/* Splits a CAP LS / CAP NEW payload into a name to values mapping:
 "sasl=PLAIN,EXTERNAL cap-notify" becomes
 { "sasl" : [ "PLAIN", "EXTERNAL" ], "cap-notify" : [] }. Keys are
 lowercased. */
+ (NSDictionary<NSString *, NSArray<NSString *> *> *)parseCapabilityList:(NSString *)list;

/* The capabilities to send in CAP REQ for the capabilities offered,
 in registry order. A capability is included when it is requested by
 default, allowed by preferences, offered by the server, and each of
 its dependencies is included as well. Negotiation hooks are not run;
 the caller evaluates them with the values in `offered`. */
- (NSArray<IRCCapability *> *)capabilitiesToRequestFromOffered:
	(NSDictionary<NSString *, NSArray<NSString *> *> *)offered;
@end

NS_ASSUME_NONNULL_END
