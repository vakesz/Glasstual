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
#import "TXGlobalModels.h"
#import "IRCClientPrivate.h"
#import "TPCPathInfo.h"
#import "TPCPreferencesLocal.h"
#import "TLOEncryptionManagerPrivate.h"
#import "TLOLocalization.h"
#import "TDCFileTransferDialogSocketPrivate.h"
#import "TDCFileTransferDialogTableCellPrivate.h"
#import "TDCFileTransferDialogTransferControllerPrivate.h"
#import "TDCFileTransferDialogInternal.h"

NS_ASSUME_NONNULL_BEGIN

#define RECORDS_LENGTH 10
#define MAX_QUEUE_SIZE 2
#define BUFFER_SIZE (1024 * 64)
#define RATE_LIMIT (1024 * 1024 * 10)

#define _connectTimeout 30.0
#define _sendDataTimeout 30.0
#define _resumeAcceptTimeout 10.0

/* Ownership: every piece of mutable state in this controller belongs to
 the main queue. The sockets run their own queues internally but deliver
 all delegate callbacks on the main queue, the maintenance timer fires on
 the main queue, the resume timeout is scheduled on the main run loop and
 IRCClient and the dialog call in from the main thread. The table cell
 reads the progress properties from the main thread as well. Because of
 this there is no locking: a status transition and the work that follows
 it are a single uninterrupted unit on one queue. */
#define _assertMainQueue() dispatch_assert_queue(dispatch_get_main_queue())

@interface TDCFileTransferDialogTransferController () <TDCFileTransferDialogSocketDelegate>
@property(nonatomic, strong, readwrite) IRCClient *client;
@property(nonatomic, copy, readwrite) NSString *clientId;
@property(nonatomic, assign, readwrite) BOOL isResume;
@property(nonatomic, assign, readwrite) BOOL isReversed;
@property(nonatomic, assign, readwrite) BOOL isSender;
@property(nonatomic, assign, readwrite) TDCFileTransferDialogTransferStatus transferStatus;
@property(nonatomic, assign, readwrite) uint64_t totalFilesize;
@property(nonatomic, assign, readwrite) uint64_t processedFilesize;
@property(nonatomic, assign, readwrite) uint64_t currentRecord;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *speedRecordsPrivate; // Main queue only
@property(nonatomic, copy, readwrite, nullable) NSString *errorMessageDescription;
@property(nonatomic, copy, readwrite, nullable) NSString *path;
@property(nonatomic, copy, readwrite) NSString *filename;
@property(nonatomic, copy, readwrite) NSString *hostAddress;
@property(nonatomic, copy, readwrite) NSString *peerNickname;
@property(nonatomic, copy, readwrite, nullable) NSString *transferToken;
@property(nonatomic, copy, readwrite) NSString *uniqueIdentifier;
@property(nonatomic, assign, readwrite) uint16_t hostPort;
@property(nonatomic, strong, nullable) NSFileHandle *fileHandle;
@property(nonatomic, strong, nullable) XRPortMapper *portMapping;
@property(nonatomic, assign) NSUInteger sendQueueSize;
@property(nonatomic, strong, nullable) TDCFileTransferDialogSocket *listeningServer;
@property(nonatomic, strong, nullable) TDCFileTransferDialogSocket *listeningServerConnectedClient;
@property(nonatomic, strong, nullable) TDCFileTransferDialogSocket *connectionToRemoteServer;
@property(nonatomic, strong, nullable) id transferProgressHandler; // Used to prevent system sleep
@property(readonly) uint64_t currentFilesize;
@property(readonly) TDCFileTransferDialog *transferDialog;
@property(readonly, nullable) TDCFileTransferDialogSocket *readSocket;
@property(readonly, nullable) TDCFileTransferDialogSocket *writeSocket;
@end

@implementation TDCFileTransferDialogTransferController

#pragma mark -
#pragma mark Initialization

+ (nullable instancetype)receiverForClient:(IRCClient *)client
								  nickname:(NSString *)nickname
								   address:(NSString *)hostAddress
									  port:(uint16_t)hostPort
								  filename:(NSString *)filename
								  filesize:(uint64_t)totalFilesize
									 token:(nullable NSString *)transferToken
{
	NSParameterAssert(client != nil);
	NSParameterAssert(nickname != nil);
	NSParameterAssert(hostAddress != nil);
	NSParameterAssert(filename != nil);

	/* Construct controller */
	TDCFileTransferDialogTransferController *controller = [[self alloc] initWithClient:client];

	if (transferToken.length > 0) {
		controller.transferToken = transferToken;

		controller.isReversed = YES;
	}

	controller.isSender = NO;

	controller.peerNickname = nickname;

	controller.hostAddress = hostAddress;
	controller.hostPort = hostPort;

	controller.filename = filename;

	controller.totalFilesize = totalFilesize;

	return controller;
}

