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

#import "IRCClientConfigPrivate.h"
#import "IRCClientPrivate.h"

NS_ASSUME_NONNULL_BEGIN

/* A configuration that keeps the NickServ password in memory instead
 of the keychain. */
@interface GLTTestClientConfig : IRCClientConfig
@property(nonatomic, copy, nullable) NSString *testNicknamePassword;
@end

/* An IRCClient that never touches a socket. Everything that would have
 gone to the server or to a view is recorded so tests can inspect it. */
@interface GLTTestClient : IRCClient
@property(readonly, strong) NSMutableArray<NSString *> *sentCapabilityCommands; // "REQ sasl", "END"
@property(readonly, strong) NSMutableArray<NSString *> *sentLines;
@property(readonly, strong) NSMutableArray<IRCMessage *> *processedMessages;
@property(readonly, strong) NSMutableArray<NSDictionary<NSString *, id> *> *printedLines;

/* NO (the default) records messages without handling them. YES hands
 them to the real handlers as well, for tests that need state changes. */
@property(nonatomic, assign) BOOL forwardsProcessedMessages;

+ (instancetype)testClient;
+ (instancetype)testClientWithConfigDictionary:(NSDictionary<NSString *, id> *)dictionary;
+ (instancetype)testClientWithConfigDictionary:(NSDictionary<NSString *, id> *)dictionary
							  nicknamePassword:(nullable NSString *)nicknamePassword;

/* Pretend registration completed so commands that need it are sent. */
- (void)markAsLoggedIn;
@end

/* Handlers exercised directly by the tests. */
@interface IRCClient (GLTTestAccess)
- (void)processIncomingMessage:(IRCMessage *)message;
- (void)receiveBatch:(IRCMessage *)m;
- (BOOL)filterBatchCommandIncomingData:(IRCMessage *)m;
- (void)receiveStandardReply:(IRCMessage *)m;
- (void)receiveTagMessage:(IRCMessage *)m;
- (void)receiveJoin:(IRCMessage *)m;
- (void)receiveInvite:(IRCMessage *)m;
- (void)receiveAccountNotify:(IRCMessage *)m;
- (void)receiveSetName:(IRCMessage *)m;
- (void)receivePrivmsgAndNotice:(IRCMessage *)m;
- (void)receiveNumericReply:(IRCMessage *)m;
- (void)sendNextCapability;
- (void)receiveReadMarker:(IRCMessage *)m;
- (void)setIsLoggedIn:(BOOL)isLoggedIn;
- (BOOL)chatHistoryMessageIsDuplicate:(IRCMessage *)message;
- (void)scheduleReadMarkerForChannel:(IRCChannel *)channel date:(NSDate *)date;
- (void)onReadMarkerTimer;
- (void)requestPlayback;

/* SASL mechanism selection. */
- (BOOL)selectSASLMechanismFromOffered:(NSArray<NSString *> *)mechanisms;
@property(nonatomic, copy, nullable) NSString *saslMechanism;
@property(nonatomic, strong) NSMutableArray<NSString *> *saslTriedMechanisms;
- (BOOL)retrySASLNegotiationWithMechanisms:(NSArray<NSString *> *)mechanisms;

/* labeled-response delivery tracking. */
- (BOOL)labeledResponseTrackingEnabled;
- (nullable NSString *)registerPendingDeliveryForChannel:(nullable IRCChannel *)channel;
- (BOOL)resolveLabeledResponseForMessage:(IRCMessage *)m;
- (void)timeoutDeliveryWithLabel:(NSString *)label;
- (TVCLogLineDeliveryState)deliveryStateForLabel:(NSString *)label;
@end

NS_ASSUME_NONNULL_END
