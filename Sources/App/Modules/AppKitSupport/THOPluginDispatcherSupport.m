/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

#import "IRCClient.h"
#import "IRCMessage.h"
#import "THOPluginProtocolPrivate.h"
#import "THOPluginProtocolNSObjectExtension.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const THOPluginProtocolCompatibilityMinimumVersion = @"7.2.4";

@implementation IRCMessage (IRCMessagePluginExtension)

- (THOPluginDidReceiveServerInputConcreteObject *)didReceiveServerInputConcreteObject
{
	THOPluginDidReceiveServerInputConcreteObject *messageObject = [THOPluginDidReceiveServerInputConcreteObject new];

	messageObject.senderIsServer = self.senderIsServer;

	messageObject.senderNickname = self.senderNickname;
	messageObject.senderUsername = self.senderUsername;
	messageObject.senderAddress = self.senderAddress;
	messageObject.senderHostmask = self.senderHostmask;

	messageObject.receivedAt = self.receivedAt;

	messageObject.messageParameters = self.params;
	messageObject.messageParamaters = self.params;
	messageObject.messageSequence = self.sequence;

	messageObject.messageCommand = self.command;
	messageObject.messageCommandNumeric = self.commandNumeric;

	return messageObject;
}

@end

@implementation THOPluginDidPostNewMessageConcreteObject
@end

@implementation THOPluginDidReceiveServerInputConcreteObject
@end

@implementation THOPluginWebViewJavaScriptPayloadConcreteObject
@end

@implementation THOPluginOutputSuppressionRule
@end

NS_ASSUME_NONNULL_END
