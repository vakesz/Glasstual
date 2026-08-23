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

#import "IRCClient.h"
#import "IRCChannel.h"
#import "IRCTypingTrackerPrivate.h"

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const IRCTypingTrackerDidChangeNotification = @"IRCTypingTrackerDidChangeNotification";
NSString *const IRCTypingTrackerChannelKey = @"channel";

#define _activeTimeout 6.0
#define _pausedTimeout 30.0

@interface IRCTypingEntry : NSObject
@property(nonatomic, copy) NSString *nickname;
@property(nonatomic, assign) IRCTypingState state;
@property(nonatomic, copy) NSDate *updatedAt;
@property(nonatomic, copy) NSDate *startedAt;
@property(nonatomic, assign) NSUInteger sequence; // Order of first appearance
@end

@implementation IRCTypingEntry

- (NSDate *)expiresAt
{
	if (self.state == IRCTypingStateActive) {
		return [self.updatedAt dateByAddingTimeInterval:_activeTimeout];
	}

	return [self.updatedAt dateByAddingTimeInterval:_pausedTimeout];
}

@end

#pragma mark -

@interface IRCTypingTracker ()
@property(nonatomic, weak) IRCClient *client;
/* Channel unique identifier -> nickname (lowercase) -> entry */
@property(nonatomic, strong)
	NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, IRCTypingEntry *> *> *entries;
@property(nonatomic, strong) NSMapTable<NSString *, IRCChannel *> *channels;
@property(nonatomic, strong, nullable) NSTimer *expiryTimer;
@property(nonatomic, assign) NSUInteger sequence;
@end

@implementation IRCTypingTracker

- (instancetype)initWithClient:(IRCClient *)client
{
	NSParameterAssert(client != nil);

	if ((self = [super init])) {
		self.client = client;

		self.entries = [NSMutableDictionary dictionary];

		self.channels = [NSMapTable strongToWeakObjectsMapTable];
	}

	return self;
}

- (void)dealloc
{
	[self.expiryTimer invalidate];
}

+ (IRCTypingState)stateForTagValue:(nullable NSString *)value
{
	if ([value isEqualToString:@"active"]) {
		return IRCTypingStateActive;
	} else if ([value isEqualToString:@"paused"]) {
		return IRCTypingStatePaused;
	}

	return IRCTypingStateDone;
}

#pragma mark -
#pragma mark Updates

- (void)noteTypingState:(IRCTypingState)state fromNickname:(NSString *)nickname inChannel:(IRCChannel *)channel
{
	[self noteTypingState:state fromNickname:nickname inChannel:channel atDate:[NSDate date]];
}

- (void)noteTypingState:(IRCTypingState)state
		   fromNickname:(NSString *)nickname
			  inChannel:(IRCChannel *)channel
				 atDate:(NSDate *)date
{
	NSParameterAssert(nickname != nil);
	NSParameterAssert(channel != nil);
	NSParameterAssert(date != nil);

	if (nickname.length == 0) {
		return;
	}

	NSString *channelKey = channel.uniqueIdentifier;
	NSString *nicknameKey = nickname.lowercaseString;

	NSMutableDictionary<NSString *, IRCTypingEntry *> *channelEntries = self.entries[channelKey];

	IRCTypingEntry *entry = channelEntries[nicknameKey];

	BOOL changed = NO;

	if (state == IRCTypingStateDone) {
		if (entry) {
			[channelEntries removeObjectForKey:nicknameKey];

			changed = YES;
		}
	} else {
		if (channelEntries == nil) {
			channelEntries = [NSMutableDictionary dictionary];

			self.entries[channelKey] = channelEntries;

			[self.channels setObject:channel forKey:channelKey];
		}

		if (entry == nil) {
			entry = [IRCTypingEntry new];

			entry.nickname = nickname;
			entry.startedAt = date;
			entry.sequence = (self.sequence += 1);

			channelEntries[nicknameKey] = entry;

			changed = YES;
		} else if (entry.state != state) {
			changed = YES;
		}

		entry.state = state;
		entry.updatedAt = date;
	}

	if (channelEntries.count == 0) {
		[self.entries removeObjectForKey:channelKey];

		[self.channels removeObjectForKey:channelKey];
	}

	[self scheduleExpiry];

	if (changed) {
		[self postChangeForChannel:channel];
	}
}