+ (nullable instancetype)senderForClient:(IRCClient *)client nickname:(NSString *)nickname path:(NSString *)path
{
	NSParameterAssert(client != nil);
	NSParameterAssert(nickname != nil);
	NSParameterAssert(path != nil);

	NSString *filename = path.lastPathComponent;

#if GLASSTUAL_BUILT_WITH_ADVANCED_ENCRYPTION == 1
	if ([TPCPreferences textEncryptionIsEnabled]) {
		/* Ask whether we should be allowed to add the file. */
		BOOL allowWithOTR = [sharedEncryptionManager() safeToTransferFile:filename
																	   to:[client encryptionAccountNameForUser:nickname]
																	 from:[client encryptionAccountNameForLocalUser]
												   isIncomingFileTransfer:NO];

		if (allowWithOTR == NO) {
			return nil; // This operation is not allowed...
		}
	}
#endif

	/* Gather file information */
	NSDictionary *fileAttributes = [RZFileManager() attributesOfItemAtPath:path error:NULL];

	if (fileAttributes == nil) {
		return nil;
	}

	uint64_t totalFilesize = [fileAttributes fileSize];

	if (totalFilesize == 0) {
		LogToConsoleError("Fatal error: Cannot create sender because filesize == 0");

		return nil;
	}

	NSString *filePath = path.stringByDeletingLastPathComponent;

	/* Construct controller */
	TDCFileTransferDialogTransferController *controller = [[self alloc] initWithClient:client];

	controller.isReversed = [TPCPreferences fileTransferRequestsAreReversed];

	controller.isSender = YES;

	controller.peerNickname = nickname;

	controller.path = filePath;
	controller.filename = filename;

	controller.totalFilesize = totalFilesize;

	return controller;
}

- (instancetype)init
{
	[self doesNotRecognizeSelector:_cmd];

	return nil;
}

- (instancetype)initWithClient:(IRCClient *)client
{
	NSParameterAssert(client != nil);

	if ((self = [super init])) {
		self.client = client;
		self.clientId = client.uniqueIdentifier;

		[self prepareInitialState];

		return self;
	}

	return nil;
}

- (void)prepareInitialState
{
	_assertMainQueue();

	self.speedRecordsPrivate = [NSMutableArray array];

	self.transferStatus = TDCFileTransferDialogTransferStatusStopped;

	self.uniqueIdentifier = [NSString stringWithUUID];

	[RZNotificationCenter() addObserver:self
							   selector:@selector(clientDisconnected:)
								   name:IRCClientDidDisconnectNotification
								 object:self.client];
	[RZNotificationCenter() addObserver:self
							   selector:@selector(peerNicknameChanged:)
								   name:IRCClientUserNicknameChangedNotification
								 object:self.client];
}

- (void)prepareForPermanentDestruction
{
	_assertMainQueue();

	self.transferTableCell = nil;

	[self closeAndPostNotification:NO];

	[RZNotificationCenter() removeObserver:self];
}

#pragma mark -
#pragma mark Error Handling

- (void)failWithNoSpaceLeftOnDevice
{
	[self closeWithLocalizedError:@"TDCFileTransferDialog[79f-s0]"];
}

- (void)closeWithLocalizedError:(NSString *)errorLocalization
{
	[self closeWithLocalizedError:errorLocalization description:nil isFatalError:NO];
}

- (void)closeWithLocalizedError:(NSString *)errorLocalization isFatalError:(BOOL)isFatalError
{
	[self closeWithLocalizedError:errorLocalization description:nil isFatalError:isFatalError];
}

- (void)closeWithLocalizedError:(NSString *)errorLocalization description:(nullable NSString *)errorDescription
{
	[self closeWithLocalizedError:errorLocalization description:errorDescription isFatalError:NO];
}

- (void)closeWithLocalizedError:(NSString *)errorLocalization
					description:(nullable NSString *)errorDescription
				   isFatalError:(BOOL)isFatalError
{
	NSParameterAssert(errorLocalization != nil);

	if (errorDescription == nil) {
		self.errorMessageDescription = TXTLS(errorLocalization, self.peerNickname);
	} else {
		self.errorMessageDescription = TXTLS(errorLocalization, self.peerNickname, errorDescription);
	}

	if (isFatalError) {
		self.transferStatus = TDCFileTransferDialogTransferStatusFatalError;
	} else {
		self.transferStatus = TDCFileTransferDialogTransferStatusRecoverableError;
	}

	[self close];
}

#pragma mark -
#pragma mark Opening/Closing Transfer

- (void)disableSystemSleep
{
	self.transferProgressHandler = [RZProcessInfo() beginActivityWithOptions:NSActivityUserInitiated
																	  reason:@"Transferring file"];
}

