/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
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

#import "RCMConnectionManagerProtocol.h"

#import "NSObjectHelperPrivate.h"
#import "TLOLocalization.h"
#import "TPCPreferencesLocal.h"
#import "IRCClient.h"
#import "IRCConnectionConfig.h"
#import "IRCConnectionErrors.h"
#import "IRCConnectionPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCConnection ()
@property(weak, readwrite) IRCClient *client;
@property(nonatomic, strong, nullable) NSXPCConnection *serviceConnection;
@property(nonatomic, strong, nullable) SFCertificateTrustPanel *trustPanel;
@property(nonatomic, assign) BOOL trustPanelDoNotInvokeCompletionBlock;
@property(nonatomic, assign) BOOL connectionInvalidatedVoluntarily;
@property(copy, readwrite) NSString *uniqueIdentifier;
@end

@implementation IRCConnection

#pragma mark -
#pragma mark Initialization

- (instancetype)init
{
	[self doesNotRecognizeSelector:_cmd];

	return nil;
}

- (instancetype)initWithConfig:(IRCConnectionConfig *)config onClient:(IRCClient *)client
{
	NSParameterAssert(config != nil);
	NSParameterAssert(client != nil);

	if ((self = [super init])) {
		self.client = client;

		self.config = config;

		self.uniqueIdentifier = [NSString stringWithUUID];
	}

	return self;
}

- (void)resetState
{
	self.isConnecting = NO;
	self.isConnected = NO;
	self.isConnectedWithClientSideCertificate = NO;
	self.isDisconnecting = NO;
	self.EOFReceived = NO;
	self.isSecured = NO;
	self.isSending = NO;

	self.connectedAddress = nil;

	self.connectionInvalidatedVoluntarily = NO;
}

#pragma mark -
#pragma mark Process Management

- (void)invalidateProcess
{
	if (self.serviceConnection == nil) {
		return;
	}

	LogToConsoleDebug("Invalidating process...");

	[self.serviceConnection invalidate];
}

- (void)warmProcessIfNeeded
{
	if (self.serviceConnection != nil) {
		return;
	}

	LogToConsoleDebug("Warming process...");

	[self warmProcess];
}

- (void)warmProcess
{
	NSXPCConnection *serviceConnection =
		[[NSXPCConnection alloc] initWithServiceName:@"com.vakesz.glasstual.IRCConnectionHost"];

	NSXPCInterface *remoteObjectInterface =
		[NSXPCInterface interfaceWithProtocol:@protocol(RCMConnectionManagerServerProtocol)];

	serviceConnection.remoteObjectInterface = remoteObjectInterface;

	NSXPCInterface *exportedInterface =
		[NSXPCInterface interfaceWithProtocol:@protocol(RCMConnectionManagerClientProtocol)];

	serviceConnection.exportedInterface = exportedInterface;

	serviceConnection.exportedObject = self;

	/* NSXPCConnection retains its handlers for its entire lifetime and we
	 retain the connection, so capturing self strongly here is a cycle. */
	__weak typeof(self) weakSelf = self;

	serviceConnection.interruptionHandler = ^{
		[weakSelf interruptionHandler];

		LogToConsole("Interruption handler called");
	};

	serviceConnection.invalidationHandler = ^{
		[weakSelf invalidationHandler];

		LogToConsole("Invalidation handler called");
	};

	[serviceConnection resume];

	self.serviceConnection = serviceConnection;
}

- (void)interruptionHandler
{
	[self invalidateProcess];
}

- (void)invalidationHandler
{
	XRPerformBlockSynchronouslyOnMainQueue(^{
		self.serviceConnection = nil;

		/* -ircConnectionDidDisconnectWithError: instructs the process to
		 voluntarily invalidate, so if we reach here, then its pretty certain
		 something big happened and we need to let the client know. */
		if ((self.isConnecting || self.isConnected) && self.connectionInvalidatedVoluntarily == NO) {
			NSString *errorMessage = TXTLS(@"IRC[vdy-jk]");

			NSError *error = [NSError errorWithDomain:IRCConnectionErrorDomain
												 code:IRCConnectionErrorCodeOther
											 userInfo:@{NSLocalizedDescriptionKey : errorMessage}];

			[self _ircConnectionDidDisconnectWithError:error];
		}

		[self resetState];
	});
}

