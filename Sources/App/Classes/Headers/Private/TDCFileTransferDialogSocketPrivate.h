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

@class TDCFileTransferDialogSocket;

/* A thin Network.framework wrapper used by DCC file transfers.
 One instance is either a listener (nw_listener_t) or a connection
 (nw_connection_t). Every delegate callback is delivered asynchronously
 on the delegate queue supplied at creation. Once -disconnect has been
 called, no further delegate callbacks are delivered. */
@protocol TDCFileTransferDialogSocketDelegate <NSObject>
@optional
/* Listener */
- (void)socket:(TDCFileTransferDialogSocket *)socket didStartListeningOnPort:(uint16_t)port;
- (void)socket:(TDCFileTransferDialogSocket *)socket didFailToListenWithError:(NSError *)error;

/* The accepted connection is already established and shares the delegate
 and delegate queue of the listener. */
- (void)socket:(TDCFileTransferDialogSocket *)socket didAcceptConnection:(TDCFileTransferDialogSocket *)connection;

/* Connection */
- (void)socketDidConnect:(TDCFileTransferDialogSocket *)socket;
- (void)socket:(TDCFileTransferDialogSocket *)socket didReadData:(NSData *)data;
- (void)socketDidWriteData:(TDCFileTransferDialogSocket *)socket;
- (void)socket:(TDCFileTransferDialogSocket *)socket didDisconnectWithError:(nullable NSError *)error;
@end

GLASSTUAL_EXTERN NSErrorDomain const TDCFileTransferDialogSocketErrorDomain;

typedef NS_ERROR_ENUM(TDCFileTransferDialogSocketErrorDomain, TDCFileTransferDialogSocketError){
	TDCFileTransferDialogSocketErrorConnectTimeout = 1,
	TDCFileTransferDialogSocketErrorWriteTimeout = 2,
	TDCFileTransferDialogSocketErrorClosedByPeer = 3,
	TDCFileTransferDialogSocketErrorNoOpenPort = 4,
	TDCFileTransferDialogSocketErrorBadParameter = 5,
};

@interface TDCFileTransferDialogSocket : NSObject
@property(readonly, weak, nullable) id<TDCFileTransferDialogSocketDelegate> delegate;
@property(readonly) dispatch_queue_t delegateQueue;
@property(readonly) BOOL isListener;
@property(readonly) BOOL isConnected;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDelegate:(id<TDCFileTransferDialogSocketDelegate>)delegate
				   delegateQueue:(dispatch_queue_t)delegateQueue NS_DESIGNATED_INITIALIZER;

+ (NSError *)errorWithCode:(TDCFileTransferDialogSocketError)code description:(NSString *)description;

/* Tries each port in [startPort, endPort] in turn until one can be bound.
 Reports the result through -socket:didStartListeningOnPort: or
 -socket:didFailToListenWithError: */
- (void)listenOnPortRangeFrom:(uint16_t)startPort to:(uint16_t)endPort;

/* interfaceName is a BSD interface name (e.g. "en0"). If it is given and
 has an address, the connection is bound to that address before connecting. */
- (void)connectToHost:(NSString *)host
				 port:(uint16_t)port
		 viaInterface:(nullable NSString *)interfaceName
			  timeout:(NSTimeInterval)timeout;

/* Reads whatever is available (at most 64 KiB). One -socket:didReadData:
 callback is delivered for each call. */
- (void)readData;

/* Queues data for sending. -socketDidWriteData: is delivered once the data
 has been handed to the transport. A write which is not completed within
 timeout seconds disconnects the socket with a write timeout error.
 A timeout <= 0 disables the timer. */
- (void)writeData:(NSData *)data timeout:(NSTimeInterval)timeout;

- (void)disconnect;
@end

NS_ASSUME_NONNULL_END