- (void)enableSystemSleep
{
	if (self.transferProgressHandler == nil) {
		return;
	}

	[RZProcessInfo() endActivity:self.transferProgressHandler];

	self.transferProgressHandler = nil;
}

- (BOOL)receiveUnencryptedFile
{
#if GLASSTUAL_BUILT_WITH_ADVANCED_ENCRYPTION == 1
	if ([TPCPreferences textEncryptionIsEnabled]) {
		BOOL allowWithOTR =
			[sharedEncryptionManager() safeToTransferFile:self.filename
													   to:[self.client encryptionAccountNameForUser:self.peerNickname]
													 from:[self.client encryptionAccountNameForLocalUser]
								   isIncomingFileTransfer:YES];

		if (allowWithOTR == NO) {
			return NO; // This operation is not allowed...
		}
	}
#endif

	return YES;
}

- (void)open
{
	[self openWithPath:nil];
}

- (void)openWithPathOrUserDownloads
{
	NSString *path = nil;

	if (self.path == nil) {
		path = [TPCPathInfo userDownloads];
	}

	[self openWithPath:path];
}

- (void)openWithPath:(nullable NSString *)path
{
	_assertMainQueue();

	if (self.path == nil) {
		self.path = path;
	}

	if (self.client.isLoggedIn == NO) {
		[self _closeWithClientDisconnectedError];

		return;
	}

	if (self.isSender) {
		[self openTransfer];
	} else {
		if ([self receiveUnencryptedFile] == NO) {
			return;
		}

		[self sendTransferResumeRequestToClient];
	}
}

- (void)openTransfer
{
	if (self.isSender) {
		if (self.isReversed) {
			[self updateIPAddress];
		} else {
			[self openConnectionAsServer];
		}
	} else {
		if (self.isReversed) {
			[self openConnectionAsServer];
		} else {
			[self openConnectionToHost];
		}
	}
}