- (id<RCMConnectionManagerServerProtocol>)remoteObjectProxy
{
	return [self remoteObjectProxyWithErrorHandler:nil];
}

- (id<RCMConnectionManagerServerProtocol>)remoteObjectProxyWithErrorHandler:(void (^_Nullable)(NSError *error))handler
{
	return [self.serviceConnection remoteObjectProxyWithErrorHandler:^(NSError *error) {
		LogToConsoleError("Error occurred while communicating with service: %{public}@", error.localizedDescription);

		if (handler) {
			handler(error);
		}
	}];
}

#pragma mark -
#pragma mark Open/Close Connection

- (void)open
{
	if (self.isConnecting || self.isConnected || self.isDisconnecting) {
		return;
	}

	[self warmProcessIfNeeded];

	self.isConnecting = YES;

	[[self remoteObjectProxy] openWithConfig:self.config];

	if ([TPCPreferences appNapEnabled] == NO) {
		[[self remoteObjectProxy] disableAppNap];
	}

	[[self remoteObjectProxy] disableSuddenTermination];
}

- (void)close
{
	if (self.isDisconnecting) {
		return;
	}

	if (self.isConnecting || self.isConnected) {
		/* Disconnect caused by calling -close on the service will
		 cause -ircConnectionDidDisconnectWithError: to invoke
		 -invalidateProcess for us, so don't call it on this condition. */
		self.isDisconnecting = YES;

		[[self remoteObjectProxy] close];
	} else {
		[self invalidateProcess];
	}
}

#pragma mark -
#pragma mark Utilities

- (void)enforceFloodControl
{
	if (self.isConnected == NO) {
		return;
	}

	[[self remoteObjectProxy] enforceFloodControl];
}

- (void)openSecuredConnectionCertificateModal
{
	[[self remoteObjectProxy] exportSecureConnectionInformation:^(NSString *_Nullable policyName,
																  tls_protocol_version_t protocolType,
																  tls_ciphersuite_t cipherSuites,
																  NSArray<NSData *> *certificateChain) {
		if (policyName == nil) {
			return;
		}

		SecTrustRef trustRef = [RCMSecureTransport trustFromCertificateChain:certificateChain
															  withPolicyName:policyName];

		if (trustRef == NULL) {
			return;
		}

		NSString *protocolDescription = [RCMSecureTransport descriptionForProtocolType:protocolType];

		NSString *cipherDescription = [RCMSecureTransport descriptionForCipherSuite:cipherSuites];

		if (protocolDescription == nil || cipherDescription == nil) {
			CFRelease(trustRef);

			return;
		}

		NSString *protocolSummary = nil;

		if ([RCMSecureTransport isCipherSuiteDeprecated:cipherSuites] == NO) {
			protocolSummary = TXTLS(@"Prompts[2jq-t5]", protocolDescription, cipherDescription);
		} else {
			protocolSummary = TXTLS(@"Prompts[8ou-pu]", protocolDescription, cipherDescription);
		}

		NSString *defaultButtonTitle = TXTLS(@"Prompts[aqw-q1]");
		NSString *alternateButtonTitle = nil;

		NSString *promptTitleText = TXTLS(@"Prompts[sfx-xx]", policyName);
		NSString *promptInformativeText = nil;

		if (protocolSummary == nil) {
			promptInformativeText = TXTLS(@"Prompts[ihy-mz]", policyName);
		} else {
			promptInformativeText = TXTLS(@"Prompts[iun-45]", policyName, protocolSummary);
		}

		__block NSWindow *window = nil;

		XRPerformBlockSynchronouslyOnMainQueue(^{
			window = [NSApp keyWindow];
		});

		(void)[RCMTrustPanel presentTrustPanelInWindow:window
												  body:promptInformativeText
												 title:promptTitleText
										 defaultButton:defaultButtonTitle
									   alternateButton:alternateButtonTitle
											  trustRef:trustRef
									   completionBlock:^(SecTrustRef trustRef, BOOL trusted, id contextInfo){
										   /* RCMTrustPanel consumes the +1 reference returned by
											+trustFromCertificateChain:withPolicyName: and releases
											it after this block returns. Do not release it here. */
									   }];
	}];
}

