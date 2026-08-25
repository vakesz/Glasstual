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

/* IRCMessage plugin helper is implemented in Swift (Message). */

@implementation THOPluginDidPostNewMessageConcreteObject
@end

@implementation THOPluginDidReceiveServerInputConcreteObject
@end

@implementation THOPluginWebViewJavaScriptPayloadConcreteObject
@end

@implementation THOPluginOutputSuppressionRule
@end

NS_ASSUME_NONNULL_END