- (void)openConnectionToHost
{
	_assertMainQueue();

	[self closeAndPostNotification:NO];

	[self resetProperties];

	self.transferStatus = TDCFileTransferDialogTransferStatusConnecting;

	if (self.hostAddress.length == 0 || self.hostPort == 0) {
		LogToConsoleError("DCC Connect Error: Invalid host address or port");

		[self closeWithLocalizedError:@"TDCFileTransferDialog[fn8-sx]"];

		return;
	}

	TDCFileTransferDialogSocket *connectionToRemoteServer =
		[[TDCFileTransferDialogSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];

	self.connectionToRemoteServer = connectionToRemoteServer;

	/* Use the interface of the configured IP address instead of the default. */
	/* Default interface is used if IP address is not found locally. */
	NSString *networkInterface = [self networkInterfaceMatchingAddress];

	[connectionToRemoteServer connectToHost:self.hostAddress
									   port:self.hostPort
							   viaInterface:networkInterface
									timeout:_connectTimeout];

	[self disableSystemSleep];
}

- (void)openConnectionAsServer
{
	_assertMainQueue();

	[self closeAndPostNotification:NO];

	[self resetProperties];

	self.transferStatus = TDCFileTransferDialogTransferStatusInitializing;

	uint16_t portRangeStart = [TPCPreferences fileTransferPortRangeStart];
	uint16_t portRangeEnd = [TPCPreferences fileTransferPortRangeEnd];

	if (portRangeStart == 0 || portRangeStart > portRangeEnd) {
		[self closeWithLocalizedError:@"TDCFileTransferDialog[vxc-sd]"];

		return;
	}

	TDCFileTransferDialogSocket *listeningServer =
		[[TDCFileTransferDialogSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];

	self.listeningServer = listeningServer;

	/* The result is delivered to -socket:didStartListeningOnPort:
	 or -socket:didFailToListenWithError: */
	[listeningServer listenOnPortRangeFrom:portRangeStart to:portRangeEnd];

	[self disableSystemSleep];
}

- (void)listeningServerDidStartOnPort:(uint16_t)port
{
	NSAssertReturn(self.transferStatus == TDCFileTransferDialogTransferStatusInitializing);

	self.hostPort = port;

	/* Try to map the port */
	XRPortMapper *portMapping = [[XRPortMapper alloc] initWithPort:self.hostPort];

	portMapping.mapTCP = YES;
	portMapping.mapUDP = NO;

	portMapping.desiredPublicPort = self.hostPort;

	self.portMapping = portMapping;

	[RZNotificationCenter() addObserver:self
							   selector:@selector(portMapperDidFinishWork:)
								   name:XRPortMapperDidChangedNotification
								 object:self.portMapping];

	self.transferStatus = TDCFileTransferDialogTransferStatusMappingListeningPort;

	if ([self.portMapping open] == NO) {
		[self portMapperDidFinishWork:nil];
	}
}

- (nullable NSString *)networkInterfaceMatchingAddress
{
	return [TPCPreferences fileTransferIPAddressInterfaceName];
}

- (void)portMapperDidFinishWork:(nullable NSNotification *)aNotification
{
	NSAssertReturn(self.transferStatus == TDCFileTransferDialogTransferStatusMappingListeningPort);

	if (self.portMapping.isMapped) {
		[self updateIPAddress];

		LogToConsoleInfo("Successful port mapping on port %{public}hu", self.hostPort);

		return;
	}

	LogToConsoleError("Port mapping failed with error code: %{public}i", self.portMapping.error);

	if (self.isReversed) {
		[self closeWithLocalizedError:@"TDCFileTransferDialog[vxc-sd]"];

		return;
	}

	/* If mapping fails, we silently fail */
	/* We tried and it was successful, then that is good, but if we
	 did not, still start listening just incase other conditions allow
	 the transfer to still take place. */
	[self updateIPAddress];
}

- (void)updateIPAddress
{
	LogStackTraceWithType(LogToConsoleTypeDebug);

	NSString *address = self.transferDialog.IPAddress;

	LogToConsoleDebug("TDCFileTransferDialog cached IP address: %{private}@", address);

	TXFileTransferIPAddressMethodDetection detectionMethod = [TPCPreferences fileTransferIPAddressDetectionMethod];

	BOOL manuallyDetect = (detectionMethod == TXFileTransferIPAddressMethodManual);

	if (address == nil && manuallyDetect == NO) {
		NSString *publicAddress = self.portMapping.publicAddress;

		LogToConsoleDebug("Port mapper public IP address: %{private}@", publicAddress);

		if (publicAddress.isIPAddress) {
			self.transferDialog.IPAddress = publicAddress;

			address = publicAddress;
		}
	}

	/* Request address? */
	if (address == nil) {
		if (manuallyDetect || detectionMethod == TXFileTransferIPAddressMethodRouterOnly) {
			LogToConsoleError("User has set IP address detection to be manual but have no address set");

			[self noteIPAddressLookupFailed];
		} else {
			LogToConsoleDebug("Performing IP address lookup using the Internet");

			[self.transferDialog requestIPAddress];

			self.transferStatus = TDCFileTransferDialogTransferStatusWaitingForLocalIPAddress;
		}

		return;
	}

	[self noteIPAddressLookupSucceeded];
}

- (void)closePortMapping
{
	if (self.portMapping == nil) {
		return;
	}

	XRPortMapper *portMapping = self.portMapping;

	[RZNotificationCenter() removeObserver:self name:XRPortMapperDidChangedNotification object:portMapping];

	self.portMapping = nil;

	[portMapping close];
}

- (void)noteIPAddressLookupSucceeded
{
	LogStackTraceWithType(LogToConsoleTypeDebug);

	if (self.isSender) {
		if (self.isReversed) {
			self.transferStatus = TDCFileTransferDialogTransferStatusWaitingForReceiverToAccept;
		} else {
			self.transferStatus = TDCFileTransferDialogTransferStatusIsListeningAsSender;
		}
	} else {
		if (self.isReversed) {
			self.transferStatus = TDCFileTransferDialogTransferStatusIsListeningAsReceiver;
		} else {
			return;
		}
	}

	[self sendTransferRequestToClient];
}

- (void)noteIPAddressLookupFailed
{
	[self closeWithLocalizedError:@"TDCFileTransferDialog[47s-1s]"];
}

- (void)didReceiveResumeRequest:(uint64_t)proposedPosition
{
	_assertMainQueue();

	uint64_t currentFilesize = self.currentFilesize;

	if (proposedPosition == 0 || currentFilesize < proposedPosition) {
		return;
	}

	self.isResume = YES;

	self.processedFilesize = proposedPosition;

	[self sendTransferResumeAcceptToClient];
}

- (void)didReceiveResumeAccept:(uint64_t)proposedPosition
{
	_assertMainQueue();

	[self cancelPerformRequestsWithSelector:@selector(transferResumeRequestTimeout) object:nil];

	uint64_t currentFilesize = self.currentFilesize;

	if (currentFilesize != proposedPosition) {
		[self closeWithLocalizedError:@"TDCFileTransferDialog[0ov-tr]" isFatalError:YES];

		return;
	}

	self.isResume = YES;

	self.processedFilesize = currentFilesize;

	[self openTransfer];
}

- (void)didReceiveSendRequest:(NSString *)hostAddress hostPort:(uint16_t)hostPort
{
	NSParameterAssert(hostAddress != nil);

	_assertMainQueue();

	self.hostAddress = hostAddress;

	self.hostPort = hostPort;

	self.processedFilesize = 0;

	[self openConnectionToHost];
}

- (void)buildTransferToken
{
	NSUInteger loopedCount = 0;

	do {
		NSString *transferToken = [NSString stringWithUnsignedInteger:TXRandomNumber(9999)];

		BOOL transferExists = [self.transferDialog fileTransferExistsWithToken:transferToken];

		if (transferExists == NO) {
			self.transferToken = transferToken;

			break;
		}

		loopedCount += 1;
	} while (loopedCount < 300);
}

- (void)sendTransferRequestToClient
{
	if (self.isSender) {
		uint64_t currentFilesize = self.currentFilesize;

		if (self.isReversed) {
			[self buildTransferToken];

			[self.client sendFile:self.peerNickname
							 port:0
						 filename:self.filename
						 filesize:currentFilesize
							token:self.transferToken];
		} else {
			[self.client sendFile:self.peerNickname
							 port:self.hostPort
						 filename:self.filename
						 filesize:currentFilesize
							token:nil];
		}
	} else {
		if (self.isReversed) {
			[self.client sendFile:self.peerNickname
							 port:self.hostPort
						 filename:self.filename
						 filesize:self.totalFilesize
							token:self.transferToken];
		}
	}
}

- (void)sendTransferResumeRequestToClient
{
	_assertMainQueue();

	uint64_t currentFilesize = self.currentFilesize;

	if (currentFilesize == 0 || currentFilesize > self.totalFilesize) {
		[self transferResumeRequestTimeout];

		return;
	}

	/* Scheduled on the main run loop. -closeAndPostNotification: cancels
	 it from the main queue as well, so the cancel always finds it. */
	[self performSelectorInCommonModes:@selector(transferResumeRequestTimeout)
							withObject:nil
							afterDelay:_resumeAcceptTimeout];

	self.transferStatus = TDCFileTransferDialogTransferStatusWaitingForResumeAccept;

	if (self.isReversed) {
		[self.client sendFileResume:self.peerNickname
							   port:0
						   filename:self.filename
						   filesize:currentFilesize
							  token:self.transferToken];
	} else {
		[self.client sendFileResume:self.peerNickname
							   port:self.hostPort
						   filename:self.filename
						   filesize:currentFilesize
							  token:nil];
	}
}

- (void)sendTransferResumeAcceptToClient
{
	if (self.isReversed) {
		[self.client sendFileResumeAccept:self.peerNickname
									 port:0
								 filename:self.filename
								 filesize:self.processedFilesize
									token:self.transferToken];
	} else {
		[self.client sendFileResumeAccept:self.peerNickname
									 port:self.hostPort
								 filename:self.filename
								 filesize:self.processedFilesize
									token:nil];
	}
}

- (void)transferResumeRequestTimeout
{
	[self openTransfer];
}

- (void)peerNicknameChanged:(NSNotification *)notification
{
	NSDictionary *userInfo = notification.userInfo;

	NSString *oldNickname = userInfo[@"oldNickname"];

	if ([self.peerNickname isEqualToString:oldNickname] == NO) {
		return;
	}

	self.peerNickname = userInfo[@"newNickname"];
}

- (void)clientDisconnected:(NSNotification *)notification
{
	/* IRCClient posts this from the main thread. */
	[self closeWithClientDisconnectedError];
}

- (void)closeWithClientDisconnectedError
{
	/* If the controller is already sending or receiving data, then a connection
	 is already established to the peer which can function without a connection
	 to IRC. If data is not being transferred then fail immediately. */
	TDCFileTransferDialogTransferStatus transferStatus = self.transferStatus;

	if (transferStatus != TDCFileTransferDialogTransferStatusConnecting &&
		transferStatus != TDCFileTransferDialogTransferStatusInitializing &&
		transferStatus != TDCFileTransferDialogTransferStatusIsListeningAsReceiver &&
		transferStatus != TDCFileTransferDialogTransferStatusIsListeningAsSender &&
		transferStatus != TDCFileTransferDialogTransferStatusMappingListeningPort &&
		transferStatus != TDCFileTransferDialogTransferStatusWaitingForLocalIPAddress &&
		transferStatus != TDCFileTransferDialogTransferStatusWaitingForReceiverToAccept &&
		transferStatus != TDCFileTransferDialogTransferStatusWaitingForResumeAccept) {
		return;
	}

	[self _closeWithClientDisconnectedError];
}

- (void)_closeWithClientDisconnectedError
{
	[self closeWithLocalizedError:@"TDCFileTransferDialog[12p-0v]" isFatalError:NO];
}

- (void)close
{
	[self closeAndPostNotification:YES];
}

- (void)closeAndPostNotification:(BOOL)postNotification
{
	_assertMainQueue();

	[self cancelPerformRequests];

	if (self.listeningServer) {
		[self.listeningServer disconnect];
		self.listeningServer = nil;
	}

	if (self.listeningServerConnectedClient) {
		[self.listeningServerConnectedClient disconnect];
		self.listeningServerConnectedClient = nil;
	}

	if (self.connectionToRemoteServer) {
		[self.connectionToRemoteServer disconnect];
		self.connectionToRemoteServer = nil;
	}

	[self closePortMapping];

	[self closeFileHandle];

	if (self.transferStatus != TDCFileTransferDialogTransferStatusComplete &&
		self.transferStatus != TDCFileTransferDialogTransferStatusFatalError &&
		self.transferStatus != TDCFileTransferDialogTransferStatusRecoverableError) {
		self.transferStatus = TDCFileTransferDialogTransferStatusStopped;
	}

	if (postNotification) {
		if (self.transferStatus == TDCFileTransferDialogTransferStatusFatalError ||
			self.transferStatus == TDCFileTransferDialogTransferStatusRecoverableError) {
			if (self.isSender) {
				[self.client notifyFileTransfer:TXNotificationTypeFileTransferSendFailed
									   nickname:self.peerNickname
									   filename:self.filename
									   filesize:self.totalFilesize
							  requestIdentifier:self.uniqueIdentifier];
			} else {
				[self.client notifyFileTransfer:TXNotificationTypeFileTransferReceiveFailed
									   nickname:self.peerNickname
									   filename:self.filename
									   filesize:self.totalFilesize
							  requestIdentifier:self.uniqueIdentifier];
			}
		} else if (self.transferStatus == TDCFileTransferDialogTransferStatusComplete) {
			if (self.isSender) {
				[self.client notifyFileTransfer:TXNotificationTypeFileTransferSendSuccessful
									   nickname:self.peerNickname
									   filename:self.filename
									   filesize:self.totalFilesize
							  requestIdentifier:self.uniqueIdentifier];
			} else {
				[self.client notifyFileTransfer:TXNotificationTypeFileTransferReceiveSuccessful
									   nickname:self.peerNickname
									   filename:self.filename
									   filesize:self.totalFilesize
							  requestIdentifier:self.uniqueIdentifier];
			}
		}
	}

	[self.transferDialog updateMaintenanceTimer];

	[self enableSystemSleep];
}

#pragma mark -
#pragma mark Timer

- (void)onMaintenanceTimer
{
	_assertMainQueue();

	NSAssertReturn(self.transferStatus == TDCFileTransferDialogTransferStatusReceiving ||
				   self.transferStatus == TDCFileTransferDialogTransferStatusSending);

	[self.speedRecordsPrivate addObject:@(self.currentRecord)];

	if (self.speedRecordsPrivate.count > RECORDS_LENGTH) {
		[self.speedRecordsPrivate removeObjectAtIndex:0];
	}

	self.currentRecord = 0;

	[self reloadStatusInformation];

	[self send];
}

#pragma mark -
#pragma mark File Handle

- (void)setNonexistentFilename
{
	NSString *filePath = self.filePath;

	if ([RZFileManager() fileExistsAtPath:filePath] == NO) {
		return;
	}

	NSString *filenameExtension = self.filename.pathExtension;

	NSString *filenameWithoutExtension = self.filename.stringByDeletingPathExtension;

	NSUInteger i = 1;

	do {
		NSString *newFilename = nil;

		if (filenameExtension.length == 0) {
			newFilename = [NSString stringWithFormat:@"%@_%lu", filenameWithoutExtension, i];
		} else {
			newFilename = [NSString stringWithFormat:@"%@_%lu.%@", filenameWithoutExtension, i, filenameExtension];
		}

		filePath = [self.path stringByAppendingPathComponent:newFilename];

		i += 1;
	} while ([RZFileManager() fileExistsAtPath:filePath]);

	self.filename = filePath.lastPathComponent;
}

- (BOOL)openFileHandle
{
	NSString *filePath = self.filePath;

	if (self.isSender == NO && self.isResume == NO) {
		[self setNonexistentFilename];

		[RZFileManager() createFileAtPath:filePath contents:[NSData data] attributes:nil];
	}

	NSFileHandle *fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:filePath];

	if (fileHandle == nil) {
		[self closeWithLocalizedError:@"TDCFileTransferDialog[nab-dx]"];

		return NO;
	}

	if (self.isResume) {
		NSError *seekError = nil;

		if ([fileHandle seekToOffset:self.processedFilesize error:&seekError] == NO) {
			LogToConsoleError("Failed to seek file handle: %{public}@", seekError.localizedDescription);

			[fileHandle closeAndReturnError:NULL];

			[self closeWithLocalizedError:@"TDCFileTransferDialog[nab-dx]"];

			return NO;
		}
	}

	self.fileHandle = fileHandle;

	return YES;
}

- (void)closeFileHandle
{
	if (self.fileHandle == nil) {
		return;
	}

	NSError *closeError = nil;

	if ([self.fileHandle closeAndReturnError:&closeError] == NO) {
		LogToConsoleError("Failed to close file handle: %{public}@", closeError.localizedDescription);
	}

	self.fileHandle = nil;
}

#pragma mark -
#pragma mark Socket Delegate

- (void)socket:(TDCFileTransferDialogSocket *)socket didStartListeningOnPort:(uint16_t)port
{
	_assertMainQueue();

	if (socket != self.listeningServer) {
		return;
	}

	[self listeningServerDidStartOnPort:port];
}

- (void)socket:(TDCFileTransferDialogSocket *)socket didFailToListenWithError:(NSError *)error
{
	_assertMainQueue();

	if (socket != self.listeningServer) {
		return;
	}

	LogToConsoleError("DCC Listen Error: %{public}@", error.localizedDescription);

	[self closeWithLocalizedError:@"TDCFileTransferDialog[vxc-sd]"];
}

- (void)socket:(TDCFileTransferDialogSocket *)socket didAcceptConnection:(TDCFileTransferDialogSocket *)connection
{
	_assertMainQueue();

	if (socket != self.listeningServer || self.isActingAsServer == NO) {
		[connection disconnect];

		return;
	}

	if (self.listeningServerConnectedClient == nil) {
		self.listeningServerConnectedClient = connection;
	} else {
		[connection disconnect];

		return;
	}

	if (self.isReversed) {
		self.transferStatus = TDCFileTransferDialogTransferStatusReceiving;
	} else {
		self.transferStatus = TDCFileTransferDialogTransferStatusSending;
	}

	[self.transferDialog updateMaintenanceTimer];

	if ([self openFileHandle] == NO) {
		return;
	}

	if (self.isReversed) {
		[self.readSocket readData];
	} else {
		[self send];
	}
}

- (void)socketDidConnect:(TDCFileTransferDialogSocket *)socket
{
	_assertMainQueue();

	if (socket != self.connectionToRemoteServer || self.isActingAsClient == NO) {
		return;
	}

	if (self.isReversed == NO) {
		self.transferStatus = TDCFileTransferDialogTransferStatusReceiving;
	} else {
		self.transferStatus = TDCFileTransferDialogTransferStatusSending;
	}

	[self.transferDialog updateMaintenanceTimer];

	if ([self openFileHandle] == NO) {
		return;
	}

	if (self.isReversed == NO) {
		[self.readSocket readData];
	} else {
		[self send];
	}
}

- (void)socket:(TDCFileTransferDialogSocket *)socket didDisconnectWithError:(nullable NSError *)error
{
	_assertMainQueue();

	if (socket != self.listeningServer && socket != self.listeningServerConnectedClient &&
		socket != self.connectionToRemoteServer) {
		return;
	}

	if (self.transferStatus == TDCFileTransferDialogTransferStatusComplete ||
		self.transferStatus == TDCFileTransferDialogTransferStatusFatalError ||
		self.transferStatus == TDCFileTransferDialogTransferStatusRecoverableError) {
		return;
	}

	if (error) {
		[self closeWithLocalizedError:@"TDCFileTransferDialog[s79-3a]" description:error.localizedDescription];
	} else {
		[self close];
	}
}

- (void)socket:(TDCFileTransferDialogSocket *)socket didReadData:(NSData *)data
{
	_assertMainQueue();

	if (socket != self.readSocket || self.isSender != NO) {
		return;
	}

	/* Update progress */
	self.currentRecord += data.length;

	self.processedFilesize += data.length;

	if (data.length > 0) {
		NSError *writeError = nil;

		if ([self.fileHandle writeData:data error:&writeError] == NO) {
			LogToConsoleError("Failed to write data: %{public}@", writeError.localizedDescription);

			if ([writeError.domain isEqualToString:NSPOSIXErrorDomain] && writeError.code == ENOSPC) {
				[self failWithNoSpaceLeftOnDevice];

				return;
			}

			[self closeWithLocalizedError:@"TDCFileTransferDialog[05g-c8]"];

			return;
		}
	}

	/* Send acknowledgement back to server */
	uint32_t processedFilesize = (self.processedFilesize & 0xFFFFFFFF);

	unsigned char ackPacket[4];

	ackPacket[0] = ((processedFilesize >> 24) & 0xFF);
	ackPacket[1] = ((processedFilesize >> 16) & 0xFF);
	ackPacket[2] = ((processedFilesize >> 8) & 0xFF);
	ackPacket[3] = (processedFilesize & 0xFF);

	NSData *ackPacketData = [NSData dataWithBytes:ackPacket length:4];

	[self.readSocket writeData:ackPacketData timeout:(-1)];

	/* Continue requesting data if the transfer is not complete */
	if (self.processedFilesize < self.totalFilesize) {
		[self.readSocket readData];

		return;
	}

	/* Update status and tear down transfer */
	self.transferStatus = TDCFileTransferDialogTransferStatusComplete;

	[self close];
}

#pragma mark -
#pragma mark Socket Write

- (void)socketDidWriteData:(TDCFileTransferDialogSocket *)socket
{
	_assertMainQueue();

	if (socket != self.writeSocket || self.isSender == NO) {
		return;
	}

	/* Acknowledge sent data */
	self.sendQueueSize -= 1;

	/* Continue sending data if the transfer is not complete */
	if (self.processedFilesize < self.totalFilesize) {
		[self send];

		return;
	}

	/* Wait until the send queue has cleared before closing 
	 connection. Just because we finished processing the 
	 data here doesn't mean it has been sent yet. */
	if (self.sendQueueSize > 0) {
		return;
	}

	/* Update status and tear down transfer */
	self.transferStatus = TDCFileTransferDialogTransferStatusComplete;

	[self close];
}

- (void)send
{
	if (self.isSender == NO) {
		return;
	}

	if (self.transferStatus != TDCFileTransferDialogTransferStatusSending) {
		return;
	}

	do {
		if (self.currentRecord >= RATE_LIMIT) {
			return;
		}

		if (self.sendQueueSize >= MAX_QUEUE_SIZE) {
			return;
		}

		if (self.processedFilesize >= self.totalFilesize) {
			return;
		}

		NSError *readError = nil;

		NSData *dataToWrite = [self.fileHandle readDataUpToLength:BUFFER_SIZE error:&readError];

		if (dataToWrite == nil || dataToWrite.length == 0) {
			if (readError) {
				LogToConsoleError("Failed to read data: %{public}@", readError.localizedDescription);
			}

			[self closeWithLocalizedError:@"TDCFileTransferDialog[nab-dx]"];

			return;
		}

		self.currentRecord += dataToWrite.length;

		self.processedFilesize += dataToWrite.length;

		self.sendQueueSize += 1;

		[self.writeSocket writeData:dataToWrite timeout:_sendDataTimeout];
	} while (1);
}

#pragma mark -
#pragma mark Actions

- (void)updateClearButton
{
	[self.transferDialog updateClearButton];
}

- (void)reloadStatusInformation
{
	TDCFileTransferDialogTableCell *transferTableCell = self.transferTableCell;

	if (transferTableCell == nil) {
		return;
	}

	[transferTableCell reloadStatusInformation];
}

#pragma mark -
#pragma mark Properties

- (nullable TDCFileTransferDialogSocket *)writeSocket
{
	if (self.isReversed) {
		return self.connectionToRemoteServer;
	} else {
		return self.listeningServerConnectedClient;
	}
}

- (nullable TDCFileTransferDialogSocket *)readSocket
{
	if (self.isReversed) {
		return self.listeningServerConnectedClient;
	} else {
		return self.connectionToRemoteServer;
	}
}

- (BOOL)isActingAsServer
{
	return ((self.isSender && self.isReversed == NO) || (self.isSender == NO && self.isReversed));
}

- (BOOL)isActingAsClient
{
	return ((self.isSender == NO && self.isReversed == NO) || (self.isSender && self.isReversed));
}

- (TDCFileTransferDialog *)transferDialog
{
	return [TXSharedApplication sharedFileTransferDialog];
}

- (NSArray<NSNumber *> *)speedRecords
{
	_assertMainQueue();

	return [self.speedRecordsPrivate copy];
}

- (nullable NSString *)filePath
{
	NSString *path = self.path;

	NSString *filename = self.filename;

	if (path == nil || filename == nil) {
		return nil;
	}

	return [path stringByAppendingPathComponent:filename];
}

- (nullable NSURL *)fileURL
{
	NSString *filePath = self.filePath;

	if (filePath == nil) {
		return nil;
	}

	return [NSURL fileURLWithPath:filePath];
}

- (uint64_t)currentFilesize
{
	NSString *filePath = self.filePath;

	if (filePath == nil) {
		return 0;
	}

	if ([RZFileManager() fileExistsAtPath:filePath] == NO) {
		return 0;
	}

	NSDictionary *fileAttributes = [RZFileManager() attributesOfItemAtPath:filePath error:NULL];

	return fileAttributes.fileSize;
}

- (void)setTransferStatus:(TDCFileTransferDialogTransferStatus)transferStatus
{
	_assertMainQueue();

	if (self->_transferStatus != transferStatus) {
		self->_transferStatus = transferStatus;

		[self reloadStatusInformation];
	}
}

- (void)resetProperties
{
	if (self.isResume == NO) {
		self.processedFilesize = 0;
	}

	self.currentRecord = 0;

	self.errorMessageDescription = nil;

	self.sendQueueSize = 0;

	[self.speedRecordsPrivate removeAllObjects];
}

@end

NS_ASSUME_NONNULL_END