- (void)openInsecureCertificateTrustPanel:(RCMTrustResponse)trustBlock
{
	if (self.trustPanel != nil) {
		return;
	}

	[[self remoteObjectProxy] exportSecureConnectionInformation:^(NSString *_Nullable policyName,
																  tls_protocol_version_t protocolType,
																  tls_ciphersuite_t cipherSuites,
																  NSArray<NSData *> *certificateChain) {
		if (policyName == nil) {
			return;
		}

		SecTrustRef trustRef = [RCMSecureTransport trustFromCertificateChain:certificateChain
															  withPolicyName:policyName];

		if (trustRef == NULL) {
			return;
		}

		NSString *defaultButtonTitle = TXTLS(@"Prompts[zjw-bd]");
		NSString *alternateButtonTitle = TXTLS(@"Prompts[qso-2g]");

		NSString *promptTitleText = TXTLS(@"Prompts[m8b-58]", policyName);
		NSString *promptInformativeText = TXTLS(@"Prompts[85z-qw]", policyName);

		__weak typeof(self) weakSelf = self;

		self.trustPanel =
			[RCMTrustPanel presentTrustPanelInWindow:nil
												body:promptInformativeText
											   title:promptTitleText
									   defaultButton:defaultButtonTitle
									 alternateButton:alternateButtonTitle
											trustRef:trustRef
									 completionBlock:^(SecTrustRef trustRef, BOOL trusted, id contextInfo) {
										 /* RCMTrustPanel consumes the +1 trustRef and releases it after
										  this block returns. Do not release it here. */

										 weakSelf.trustPanel = nil;

										 if (weakSelf.trustPanelDoNotInvokeCompletionBlock) {
											 weakSelf.trustPanelDoNotInvokeCompletionBlock = NO;

											 return;
										 }

										 ((RCMTrustResponse)contextInfo)(trusted);
									 }
										 contextInfo:trustBlock];
	}];
}

- (void)closeInsecureCertificateTrustPanel
{
	if (self.trustPanel == nil) {
		return;
	}

	SFCertificateTrustPanel *trustPanel = self.trustPanel;

	/* Ending the sheet (or modal session) causes the panel to invoke the
	 did-end selector RCMTrustPanel registered, which in turn invokes our
	 completion block. The flag tells that block to swallow the response. */
	self.trustPanelDoNotInvokeCompletionBlock = YES;

	NSWindow *sheetParent = trustPanel.sheetParent;

	if (sheetParent) {
		[sheetParent endSheet:trustPanel returnCode:NSModalResponseCancel];

		return;
	}

	if ([NSApp modalWindow] == trustPanel) {
		[NSApp stopModalWithCode:NSModalResponseCancel];

		return;
	}

	/* The panel is neither a sheet nor modal so there is no did-end
	 callback to wait for. Hide it and drop our state by hand. */
	[trustPanel orderOut:nil];

	self.trustPanelDoNotInvokeCompletionBlock = NO;

	self.trustPanel = nil;
}

#pragma mark -
#pragma mark Encode Data

- (nullable NSString *)convertFromCommonEncoding:(NSData *)data
{
	return [self.client convertFromCommonEncoding:data];
}

- (nullable NSData *)convertToCommonEncoding:(NSString *)data
{
	return [self.client convertToCommonEncoding:data];
}

#pragma mark -
#pragma mark Send Data

