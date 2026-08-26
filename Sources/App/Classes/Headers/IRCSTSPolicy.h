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

NS_ASSUME_NONNULL_BEGIN

/* IRCv3 Strict Transport Security (the "sts" capability).

 A server advertises "sts=port=6697,duration=N[,preload]". A policy is
 persisted per host only when it was received over TLS. On later
 connections to the host, an unexpired policy forces TLS on the policy
 port whatever the server configuration says. */

/* The values of one "sts=" capability as parsed from CAP LS / CAP NEW. */
@interface IRCSTSCapabilityValues : NSObject
@property(readonly) uint16_t port; // 0 when the port key is absent or invalid
@property(readonly) BOOL hasDuration;
@property(readonly)
    NSTimeInterval duration; // Seconds; meaningful when hasDuration
@property(readonly) BOOL preload;

+ (nullable instancetype)valuesFromCapabilityValues:
    (NSArray<NSString *> *)values;
@end

/* A stored policy. */
@interface IRCSTSPolicy : NSObject
@property(readonly) uint16_t port;
@property(readonly, copy) NSDate *expiresAt;
@property(readonly) BOOL preload;

@property(readonly) BOOL isExpired;

- (instancetype)initWithPort:(uint16_t)port
                   expiresAt:(NSDate *)expiresAt
                     preload:(BOOL)preload;
@end

/* What the client should do after the server offered "sts=". */
typedef NS_ENUM(NSUInteger, IRCSTSPolicyAction) {
  IRCSTSPolicyActionNone = 0, // Nothing usable in the values
  IRCSTSPolicyActionUpgrade,  // Plaintext connection: reconnect with TLS on
                              // -port
  IRCSTSPolicyActionStored,   // TLS connection: policy stored or refreshed
  IRCSTSPolicyActionCleared,  // TLS connection: duration=0, policy removed
};

/* The per host policy table. The shared store persists to user defaults
 under IRCSTSPolicyStoreDefaultsKey; tests build their own in memory. */
@interface IRCSTSPolicyStore : NSObject
@property(class, readonly, strong) IRCSTSPolicyStore *sharedStore;

- (instancetype)initWithUserDefaults:(nullable NSUserDefaults *)userDefaults;

/* The unexpired policy for the host, or nil. An expired policy is
 forgotten on lookup. Host comparison is case insensitive. */
- (nullable IRCSTSPolicy *)policyForHost:(NSString *)host;

- (void)setPolicy:(IRCSTSPolicy *)policy forHost:(NSString *)host;
- (void)removePolicyForHost:(NSString *)host;

/* Applies the policy to the parameters a connection is about to use.
 With an unexpired policy for the host, *port becomes the policy port and
 *secured becomes YES. Returns YES when the parameters were changed or
 confirmed by a policy, NO when there is none. */
- (BOOL)applyPolicyForHost:(NSString *)host
                    toPort:(inout uint16_t *)port
                   secured:(inout BOOL *)secured;

/* Decides what an "sts=" capability means for a connection to the host
 that is currently on `connectedPort`, over TLS or not. Policies are
 only written or cleared for TLS connections. The policy port is the
 advertised port when present, otherwise the connected port. Returns
 the action and, for an upgrade, the port to reconnect on in *upgradePort. */
- (IRCSTSPolicyAction)applyCapabilityValues:(IRCSTSCapabilityValues *)values
                                    forHost:(NSString *)host
                              connectedPort:(uint16_t)connectedPort
                                    secured:(BOOL)secured
                                upgradePort:(nullable uint16_t *)upgradePort;
@end

extern NSString *const IRCSTSPolicyStoreDefaultsKey;

NS_ASSUME_NONNULL_END
