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

@class IRCClient, IRCDirectChatConnection;

typedef NS_ENUM(NSUInteger, IRCDirectChatConnectionState) {
	IRCDirectChatConnectionStateIdle = 0,
	IRCDirectChatConnectionStateListening,	// Waiting for the peer to connect to us
	IRCDirectChatConnectionStateConnecting, // Connecting to the peer
	IRCDirectChatConnectionStateConnected,
	IRCDirectChatConnectionStateClosed,
};

@protocol IRCDirectChatConnectionDelegate <NSObject>
@required
/* The listener is up. The delegate is expected to advertise the
 port to the peer (DCC CHAT chat <address> <port> [token]). */
- (void)directChatConnection:(IRCDirectChatConnection *)connection didStartListeningOnPort:(uint16_t)port;
- (void)directChatConnectionDidConnect:(IRCDirectChatConnection *)connection;
/* One line of text from the peer. CTCP ACTION is already unwrapped. */
- (void)directChatConnection:(IRCDirectChatConnection *)connection
		   didReceiveMessage:(NSString *)message
					isAction:(BOOL)isAction;
/* error is nil when the peer closed the connection cleanly.
 Not delivered after -close. Delivered at most once. */
- (void)directChatConnection:(IRCDirectChatConnection *)connection didCloseWithError:(nullable NSError *)error;
@end

/* A DCC CHAT session. One instance is one TCP connection to one peer.
 All state belongs to the main queue: the socket delivers its callbacks
 there and every method below must be called from there. */
@interface IRCDirectChatConnection : NSObject
@property(readonly, weak) IRCClient *client;
@property(readonly, weak, nullable) id<IRCDirectChatConnectionDelegate> delegate;
@property(readonly, copy) NSString *peerNickname;
@property(readonly, copy, nullable) NSString *hostAddress;	 // Peer address (only when connecting to them)
@property(readonly) uint16_t hostPort;						 // Peer port, or the port we listen on
@property(readonly, copy, nullable) NSString *transferToken; // Passive (reverse) DCC only
@property(readonly) IRCDirectChatConnectionState state;
@property(getter=isConnected, readonly) BOOL connected;

- (instancetype)init NS_UNAVAILABLE;

/* Peer offered "DCC CHAT chat <address> <port>". We connect to them. */
+ (instancetype)connectionToPeer:(NSString *)nickname
						 address:(NSString *)hostAddress
							port:(uint16_t)hostPort
						onClient:(IRCClient *)client
						delegate:(id<IRCDirectChatConnectionDelegate>)delegate;

/* We offer the chat (or the peer asked for a passive one with token):
 listen on the configured DCC port range and wait for the peer. */
+ (instancetype)listeningConnectionForPeer:(NSString *)nickname
									 token:(nullable NSString *)transferToken
								  onClient:(IRCClient *)client
								  delegate:(id<IRCDirectChatConnectionDelegate>)delegate;

- (void)open;

- (void)sendMessage:(NSString *)message;
- (void)sendAction:(NSString *)message;

- (void)close;
@end

NS_ASSUME_NONNULL_END
