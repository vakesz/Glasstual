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

NS_ASSUME_NONNULL_BEGIN

@class IRCNetwork;

typedef NS_ENUM(NSUInteger, IRCNetworkRegistration) {
	IRCNetworkRegistrationNone = 0, // The network has no account services
	IRCNetworkRegistrationOptional, // Accounts exist but are not required to chat
	IRCNetworkRegistrationRequired	// An account is required to connect or chat
};

/* The bundled list of well known networks (IRCNetworks.plist). Entries are
 sorted alphabetically by name. A separate "popular" subset is exposed for
 the onboarding flow. */
@interface IRCNetworkList : NSObject
@property(readonly, copy) NSArray<IRCNetwork *> *listOfNetworks;

/* Networks most people are looking for, in the order they should be shown.
 Every member is also present in -listOfNetworks. */
@property(readonly, copy) NSArray<IRCNetwork *> *popularNetworks;

- (nullable IRCNetwork *)networkNamed:(NSString *)networkName;
- (nullable IRCNetwork *)networkWithServerAddress:(NSString *)serverAddress;

/* Whether the account group (account name, password, SASL) applies to a
 network with the given registration policy and SASL support. Kept as a
 pure function so that it can be tested without a network object. */
+ (BOOL)accountFieldsApplyToRegistration:(IRCNetworkRegistration)registration saslSupported:(BOOL)saslSupported;

+ (IRCNetworkRegistration)registrationFromString:(nullable NSString *)string;
@end

#pragma mark -

@interface IRCNetwork : NSObject
@property(readonly, copy) NSString *networkName;
@property(readonly, copy) NSString *networkDescription;
@property(readonly, copy) NSString *serverAddress;
@property(readonly) uint16_t serverPort;
@property(readonly) BOOL prefersSecuredConnection;
@property(readonly, copy, nullable) NSString *website;
@property(readonly) BOOL saslSupported;
@property(readonly) IRCNetworkRegistration registration;
@property(readonly, copy, nullable) NSString *registrationNote;
@property(readonly, copy) NSArray<NSString *> *suggestedChannels;

/* YES when the picker should show the account group for this network. */
@property(readonly) BOOL accountFieldsApply;

- (instancetype)init NS_UNAVAILABLE;

/* Designated initializer. Returns nil when the name or address is missing.
 Used by the bundled list and by tests. */
- (nullable instancetype)initWithDictionary:(NSDictionary<NSString *, id> *)dictionary NS_DESIGNATED_INITIALIZER;
@end

NS_ASSUME_NONNULL_END
