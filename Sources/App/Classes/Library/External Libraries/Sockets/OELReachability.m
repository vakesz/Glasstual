/*
 Copyright (c) 2011, Tony Million.
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 */

#import <Network/Network.h>

#import "OELReachability.h"

NS_ASSUME_NONNULL_BEGIN

@interface OELReachability ()
@property (nonatomic, strong) nw_path_monitor_t monitor;
@property (nonatomic, strong) dispatch_queue_t monitorQueue;
@property (nonatomic, assign) BOOL currentlyReachable;
@end

@implementation OELReachability

+ (nullable OELReachability *)reachabilityForInternetConnection
{
	return [[self alloc] init];
}

- (instancetype)init
{
	if ((self = [super init])) {
		self.monitorQueue = dispatch_queue_create("com.vakesz.glasstual.reachability", DISPATCH_QUEUE_SERIAL);
		self.monitor = nw_path_monitor_create();
	}

	return self;
}

- (void)dealloc
{
	[self stopNotifier];

	self.reachableBlock = nil;
	self.unreachableBlock = nil;
}

- (BOOL)startNotifier
{
	__weak typeof(self) weakSelf = self;

	nw_path_monitor_set_queue(self.monitor, self.monitorQueue);
	nw_path_monitor_set_update_handler(self.monitor, ^(nw_path_t path) {
		BOOL reachable = (nw_path_get_status(path) == nw_path_status_satisfied);

		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf pathChangedReachable:reachable];
		});
	});

	nw_path_monitor_start(self.monitor);

	return YES;
}

- (void)stopNotifier
{
	if (self.monitor) {
		nw_path_monitor_cancel(self.monitor);
	}
}

- (BOOL)isReachable
{
	return self.currentlyReachable;
}

- (void)pathChangedReachable:(BOOL)reachable
{
	BOOL wasReachable = self.currentlyReachable;

	self.currentlyReachable = reachable;

	if (reachable == wasReachable) {
		return;
	}

	if (reachable) {
		if (self.reachableBlock) {
			self.reachableBlock(self);
		}
	} else {
		if (self.unreachableBlock) {
			self.unreachableBlock(self);
		}
	}
}

@end

NS_ASSUME_NONNULL_END
