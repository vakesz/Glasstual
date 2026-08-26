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

#import <XCTest/XCTest.h>

#import "GLTTestClient.h"
#import "IRCChannelPrivate.h"
#import "IRCMessage.h"
#import "IRCTreeItemPrivate.h"
#import "TVCLogLine.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRCClientNegotiationTests : XCTestCase
@end

@implementation IRCClientNegotiationTests

- (IRCMessage *)message:(NSString *)line onClient:(IRCClient *)client
{
	IRCMessage *message = [[IRCMessage alloc] initWithLine:line onClient:client];

	XCTAssertNotNil(message, @"Failed to parse: %@", line);

	return message;
}

#pragma mark -
#pragma mark CAP

- (void)testCapabilityListContinuationDefersRequests
{
	GLTTestClient *client = [GLTTestClient testClient];

	[client receiveCapabilityOrAuthenticationRequest:
				[self message:@":irc.example.net CAP * LS * :multi-prefix sasl=PLAIN,EXTERNAL" onClient:client]];

	XCTAssertEqual(client.sentCapabilityCommands.count, 0, @"Nothing may be requested before the list is complete");
	XCTAssertEqual(client.pendingCapabilityRequests.count, 0);

	[client receiveCapabilityOrAuthenticationRequest:
				[self message:@":irc.example.net CAP * LS :server-time message-tags example.com/vendor"
					 onClient:client]];

	/* Registry order: message-tags before multi-prefix before server-time.
	 sasl is offered but there is no password, so it is not requested. */
	XCTAssertEqualObjects(client.sentCapabilityCommands, @[ @"REQ message-tags" ]);
	XCTAssertEqualObjects(client.pendingCapabilityRequests, (@[ @"multi-prefix", @"server-time" ]));
}

- (void)testAcknowledgementEnablesCapabilityAndContinuesNegotiation
{
	GLTTestClient *client = [GLTTestClient testClient];

	[client
		receiveCapabilityOrAuthenticationRequest:[self message:@":irc.example.net CAP * LS :multi-prefix server-time"
													  onClient:client]];

	XCTAssertEqualObjects(client.sentCapabilityCommands, @[ @"REQ multi-prefix" ]);

	[client receiveCapabilityOrAuthenticationRequest:[self message:@":irc.example.net CAP me ACK :multi-prefix"
														  onClient:client]];

	XCTAssertTrue([client isCapabilityEnabled:ClientIRCv3SupportedCapabilityMultiPrefix]);
	XCTAssertFalse([client isCapabilityEnabled:ClientIRCv3SupportedCapabilityServerTime]);
	XCTAssertEqualObjects(client.sentCapabilityCommands, (@[ @"REQ multi-prefix", @"REQ server-time" ]));

	[client receiveCapabilityOrAuthenticationRequest:[self message:@":irc.example.net CAP me NAK :server-time"
														  onClient:client]];

	XCTAssertFalse([client isCapabilityEnabled:ClientIRCv3SupportedCapabilityServerTime]);

	/* Registration is not complete, so negotiation ends with CAP END. */
	XCTAssertEqualObjects(client.sentCapabilityCommands.lastObject, @"END");

	XCTAssertEqualObjects(client.enabledCapabilitiesStringValue, @"multi-prefix");
}

- (void)testVendorServerTimeEnablesGenericBit
{
	GLTTestClient *client = [GLTTestClient testClient];

	[client receiveCapabilityOrAuthenticationRequest:[self message:@":irc.example.net CAP * LS :znc.in/server-time-iso"
														  onClient:client]];
	[client
		receiveCapabilityOrAuthenticationRequest:[self message:@":irc.example.net CAP me ACK :znc.in/server-time-iso"
													  onClient:client]];

	XCTAssertTrue([client isCapabilityEnabled:ClientIRCv3SupportedCapabilityServerTime]);

	[client
		receiveCapabilityOrAuthenticationRequest:[self message:@":irc.example.net CAP me DEL :znc.in/server-time-iso"
													  onClient:client]];

	XCTAssertFalse([client isCapabilityEnabled:ClientIRCv3SupportedCapabilityServerTime]);
}