- (void)sendLine:(NSString *)line
{
	NSParameterAssert(line != nil);

	/* IRC is line oriented. Any CR or LF inside the line would be read by
	 the server as the start of a second, unintended command. */
	line = [line stringByReplacingOccurrencesOfString:@"\x0d" withString:@""];
	line = [line stringByReplacingOccurrencesOfString:@"\x0a" withString:@""];

	line = [line stringByAppendingString:@"\x0d\x0a"];

	NSData *dataToSend = [self convertToCommonEncoding:line];

	if (dataToSend == nil) {
		return;
	}

	self.isSending = YES;

	/* PONG replies are extremely important. There is no reason they should be
	 placed in the flood control queue. This writes them directly to the socket
	 instead of actually waiting for the queue. We only need this check if
	 we actually have flood control enabled. */
	if ([line hasPrefix:@"PONG"]) {
		[[self remoteObjectProxy] sendData:dataToSend bypassQueue:YES];

		return;
	}

	[[self remoteObjectProxy] sendData:dataToSend];
}

- (void)clearSendQueue
{
	[[self remoteObjectProxy] clearSendQueue];
}

#pragma mark -
#pragma mark Socket Delegate

- (void)ircConnectionWillConnectToProxy:(NSString *)proxyHost port:(uint16_t)proxyPort
{
	XRPerformBlockSynchronouslyOnMainQueue(^{
		[self.client ircConnection:self willConnectToProxy:proxyHost port:proxyPort];
	});
}

/* Delegate methods below arrive on the XPC connection's queue. State is
 mutated inside the main queue hop so that IRCClient, which reads these
 properties from the main thread, never observes a half-updated object. */

- (void)ircConnectionDidConnectToHost:(nullable NSString *)host
{
	XRPerformBlockSynchronouslyOnMainQueue(^{
		self.connectedAddress = host;

		self.isConnecting = NO;
		self.isConnected = YES;

		[self.client ircConnectionDidConnect:self];
	});
}

- (void)ircConnectionDidSecureConnectionWithProtocolType:(tls_protocol_version_t)protocolType
											 cipherSuite:(tls_ciphersuite_t)cipherSuite
{
	XRPerformBlockSynchronouslyOnMainQueue(^{
		self.isSecured = YES;

		if (self.config.identityClientSideCertificate != nil) {
			self.isConnectedWithClientSideCertificate = YES;
		}

		[self.client ircConnectionDidSecureConnection:self withProtocolType:protocolType cipherSuite:cipherSuite];
	});
}

- (void)ircConnectionDidCloseReadStream
{
	XRPerformBlockSynchronouslyOnMainQueue(^{
		self.EOFReceived = YES;

		[self.client ircConnectionDidCloseReadStream:self];
	});
}

- (void)ircConnectionDidDisconnectWithError:(nullable NSError *)disconnectError
{
	XRPerformBlockSynchronouslyOnMainQueue(^{
		self.connectionInvalidatedVoluntarily = YES;

		[self invalidateProcess];

		[self _ircConnectionDidDisconnectWithError:disconnectError];
	});
}

- (void)_ircConnectionDidDisconnectWithError:(nullable NSError *)disconnectError
{
	XRPerformBlockSynchronouslyOnMainQueue(^{
		[self closeInsecureCertificateTrustPanel];

		[self.client ircConnection:self didDisconnectWithError:disconnectError];
	});
}

- (void)ircConnectionDidReceiveData:(NSData *)data
{
	/* IRCClient performs call to main thread later in stack. */
	NSString *dataString = [self convertFromCommonEncoding:data];

	if (dataString == nil) {
		return;
	}

	[self.client ircConnection:self didReceiveData:dataString];
}

- (void)ircConnectionRequestInsecureCertificateTrust:(RCMTrustResponse)trustBlock
{
	XRPerformBlockSynchronouslyOnMainQueue(^{
		[self openInsecureCertificateTrustPanel:trustBlock];
	});
}

- (void)ircConnectionWillSendData:(NSData *)data
{
	XRPerformBlockSynchronouslyOnMainQueue(^{
		NSString *dataString = [self convertFromCommonEncoding:data];

		if (dataString == nil) {
			return;
		}

		[self.client ircConnection:self willSendData:dataString];
	});
}

- (void)ircConnectionDidSendData
{
	XRPerformBlockSynchronouslyOnMainQueue(^{
		self.isSending = NO;
	});
}

@end

NS_ASSUME_NONNULL_END
