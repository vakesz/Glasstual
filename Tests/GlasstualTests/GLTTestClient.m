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

#import "GLTTestClient.h"

NS_ASSUME_NONNULL_BEGIN

@implementation GLTTestClientConfig

- (nullable NSString *)nicknamePassword
{
	return self.testNicknamePassword;
}

- (void)writeNicknamePasswordToKeychain
{
}

- (void)writeProxyPasswordToKeychain
{
}

@end

#pragma mark -

@implementation GLTTestClient

+ (instancetype)testClient
{
	return [self testClientWithConfigDictionary:@{}];
}

+ (instancetype)testClientWithConfigDictionary:(NSDictionary<NSString *, id> *)dictionary
{
	return [self testClientWithConfigDictionary:dictionary nicknamePassword:nil];
}

+ (instancetype)testClientWithConfigDictionary:(NSDictionary<NSString *, id> *)dictionary
							  nicknamePassword:(nullable NSString *)nicknamePassword
{
	GLTTestClientConfig *config = [[GLTTestClientConfig alloc] initWithDictionary:dictionary];

	config.testNicknamePassword = nicknamePassword;

	GLTTestClient *client = [[self alloc] initWithConfig:config];

	client->_sentCapabilityCommands = [NSMutableArray array];
	client->_sentLines = [NSMutableArray array];
	client->_processedMessages = [NSMutableArray array];
	client->_printedLines = [NSMutableArray array];

	return client;
}

- (void)markAsLoggedIn
{
	[self setValue:@YES forKey:@"isLoggedIn"];
}

- (void)sendCapability:(NSString *)subcommand data:(nullable NSString *)data
{
	if (data) {
		[self.sentCapabilityCommands addObject:[NSString stringWithFormat:@"%@ %@", subcommand, data]];
	} else {
		[self.sentCapabilityCommands addObject:subcommand];
	}
}

- (void)sendLine:(NSString *)string
{
	[self.sentLines addObject:string];
}

- (void)processIncomingMessage:(IRCMessage *)message
{
	[self.processedMessages addObject:message];

	if (self.forwardsProcessedMessages) {
		[super processIncomingMessage:message];
	}
}

- (void)print:(NSString *)messageBody
				  by:(nullable NSString *)nickname
		   inChannel:(nullable IRCChannel *)channel
			  asType:(TVCLogLineType)lineType
			 command:(nullable NSString *)command
		  receivedAt:(NSDate *)receivedAt
		 isEncrypted:(BOOL)isEncrypted
	   escapeMessage:(BOOL)escapeMessage
	referenceMessage:(nullable IRCMessage *)referenceMessage
	 completionBlock:(nullable TVCLogControllerPrintOperationCompletionBlock)postPrintBlock
{
	NSMutableDictionary<NSString *, id> *line = [NSMutableDictionary dictionary];

	line[@"messageBody"] = messageBody;
	line[@"lineType"] = @(lineType);
	line[@"command"] = command;
	line[@"channel"] = channel;
	line[@"nickname"] = nickname;

	[self.printedLines addObject:line];
}

@end

NS_ASSUME_NONNULL_END