- (void)testSASLIsRequestedWhenPasswordIsConfigured
{
	GLTTestClient *client = [GLTTestClient testClientWithConfigDictionary:@{@"nickname" : @"me", @"username" : @"me"}
														 nicknamePassword:@"secret"];

	[client receiveCapabilityOrAuthenticationRequest:[self message:@":irc.example.net CAP * LS :sasl=PLAIN,EXTERNAL"
														  onClient:client]];

	XCTAssertEqualObjects(client.sentCapabilityCommands, @[ @"REQ sasl" ]);

	[client receiveCapabilityOrAuthenticationRequest:[self message:@":irc.example.net CAP me ACK :sasl"
														  onClient:client]];

	XCTAssertTrue([client isCapabilityEnabled:ClientIRCv3SupportedCapabilityIsInSASLNegotiation]);

	/* Negotiation pauses while SASL runs: no CAP END yet. */
	XCTAssertEqualObjects(client.sentCapabilityCommands, @[ @"REQ sasl" ]);
}

- (void)testSASLIsSkippedWhenOnlyUnsupportedMechanismsAreOffered
{
	GLTTestClient *client = [GLTTestClient testClientWithConfigDictionary:@{} nicknamePassword:@"secret"];

	/* SCRAM-SHA-512 and GSSAPI are not implemented by this client. */
	[client
		receiveCapabilityOrAuthenticationRequest:[self message:@":irc.example.net CAP * LS :sasl=SCRAM-SHA-512,GSSAPI"
													  onClient:client]];

	XCTAssertEqualObjects(client.sentCapabilityCommands, @[ @"END" ]);
}

- (void)testSCRAMIsPreferredOverPlain
{
	GLTTestClient *client = [GLTTestClient testClientWithConfigDictionary:@{@"nickname" : @"me"}
														 nicknamePassword:@"secret"];

	XCTAssertTrue(([client selectSASLMechanismFromOffered:@[ @"PLAIN", @"SCRAM-SHA-256" ]]));
	XCTAssertEqualObjects(client.saslMechanism, @"SCRAM-SHA-256");
}

- (void)testPlainIsChosenWhenSCRAMIsNotOffered
{
	GLTTestClient *client = [GLTTestClient testClientWithConfigDictionary:@{@"nickname" : @"me"}
														 nicknamePassword:@"secret"];

	XCTAssertTrue([client selectSASLMechanismFromOffered:@[ @"PLAIN" ]]);
	XCTAssertEqualObjects(client.saslMechanism, @"PLAIN");
}

- (void)testSASLMechsRetryMovesToNextMechanism
{
	GLTTestClient *client = [GLTTestClient testClientWithConfigDictionary:@{@"nickname" : @"me"}
														 nicknamePassword:@"secret"];

	[client selectSASLMechanismFromOffered:@[ @"PLAIN", @"SCRAM-SHA-256" ]];

	XCTAssertEqualObjects(client.saslMechanism, @"SCRAM-SHA-256");

	/* 908 refused SCRAM and named PLAIN. */
	XCTAssertTrue([client retrySASLNegotiationWithMechanisms:@[ @"PLAIN" ]]);
	XCTAssertEqualObjects(client.saslMechanism, @"PLAIN");
	XCTAssertTrue([client.saslTriedMechanisms containsObject:@"SCRAM-SHA-256"]);

	/* Nothing left to try. */
	XCTAssertFalse([client retrySASLNegotiationWithMechanisms:@[ @"PLAIN" ]]);
}

#pragma mark -
#pragma mark BATCH

- (void)testNestedBatchesAreReplayedInOrder
{
	GLTTestClient *client = [GLTTestClient testClient];

	[client enableCapability:ClientIRCv3SupportedCapabilityBatch];

	NSArray<NSString *> *lines = @[
		@":irc.example.net BATCH +outer example.com/outer",
		@"@batch=outer :irc.example.net BATCH +inner example.com/inner",
		@"@batch=inner :a!u@h PRIVMSG #c :one",
		@"@batch=outer :b!u@h PRIVMSG #c :two",
		@"@batch=inner :c!u@h PRIVMSG #c :three",
		@":irc.example.net BATCH -inner",
		@"@batch=outer :d!u@h PRIVMSG #c :four",
		@":irc.example.net BATCH -outer",
	];

	for (NSString *line in lines) {
		IRCMessage *message = [self message:line onClient:client];

		if ([client filterBatchCommandIncomingData:message]) {
			continue;
		}

		if ([message.command isEqualToString:@"BATCH"]) {
			[client receiveBatch:message];
		} else {
			[client processIncomingMessage:message];
		}
	}

	NSArray<NSString *> *bodies = [client.processedMessages valueForKeyPath:@"sequence"];

	XCTAssertEqualObjects(bodies, (@[ @"one", @"two", @"three", @"four" ]));
}

- (void)testMessagesOutsideAnOpenBatchAreNotQueued
{
	GLTTestClient *client = [GLTTestClient testClient];

	[client enableCapability:ClientIRCv3SupportedCapabilityBatch];

	IRCMessage *message = [self message:@"@batch=unknown :a!u@h PRIVMSG #c :hi" onClient:client];

	XCTAssertFalse([client filterBatchCommandIncomingData:message]);
}