- (void)removeNickname:(NSString *)nickname
{
	NSParameterAssert(nickname != nil);

	NSString *nicknameKey = nickname.lowercaseString;

	for (NSString *channelKey in self.entries.allKeys) {
		NSMutableDictionary *channelEntries = self.entries[channelKey];

		if (channelEntries[nicknameKey] == nil) {
			continue;
		}

		[channelEntries removeObjectForKey:nicknameKey];

		IRCChannel *channel = [self.channels objectForKey:channelKey];

		if (channelEntries.count == 0) {
			[self.entries removeObjectForKey:channelKey];

			[self.channels removeObjectForKey:channelKey];
		}

		if (channel) {
			[self postChangeForChannel:channel];
		}
	}
}

- (void)removeAllInChannel:(IRCChannel *)channel
{
	NSParameterAssert(channel != nil);

	NSString *channelKey = channel.uniqueIdentifier;

	if (self.entries[channelKey] == nil) {
		return;
	}

	[self.entries removeObjectForKey:channelKey];

	[self.channels removeObjectForKey:channelKey];

	[self postChangeForChannel:channel];
}

- (void)removeAll
{
	NSArray<NSString *> *channelKeys = self.entries.allKeys;

	[self.entries removeAllObjects];

	for (NSString *channelKey in channelKeys) {
		IRCChannel *channel = [self.channels objectForKey:channelKey];

		if (channel) {
			[self postChangeForChannel:channel];
		}
	}

	[self.channels removeAllObjects];

	[self.expiryTimer invalidate];

	self.expiryTimer = nil;
}

#pragma mark -
#pragma mark Queries

- (NSArray<NSString *> *)typingNicknamesInChannel:(IRCChannel *)channel
{
	return [self typingNicknamesInChannel:channel atDate:[NSDate date]];
}

- (NSArray<NSString *> *)typingNicknamesInChannel:(IRCChannel *)channel atDate:(NSDate *)date
{
	NSParameterAssert(channel != nil);

	NSDictionary<NSString *, IRCTypingEntry *> *channelEntries = self.entries[channel.uniqueIdentifier];

	if (channelEntries.count == 0) {
		return @[];
	}

	NSMutableArray<IRCTypingEntry *> *live = [NSMutableArray array];

	for (IRCTypingEntry *entry in channelEntries.allValues) {
		if ([entry.expiresAt compare:date] == NSOrderedAscending) {
			continue;
		}

		[live addObject:entry];
	}

	[live sortUsingComparator:^NSComparisonResult(IRCTypingEntry *entry1, IRCTypingEntry *entry2) {
		if (entry1.sequence < entry2.sequence) {
			return NSOrderedAscending;
		} else if (entry1.sequence > entry2.sequence) {
			return NSOrderedDescending;
		}

		return NSOrderedSame;
	}];

	NSMutableArray<NSString *> *nicknames = [NSMutableArray arrayWithCapacity:live.count];

	for (IRCTypingEntry *entry in live) {
		[nicknames addObject:entry.nickname];
	}

	return [nicknames copy];
}

#pragma mark -
#pragma mark Expiry

- (void)scheduleExpiry
{
	if (self.entries.count == 0) {
		[self.expiryTimer invalidate];

		self.expiryTimer = nil;

		return;
	}

	if (self.expiryTimer != nil) {
		return;
	}

	__weak IRCTypingTracker *weakSelf = self;

	self.expiryTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
													   repeats:YES
														 block:^(NSTimer *timer) {
															 [weakSelf expireEntriesAtDate:[NSDate date]];
														 }];

	self.expiryTimer.tolerance = 0.2;
}

- (void)expireEntriesAtDate:(NSDate *)date
{
	NSParameterAssert(date != nil);

	for (NSString *channelKey in self.entries.allKeys) {
		NSMutableDictionary<NSString *, IRCTypingEntry *> *channelEntries = self.entries[channelKey];

		BOOL changed = NO;

		for (NSString *nicknameKey in channelEntries.allKeys) {
			IRCTypingEntry *entry = channelEntries[nicknameKey];

			if ([entry.expiresAt compare:date] == NSOrderedAscending) {
				[channelEntries removeObjectForKey:nicknameKey];

				changed = YES;
			}
		}

		IRCChannel *channel = [self.channels objectForKey:channelKey];

		if (channelEntries.count == 0) {
			[self.entries removeObjectForKey:channelKey];

			[self.channels removeObjectForKey:channelKey];
		}

		if (changed && channel) {
			[self postChangeForChannel:channel];
		}
	}

	[self scheduleExpiry];
}

- (void)postChangeForChannel:(IRCChannel *)channel
{
	IRCClient *client = self.client;

	if (client == nil) {
		return;
	}

	[RZNotificationCenter() postNotificationName:IRCTypingTrackerDidChangeNotification
										  object:client
										userInfo:@{IRCTypingTrackerChannelKey : channel}];
}

@end

NS_ASSUME_NONNULL_END
