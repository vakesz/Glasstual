/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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

@class IRCClient, IRCChannel;

/* Posted on the main queue when the set of people typing in a channel
 changes. The object is the IRCClient; the channel is in the user info
 under IRCTypingTrackerChannelKey. */
static NSNotificationName const IRCTypingTrackerDidChangeNotification =
    @"IRCTypingTrackerDidChangeNotification";
static NSString *const IRCTypingTrackerChannelKey = @"channel";

typedef NS_ENUM(NSUInteger, IRCTypingState) {
  IRCTypingStateDone = 0,
  IRCTypingStateActive,
  IRCTypingStatePaused,
};

/* Who is typing where (IRCv3 "+typing" client tag). An active entry
 expires after six seconds, a paused one after thirty; "done" removes
 the entry at once. The local user is never tracked. */
@interface IRCTypingTracker : NSObject
- (instancetype)initWithClient:(IRCClient *)client NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

+ (IRCTypingState)stateForTagValue:
    (nullable NSString *)value; // "active", "paused", anything else = done

- (void)noteTypingState:(IRCTypingState)state
           fromNickname:(NSString *)nickname
              inChannel:(IRCChannel *)channel;
- (void)noteTypingState:(IRCTypingState)state
           fromNickname:(NSString *)nickname
              inChannel:(IRCChannel *)channel
                 atDate:(NSDate *)date;

/* Nicknames still considered typing, in the order they started. */
- (NSArray<NSString *> *)typingNicknamesInChannel:(IRCChannel *)channel;
- (NSArray<NSString *> *)typingNicknamesInChannel:(IRCChannel *)channel
                                           atDate:(NSDate *)date;

- (void)removeNickname:(NSString *)nickname;
- (void)removeAllInChannel:(IRCChannel *)channel;
- (void)removeAll;

/* Drops expired entries and posts the notification for every channel
 that changed. Runs on a timer while there is anything to expire. */
- (void)expireEntriesAtDate:(NSDate *)date;
@end

NS_ASSUME_NONNULL_END
