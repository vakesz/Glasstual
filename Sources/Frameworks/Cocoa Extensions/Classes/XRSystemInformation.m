/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2020 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
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
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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

#import <AppKit/AppKit.h>

#include <sys/sysctl.h>

#include <stdatomic.h>

static atomic_bool _systemIsSleeping = false;

NS_ASSUME_NONNULL_BEGIN

@implementation XRSystemInformation

#pragma mark -
#pragma mark Public

+ (void)observeSleepNotifications
{
	/* Track sleep state from workspace notifications. Observers are
	 registered lazily (this framework is also linked by XPC services
	 that never ask) and live for the lifetime of the process. */
	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		NSNotificationCenter *center = [NSWorkspace sharedWorkspace].notificationCenter;

		[center addObserverForName:NSWorkspaceWillSleepNotification
							object:nil
							 queue:nil
						usingBlock:^(NSNotification *note) {
							atomic_store(&_systemIsSleeping, true);
						}];

		[center addObserverForName:NSWorkspaceDidWakeNotification
							object:nil
							 queue:nil
						usingBlock:^(NSNotification *note) {
							atomic_store(&_systemIsSleeping, false);
						}];
	});
}

+ (BOOL)systemIsSleeping
{
	[self observeSleepNotifications];

	return atomic_load(&_systemIsSleeping);
}

+ (nullable NSString *)systemBuildVersion
{
	static id cachedValue = nil;

	if (cachedValue == nil) {
		cachedValue = [NSDictionary
			dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"][@"ProductBuildVersion"];
	}

	return cachedValue;
}

+ (nullable NSString *)systemStandardVersion
{
	static id cachedValue = nil;

	if (cachedValue == nil) {
		NSOperatingSystemVersion version = [NSProcessInfo processInfo].operatingSystemVersion;

		if (version.patchVersion == 0) {
			cachedValue =
				[NSString stringWithFormat:@"%ld.%ld", (long)version.majorVersion, (long)version.minorVersion];
		} else {
			cachedValue = [NSString stringWithFormat:@"%ld.%ld.%ld",
													 (long)version.majorVersion,
													 (long)version.minorVersion,
													 (long)version.patchVersion];
		}
	}

	return cachedValue;
}

+ (nullable NSString *)systemOperatingSystemName
{
	static id cachedValue = nil;

	if (cachedValue == nil) {
		NSBundle *bundle = [NSBundle bundleForClass:[self class]];

		NSInteger majorVersion = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion;

		if (majorVersion == 26) {
			cachedValue = NSLocalizedStringFromTableInBundle(@"macOS Tahoe", @"XRSystemInformation", bundle, nil);
		} else {
			cachedValue = NSLocalizedStringFromTableInBundle(@"macOS", @"XRSystemInformation", bundle, nil);
		}
	}

	return cachedValue;
}

#pragma mark -
#pragma mark Private

+ (nullable NSString *)systemModelToken
{
	static id cachedValue = nil;

	if (cachedValue == nil) {
		char modelBuffer[256];

		size_t sz = sizeof(modelBuffer);

		if (sysctlbyname("hw.model", modelBuffer, &sz, NULL, 0) == 0) {
			modelBuffer[(sizeof(modelBuffer) - 1)] = 0;

			cachedValue = @(modelBuffer);
		}
	}

	return cachedValue;
}

+ (nullable NSString *)systemModelName
{
	/* June 11, 2024: This method identifies a model based on the prefix 
	 of its identifier. New Macs no longer have a model specific prefix
	 and instead simply begin with "Mac" — This method is typically used
	 as a last resort to identify an unknown model and it is not worth
	 the effort to redesign it to accommodate this change. */
	static id cachedValue = nil;

	if (cachedValue == nil) {
		/* This method is not returning very detailed information. Only
		the model being ran on. Therefore, not much love will be put into
		it. As can be seen below, we are defining our models inline instead
		of using a dictionary that will have to be loaded from a file. */
		NSBundle *bundle = [NSBundle bundleForClass:[self class]];

		NSDictionary *modelPrefixes = @{
			@"macbookpro" : NSLocalizedStringFromTableInBundle(@"MacBook Pro", @"XRSystemInformation", bundle, nil),
			@"macbookair" : NSLocalizedStringFromTableInBundle(@"MacBook Air", @"XRSystemInformation", bundle, nil),
			@"macbook" : NSLocalizedStringFromTableInBundle(@"MacBook", @"XRSystemInformation", bundle, nil),
			@"macpro" : NSLocalizedStringFromTableInBundle(@"Mac Pro", @"XRSystemInformation", bundle, nil),
			@"macmini" : NSLocalizedStringFromTableInBundle(@"Mac Mini", @"XRSystemInformation", bundle, nil),
			@"imac" : NSLocalizedStringFromTableInBundle(@"iMac", @"XRSystemInformation", bundle, nil),
			@"xserve" : NSLocalizedStringFromTableInBundle(@"Xserve", @"XRSystemInformation", bundle, nil)
		};

		NSString *modelToken = [self systemModelToken];

		if (modelToken.length <= 0) {
			return nil;
		}

		modelToken = modelToken.lowercaseString;

		for (NSString *modelPrefix in modelPrefixes) {
			if ([modelToken hasPrefix:modelPrefix]) {
				cachedValue = modelPrefixes[modelPrefix];
			}
		}

		if (cachedValue == nil) {
			cachedValue = NSLocalizedStringFromTableInBundle(@"Mac", @"XRSystemInformation", bundle, nil);
		}
	}

	return cachedValue;
}

@end

NS_ASSUME_NONNULL_END
