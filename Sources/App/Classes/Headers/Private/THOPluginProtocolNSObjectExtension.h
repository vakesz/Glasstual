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

NS_ASSUME_NONNULL_BEGIN

@class IRCClient, IRCChannel, IRCPrefix, IRCMessage;

@interface NSObject (THOPluginProtocolExtension)
- (BOOL)receivedCommand:(NSString *)command
               withText:(nullable NSString *)text
             authoredBy:(IRCPrefix *)textAuthor
            destinedFor:(nullable IRCChannel *)textDestination
               onClient:(IRCClient *)client
             receivedAt:(NSDate *)receivedAt
       referenceMessage:(nullable IRCMessage *)referenceMessage;
@end

NS_ASSUME_NONNULL_END
