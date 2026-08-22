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

#import "IRCClientPrivate.h"
#import "IRCDirectChatConnectionPrivate.h"
#import "TDCFileTransferDialogSocketPrivate.h"
#import "TPCPreferencesLocal.h"

NS_ASSUME_NONNULL_BEGIN

#define _connectTimeout 30.0
#define _writeTimeout 30.0

/* A single line is never allowed to grow without bound. */
#define _maximumLineLength (1024 * 16)

#define _assertMainQueue() dispatch_assert_queue(dispatch_get_main_queue())

@interface IRCDirectChatConnection () <TDCFileTransferDialogSocketDelegate>
@property(nonatomic, weak, readwrite) IRCClient *client;
@property(nonatomic, weak, readwrite, nullable) id<IRCDirectChatConnectionDelegate> delegate;
@property(nonatomic, copy, readwrite) NSString *peerNickname;
@property(nonatomic, copy, readwrite, nullable) NSString *hostAddress;
@property(nonatomic, assign, readwrite) uint16_t hostPort;
@property(nonatomic, copy, readwrite, nullable) NSString *transferToken;
@property(nonatomic, assign, readwrite) IRCDirectChatConnectionState state;
@property(nonatomic, assign) BOOL isListener;
@property(nonatomic, strong, nullable) TDCFileTransferDialogSocket *listeningServer;
@property(nonatomic, strong, nullable) TDCFileTransferDialogSocket *connection;
@property(nonatomic, strong, nullable) XRPortMapper *portMapping;
@property(nonatomic, strong) NSMutableData *lineBuffer;
@end

@implementation IRCDirectChatConnection

#pragma mark -
#pragma mark Initialization

+ (instancetype)connectionToPeer:(NSString *)nickname
						 address:(NSString *)hostAddress
							port:(uint16_t)hostPort
						onClient:(IRCClient *)client
						delegate:(id<IRCDirectChatConnectionDelegate>)delegate
{
	NSParameterAssert(hostAddress != nil);
	NSParameterAssert(hostPort != 0);

	IRCDirectChatConnection *object = [[self alloc] initWithPeer:nickname onClient:client delegate:delegate];

	object.hostAddress = hostAddress;
	object.hostPort = hostPort;

	object.isListener = NO;

	return object;
}

+ (instancetype)listeningConnectionForPeer:(NSString *)nickname
									 token:(nullable NSString *)transferToken
								  onClient:(IRCClient *)client
								  delegate:(id<IRCDirectChatConnectionDelegate>)delegate
{
	IRCDirectChatConnection *object = [[self alloc] initWithPeer:nickname onClient:client delegate:delegate];

	if (transferToken.length > 0) {
		object.transferToken = transferToken;
	}

	object.isListener = YES;

	return object;
}

- (instancetype)initWithPeer:(NSString *)nickname
					onClient:(IRCClient *)client
					delegate:(id<IRCDirectChatConnectionDelegate>)delegate
{
	NSParameterAssert(nickname != nil);
	NSParameterAssert(client != nil);
	NSParameterAssert(delegate != nil);

	if ((self = [super init])) {
		self.peerNickname = nickname;
		self.client = client;
		self.delegate = delegate;

		self.lineBuffer = [NSMutableData data];

		self.state = IRCDirectChatConnectionStateIdle;

		return self;
	}

	return nil;
}

- (void)dealloc
{
	[self tearDownSockets];
}

#pragma mark -
#pragma mark Properties

- (BOOL)isConnected
{
	return (self.state == IRCDirectChatConnectionStateConnected);
}

#pragma mark -
#pragma mark Open/Close

- (void)open
{
	_assertMainQueue();

	if (self.state != IRCDirectChatConnectionStateIdle) {
		return;
	}

	if (self.isListener) {
		[self openListener];
	} else {
		[self openConnection];
	}
}