#pragma mark -
#pragma mark Standard replies

- (void)testStandardRepliesArePrintedToConsoleOrChannel
{
	GLTTestClient *client = [GLTTestClient testClient];

	[client receiveStandardReply:
				[self message:@":irc.example.net FAIL BOX BOXES_INVALID STACK CLOCKWISE :Given boxes are not supported"
					 onClient:client]];

	XCTAssertEqual(client.printedLines.count, 1);
	XCTAssertEqualObjects(client.printedLines[0][@"messageBody"],
						  @"FAIL BOX/BOXES_INVALID: Given boxes are not supported");
	XCTAssertEqual([client.printedLines[0][@"lineType"] unsignedIntegerValue], TVCLogLineTypeDebug);
	XCTAssertNil(client.printedLines[0][@"channel"]);

	[client receiveStandardReply:[self message:@":irc.example.net NOTE * OPER_MESSAGE :The message" onClient:client]];

	XCTAssertEqualObjects(client.printedLines[1][@"messageBody"], @"NOTE */OPER_MESSAGE: The message");
	XCTAssertEqual([client.printedLines[1][@"lineType"] unsignedIntegerValue], TVCLogLineTypeNotice);

	/* A channel the client is in receives the reply. */
	IRCChannel *channel = [[IRCChannel alloc] initWithConfigDictionary:@{@"channelName" : @"#chat"}];

	channel.associatedClient = client;

	[client addChannel:channel];

	[client
		receiveStandardReply:[self message:@":irc.example.net WARN REHASH CERTS_EXPIRED #chat :Certificate has expired"
								  onClient:client]];

	XCTAssertEqualObjects(client.printedLines[2][@"messageBody"],
						  @"WARN REHASH/CERTS_EXPIRED: Certificate has expired");
	XCTAssertEqual([client.printedLines[2][@"lineType"] unsignedIntegerValue], TVCLogLineTypeNotice);
	XCTAssertEqual(client.printedLines[2][@"channel"], channel);

	/* Unknown channel names fall back to the console. */
	[client
		receiveStandardReply:[self message:@":irc.example.net WARN REHASH CERTS_EXPIRED #other :Certificate has expired"
								  onClient:client]];

	XCTAssertNil(client.printedLines[3][@"channel"]);
}

#pragma mark -
#pragma mark Message tags

- (void)testTagMessageIsOnlySentWithMessageTagsEnabled
{
	GLTTestClient *client = [GLTTestClient testClient];

	NSDictionary *typing = @{@"+typing" : @"active"};

	XCTAssertFalse([client sendTagMessage:typing toTarget:@"#c"]);
	XCTAssertEqual(client.sentLines.count, 0);

	[client enableCapability:ClientIRCv3SupportedCapabilityMessageTags];

	XCTAssertTrue([client sendTagMessage:typing toTarget:@"#c"]);
	XCTAssertEqualObjects(client.sentLines, @[ @"@+typing=active TAGMSG #c" ]);

	NSDictionary *empty = @{};

	XCTAssertFalse([client sendTagMessage:empty toTarget:@"#c"]);
}

- (void)testTagsAreDroppedFromCommandsWithoutMessageTags
{
	GLTTestClient *client = [GLTTestClient testClient];

	[client sendCommand:@"PRIVMSG" arguments:@[ @"#c", @"hello" ] tags:@{@"+draft/reply" : @"abc"}];

	XCTAssertEqualObjects(client.sentLines, @[ @"PRIVMSG #c :hello" ]);

	[client enableCapability:ClientIRCv3SupportedCapabilityMessageTags];

	[client sendCommand:@"PRIVMSG" arguments:@[ @"#c", @"hello" ] tags:@{@"+draft/reply" : @"abc"}];

	XCTAssertEqualObjects(client.sentLines.lastObject, @"@+draft/reply=abc PRIVMSG #c :hello");
}

- (void)testReceivedTagMessageWithoutClientTagsIsIgnored
{
	GLTTestClient *client = [GLTTestClient testClient];

	/* No view controller is attached; the handler must cope and not print. */
	[client receiveTagMessage:[self message:@"@msgid=1 :a!u@h TAGMSG #c" onClient:client]];
	[client receiveTagMessage:[self message:@"@+typing=active;msgid=2 :a!u@h TAGMSG #c" onClient:client]];

	XCTAssertEqual(client.printedLines.count, 0);
}

@end

NS_ASSUME_NONNULL_END