- (void)openConnection
{
	self.state = IRCDirectChatConnectionStateConnecting;

	TDCFileTransferDialogSocket *connection =
		[[TDCFileTransferDialogSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];

	self.connection = connection;

	[connection connectToHost:self.hostAddress
						 port:self.hostPort
				 viaInterface:[TPCPreferences fileTransferIPAddressInterfaceName]
					  timeout:_connectTimeout];
}

- (void)openListener
{
	uint16_t portRangeStart = [TPCPreferences fileTransferPortRangeStart];
	uint16_t portRangeEnd = [TPCPreferences fileTransferPortRangeEnd];

	if (portRangeStart == 0 || portRangeStart > portRangeEnd) {
		[self closeWithError:[TDCFileTransferDialogSocket errorWithCode:TDCFileTransferDialogSocketErrorNoOpenPort
															description:@"The file transfer port range is invalid"]];

		return;
	}

	self.state = IRCDirectChatConnectionStateListening;

	TDCFileTransferDialogSocket *listeningServer =
		[[TDCFileTransferDialogSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];

	self.listeningServer = listeningServer;

	[listeningServer listenOnPortRangeFrom:portRangeStart to:portRangeEnd];
}

- (void)close
{
	_assertMainQueue();

	if (self.state == IRCDirectChatConnectionStateClosed) {
		return;
	}

	self.state = IRCDirectChatConnectionStateClosed;

	[self tearDownSockets];
}

- (void)closeWithError:(nullable NSError *)error
{
	if (self.state == IRCDirectChatConnectionStateClosed) {
		return;
	}

	[self close];

	[self.delegate directChatConnection:self didCloseWithError:error];
}

- (void)tearDownSockets
{
	XRPortMapper *portMapping = self.portMapping;

	if (portMapping) {
		[RZNotificationCenter() removeObserver:self name:XRPortMapperDidChangedNotification object:portMapping];

		self.portMapping = nil;

		[portMapping close];
	}

	TDCFileTransferDialogSocket *listeningServer = self.listeningServer;

	if (listeningServer) {
		self.listeningServer = nil;

		[listeningServer disconnect];
	}

	TDCFileTransferDialogSocket *connection = self.connection;

	if (connection) {
		self.connection = nil;

		[connection disconnect];
	}
}

#pragma mark -
#pragma mark Port Mapping

/* Mirrors the file transfer behaviour: try to map the port through the
 router, but advertise the listener either way. */
- (void)mapListeningPort:(uint16_t)port
{
	XRPortMapper *portMapping = [[XRPortMapper alloc] initWithPort:port];

	portMapping.mapTCP = YES;
	portMapping.mapUDP = NO;

	portMapping.desiredPublicPort = port;

	self.portMapping = portMapping;

	[RZNotificationCenter() addObserver:self
							   selector:@selector(portMapperDidFinishWork:)
								   name:XRPortMapperDidChangedNotification
								 object:portMapping];

	if ([portMapping open] == NO) {
		[self portMapperDidFinishWork:nil];
	}
}

- (void)portMapperDidFinishWork:(nullable NSNotification *)aNotification
{
	_assertMainQueue();

	if (self.state != IRCDirectChatConnectionStateListening) {
		return;
	}

	XRPortMapper *portMapping = self.portMapping;

	if (portMapping == nil) {
		return;
	}

	[RZNotificationCenter() removeObserver:self name:XRPortMapperDidChangedNotification object:portMapping];

	if (portMapping.isMapped) {
		LogToConsoleInfo("Direct chat: port %{public}hu mapped", self.hostPort);
	} else {
		LogToConsoleError("Direct chat: port mapping failed with error code %{public}i", portMapping.error);
	}

	[self.delegate directChatConnection:self didStartListeningOnPort:self.hostPort];
}

#pragma mark -
#pragma mark Sending

- (void)sendMessage:(NSString *)message
{
	NSParameterAssert(message != nil);

	[self sendLine:message];
}

- (void)sendAction:(NSString *)message
{
	NSParameterAssert(message != nil);

	[self sendLine:[NSString stringWithFormat:@"%cACTION %@%c", 0x01, message, 0x01]];
}

- (void)sendLine:(NSString *)line
{
	_assertMainQueue();

	if (self.isConnected == NO) {
		return;
	}

	/* A newline inside the text would be read by the peer as two
	 messages. The caller already split on newlines; this is a guard. */
	NSString *sanitizedLine = [line stringByReplacingOccurrencesOfString:@"\r" withString:@" "];

	sanitizedLine = [sanitizedLine stringByReplacingOccurrencesOfString:@"\n" withString:@" "];

	NSMutableData *data = [[self.client convertToCommonEncoding:sanitizedLine] mutableCopy];

	if (data == nil) {
		return;
	}

	[data appendBytes:"\r\n" length:2];

	[self.connection writeData:data timeout:_writeTimeout];
}

#pragma mark -
#pragma mark Receiving

- (void)consumeReceivedData:(NSData *)data
{
	NSMutableData *lineBuffer = self.lineBuffer;

	[lineBuffer appendData:data];

	while (lineBuffer.length > 0) {
		NSRange newlineRange = [lineBuffer rangeOfData:[NSData dataWithBytes:"\n" length:1]
											   options:0
												 range:NSMakeRange(0, lineBuffer.length)];

		if (newlineRange.location == NSNotFound) {
			if (lineBuffer.length > _maximumLineLength) {
				[self closeWithError:[TDCFileTransferDialogSocket
										 errorWithCode:TDCFileTransferDialogSocketErrorBadParameter
										   description:@"The peer sent a line which is too long"]];
			}

			return;
		}

		NSData *lineData = [lineBuffer subdataWithRange:NSMakeRange(0, newlineRange.location)];

		[lineBuffer replaceBytesInRange:NSMakeRange(0, newlineRange.location + 1) withBytes:NULL length:0];

		[self consumeReceivedLine:lineData];

		/* The delegate may have closed the chat in response. */
		if (self.state == IRCDirectChatConnectionStateClosed) {
			return;
		}
	}
}

- (void)consumeReceivedLine:(NSData *)lineData
{
	NSString *line = [self.client convertFromCommonEncoding:lineData];

	if (line == nil) {
		return;
	}

	line = [line stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];

	if (line.length == 0) {
		return;
	}

	BOOL isAction = NO;

	NSString *actionPrefix = [NSString stringWithFormat:@"%cACTION ", 0x01];

	if ([line hasPrefix:actionPrefix]) {
		NSUInteger prefixLength = actionPrefix.length;

		NSUInteger suffixLength = ([line hasSuffix:[NSString stringWithFormat:@"%c", 0x01]] ? 1 : 0);

		if (line.length > (prefixLength + suffixLength)) {
			line = [line substringWithRange:NSMakeRange(prefixLength, (line.length - prefixLength - suffixLength))];
		} else {
			line = @"";
		}

		isAction = YES;
	}

	[self.delegate directChatConnection:self didReceiveMessage:line isAction:isAction];
}

#pragma mark -
#pragma mark Socket Delegate

- (void)socket:(TDCFileTransferDialogSocket *)socket didStartListeningOnPort:(uint16_t)port
{
	_assertMainQueue();

	if (socket != self.listeningServer) {
		return;
	}

	self.hostPort = port;

	[self mapListeningPort:port];
}

- (void)socket:(TDCFileTransferDialogSocket *)socket didFailToListenWithError:(NSError *)error
{
	_assertMainQueue();

	if (socket != self.listeningServer) {
		return;
	}

	[self closeWithError:error];
}

- (void)socket:(TDCFileTransferDialogSocket *)socket didAcceptConnection:(TDCFileTransferDialogSocket *)connection
{
	_assertMainQueue();

	if (socket != self.listeningServer || self.state != IRCDirectChatConnectionStateListening) {
		[connection disconnect];

		return;
	}

	/* One peer only. Stop listening the moment somebody connects. */
	self.listeningServer = nil;

	[socket disconnect];

	self.connection = connection;

	[self connectionDidBecomeReady];
}

- (void)socketDidConnect:(TDCFileTransferDialogSocket *)socket
{
	_assertMainQueue();

	if (socket != self.connection || self.state != IRCDirectChatConnectionStateConnecting) {
		return;
	}

	[self connectionDidBecomeReady];
}

- (void)connectionDidBecomeReady
{
	self.state = IRCDirectChatConnectionStateConnected;

	[self.connection readData];

	[self.delegate directChatConnectionDidConnect:self];
}

- (void)socket:(TDCFileTransferDialogSocket *)socket didReadData:(NSData *)data
{
	_assertMainQueue();

	if (socket != self.connection || self.isConnected == NO) {
		return;
	}

	[self consumeReceivedData:data];

	if (self.isConnected) {
		[socket readData];
	}
}

- (void)socketDidWriteData:(TDCFileTransferDialogSocket *)socket
{
	/* Nothing to do. Writes are fire and forget. */
}

- (void)socket:(TDCFileTransferDialogSocket *)socket didDisconnectWithError:(nullable NSError *)error
{
	_assertMainQueue();

	if (socket != self.connection && socket != self.listeningServer) {
		return;
	}

	/* A clean close by the peer arrives as a "closed by peer" error.
	 Treat that as a normal end of the conversation. */
	if ([error.domain isEqualToString:TDCFileTransferDialogSocketErrorDomain] &&
		error.code == TDCFileTransferDialogSocketErrorClosedByPeer) {
		error = nil;
	}

	[self closeWithError:error];
}

@end

NS_ASSUME_NONNULL_END
