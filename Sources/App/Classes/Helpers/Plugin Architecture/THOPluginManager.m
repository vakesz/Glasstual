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

#import "TXGlobalModels.h"
#import "TDCAlert.h"
#import "TLOLocalization.h"
#import "TPCApplicationInfo.h"
#import "TPCPathInfo.h"
#import "TPCPreferencesUserDefaults.h"
#import "TPCResourceManager.h"
#import "THOPluginDispatcherPrivate.h"
#import "THOPluginItemPrivate.h"
#import "THOPluginProtocol.h"
#import "THOPluginManagerPrivate.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const THOPluginManagerFinishedLoadingPluginsNotification =
	@"THOPluginManagerFinishedLoadingPluginsNotification";

@interface THOPluginManager ()
@property(nonatomic, assign, readwrite) BOOL pluginsLoaded;
@property(nonatomic, copy, readwrite, nullable) NSArray<THOPluginItem *> *loadedPlugins;
@property(nonatomic, copy, nullable) NSArray<NSBundle *> *obsoleteBundles;
@property(nonatomic, assign) THOPluginItemSupportedFeature supportedFeatures;
@end

@implementation THOPluginManager

#pragma mark -
#pragma mark Retain & Release

- (void)loadPlugins
{
	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		XRPerformBlockAsynchronouslyOnQueue([THOPluginDispatcher dispatchQueue], ^{
			[self _loadPlugins];
		});
	});
}

- (void)unloadPlugins
{
	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		XRPerformBlockAsynchronouslyOnQueue([THOPluginDispatcher dispatchQueue], ^{
			[self _unloadPlugins];
		});
	});
}

- (void)_loadPlugins
{
	NSMutableArray<THOPluginItem *> *loadedPlugins = [NSMutableArray array];
	NSMutableArray<NSString *> *bundlesToLoad = [NSMutableArray array];
	NSMutableArray<NSString *> *loadedBundles = [NSMutableArray array];
	NSMutableArray<NSBundle *> *obsoleteBundles = [NSMutableArray array];

	NSArray *pathsToLoad =
		[RZFileManager() buildPathArray:[TPCPathInfo customExtensions], [TPCPathInfo bundledExtensions], nil];

	for (NSString *path in pathsToLoad) {
		NSArray *pathFiles = [RZFileManager() contentsOfDirectoryAtPath:path error:NULL];

		if (pathFiles == nil) {
			continue;
		}

		for (NSString *file in pathFiles) {
			if ([file hasSuffix:TPCResourceManagerBundleDocumentTypeExtension] == NO) {
				continue;
			}

			NSString *filePath = [path stringByAppendingPathComponent:file];

			[bundlesToLoad addObject:filePath];
		}
	}

	for (NSString *bundlePath in bundlesToLoad) {
		NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];

		if (bundle == nil) {
			continue;
		}

		NSString *bundleIdentifier = bundle.bundleIdentifier;

		if (bundleIdentifier == nil || [loadedBundles containsObject:bundleIdentifier]) {
			continue;
		}

		/* Begin version comparison */
		NSDictionary *infoDictionary = bundle.infoDictionary;

		NSString *comparisonVersion = infoDictionary[@"MinimumGlasstualVersion"];

		if (comparisonVersion == nil) {
			[obsoleteBundles addObject:bundle];

			NSLog(@" ---------------------------- ERROR ---------------------------- ");
			NSLog(@"                                                                 ");
			NSLog(@"  Glasstual has failed to load the bundle at the following path    ");
			NSLog(@"  which did not specify a minimum version:                       ");
			NSLog(@"                                                                 ");
			NSLog(@"     Bundle Path: %@", bundle.bundlePath);
			NSLog(@"                                                                 ");
			NSLog(@"  Please add a key-value pair in the bundle's Info.plist file    ");
			NSLog(@"  with the key name as \"MinimumGlasstualVersion\"                 ");
			NSLog(@"                                                                 ");
			NSLog(@"  For example, to support this version and later:                ");
			NSLog(@"                                                                 ");
			NSLog(@"     <key>MinimumGlasstualVersion</key>                            ");
			NSLog(@"     <string>%@</string>", THOPluginProtocolCompatibilityMinimumVersion);
			NSLog(@"                                                                 ");
			NSLog(@" --------------------------------------------------------------- ");

			continue;
		}

		NSComparisonResult comparisonResult = [comparisonVersion compare:THOPluginProtocolCompatibilityMinimumVersion
																 options:NSNumericSearch];

		if (comparisonResult == NSOrderedAscending) {
			[obsoleteBundles addObject:bundle];

			NSLog(@" ---------------------------- ERROR ---------------------------- ");
			NSLog(@"                                                                 ");
			NSLog(@"  Glasstual has failed to load the bundle at the following path    ");
			NSLog(@"  because the specified minimum version is out of range:         ");
			NSLog(@"                                                                 ");
			NSLog(@"     Bundle Path: %@", bundle.bundlePath);
			NSLog(@"                                                                 ");
			NSLog(@"     Minimum version specified by bundle: %@", comparisonVersion);
			NSLog(@"     Version used by Glasstual for comparison: %@", THOPluginProtocolCompatibilityMinimumVersion);
			NSLog(@"                                                                 ");
			NSLog(@" --------------------------------------------------------------- ");

			continue;
		}

		/* Load bundle as a plugin */
		THOPluginItem *plugin = [THOPluginItem new];

		BOOL pluginLoaded = [plugin loadBundle:bundle];

		if (pluginLoaded == NO) {
			continue;
		}

		[loadedPlugins addObject:plugin];

		[loadedBundles addObject:bundleIdentifier];

		[self updateSupportedFeaturesPropertyWithPlugin:plugin];
	}

	self.loadedPlugins = loadedPlugins;

	self.obsoleteBundles = obsoleteBundles;

	self.pluginsLoaded = YES;

	XRPerformBlockAsynchronouslyOnMainQueue(^{
		[self checkForObsoleteBundles];

		[RZNotificationCenter() postNotificationName:THOPluginManagerFinishedLoadingPluginsNotification object:self];
	});
}

- (void)_unloadPlugins
{
	for (THOPluginItem *plugin in self.loadedPlugins) {
		[plugin unloadBundle];
	}

	self.loadedPlugins = nil;
}

#pragma mark -
#pragma mark AppleScript Support

- (NSArray<NSString *> *)supportedAppleScriptCommands
{
	return [self supportedAppleScriptCommands:NO];
}

- (NSDictionary<NSString *, NSString *> *)supportedAppleScriptCommandsAndPaths
{
	return [self supportedAppleScriptCommands:YES];
}

- (id)supportedAppleScriptCommands:(BOOL)returnPathInfo
{
	NSArray *forbiddenCommands = self.listOfForbiddenCommandNames;

	NSArray *scriptPaths =
		[RZFileManager() buildPathArray:[TPCPathInfo customScripts], [TPCPathInfo bundledScripts], nil];

	id returnValue = nil;

	if (returnPathInfo) {
		returnValue = [NSMutableDictionary dictionary];
	} else {
		returnValue = [NSMutableArray array];
	}

	for (NSString *path in scriptPaths) {
		NSArray *pathFiles = [RZFileManager() contentsOfDirectoryAtPath:path error:NULL];

		for (NSString *file in pathFiles) {
			NSString *filePath = [path stringByAppendingPathComponent:file];

			NSString *fileExtension = file.pathExtension;

			NSString *fileWithoutExtension = file.stringByDeletingPathExtension;

			NSString *command = fileWithoutExtension.lowercaseString;

			BOOL executable = [RZFileManager() isExecutableFileAtPath:filePath];

			if (executable == NO &&
				[fileExtension isEqualToString:TPCResourceManagerScriptDocumentTypeExtensionWithoutPeriod] == NO) {
				LogToConsoleInfo("WARNING: File “%{public}@“ found in unsupervised script folder but it isn't "
								 "AppleScript or an executable. It will be ignored.",
								 file);

				continue;
			} else if ([forbiddenCommands containsObject:command]) {
				LogToConsoleInfo("WARNING: The command “%{public}@“ exists as a script file, but it is being ignored "
								 "because the command name is forbidden.",
								 fileWithoutExtension);

				continue;
			}

			if (returnPathInfo) {
				[returnValue setObjectWithoutOverride:filePath forKey:command];
			} else {
				[returnValue addObjectWithoutDuplication:command];
			}
		}
	}

	return returnValue;
}

- (NSArray<NSString *> *)listOfForbiddenCommandNames
{
	/* List of commands that cannot be used as the name of a script 
	 because they would conflict with the commands defined by one or
	 more standard (RFC) */
	return [TPCResourceManager arrayFromResources:@"StaticStore" key:@"THOPluginManager List of Forbidden Commands"];
}

#pragma mark -
#pragma mark Obsolete Bundles

- (void)checkForObsoleteBundles
{
	NSArray *obsoleteBundles = self.obsoleteBundles;

	if (obsoleteBundles.count == 0) {
		return;
	}

	[self _presentObsoleteBundlesAlertForBundles:obsoleteBundles];
}

- (void)_presentObsoleteBundlesAlertForBundles:(NSArray *)thirdPartyBundles
{
	NSString *bundlesName = [NSBundle formattedDisplayNamesForBundles:thirdPartyBundles];

	[TDCAlert alertWithMessage:TXTLS(@"Prompts[45a-df]", THOPluginProtocolCompatibilityMinimumVersion)
						 title:TXTLS(@"Prompts[af6-45]", bundlesName)
				 defaultButton:TXTLS(@"Prompts[324-5d]")
			   alternateButton:nil
				   otherButton:TXTLS(@"Prompts[0ik-o9]")
				suppressionKey:nil
			   suppressionText:nil
			   completionBlock:^(TDCAlertResponse buttonClicked, BOOL suppressed, id _Nullable underlyingAlert) {
				   if (buttonClicked != TDCAlertResponseOther) {
					   return;
				   }

				   /* Revealing the bundles is not an answer to the question the alert
		 asks, so ask it again once the user has had a look. */
				   [NSBundle openInstallationLocationsForBundles:thirdPartyBundles];

				   [self _presentObsoleteBundlesAlertForBundles:thirdPartyBundles];
			   }];
}

- (void)findHandlerForOutgoingCommand:(NSString *)command
								 path:(NSString *_Nullable *)path
							 isScript:(BOOL *)isScript
						  isExtension:(BOOL *)isExtension
{
	NSParameterAssert(command != nil);

	/* Reset context pointers */
	if (path) {
		*path = nil;
	}

	if (isScript) {
		*isScript = NO;
	}

	if (isExtension) {
		*isExtension = NO;
	}

	/* Find a script that matches this command */
	NSDictionary *scriptPaths = self.supportedAppleScriptCommandsAndPaths;

	for (NSString *scriptCommand in scriptPaths) {
		if ([scriptCommand isEqualToString:command] == NO) {
			continue;
		}

		if (path) {
			*path = scriptPaths[scriptCommand];
		}

		if (isScript) {
			*isScript = YES;
		}

		return;
	}

	/* Find an extension that matches this command */
	BOOL pluginFound = [self.supportedUserInputCommands containsObject:command];

	if (pluginFound) {
		if (isExtension) {
			*isExtension = YES;
		}
	}
}

#pragma mark -
#pragma mark Extension Information

- (void)updateSupportedFeaturesPropertyWithPlugin:(THOPluginItem *)plugin
{
	NSParameterAssert(plugin != nil);

#define _ef(_feature)                                                                                                  \
	if ([plugin supportsFeature:(_feature)] && [self supportsFeature:(_feature)] == NO) {                              \
		self->_supportedFeatures |= (_feature);                                                                        \
	}

	_ef(THOPluginItemSupportedFeatureDidReceiveCommandEvent)
		_ef(THOPluginItemSupportedFeatureDidReceivePlainTextMessageEvent)
		//	_ef(THOPluginItemSupportedFeatureInlineMediaManipulation)
		_ef(THOPluginItemSupportedFeatureNewMessagePostedEvent) _ef(THOPluginItemSupportedFeatureOutputSuppressionRules)
			_ef(THOPluginItemSupportedFeaturePreferencePane)
				_ef(THOPluginItemSupportedFeatureServerInputDataInterception)
					_ef(THOPluginItemSupportedFeatureSubscribedServerInputCommands)
						_ef(THOPluginItemSupportedFeatureSubscribedUserInputCommands)
							_ef(THOPluginItemSupportedFeatureUserInputDataInterception)
								_ef(THOPluginItemSupportedFeatureWebViewJavaScriptPayloads)
									_ef(THOPluginItemSupportedFeatureWillRenderMessageEvent)

#undef _ef
}

- (BOOL)supportsFeature:(THOPluginItemSupportedFeature)feature
{
	return ((self->_supportedFeatures & feature) == feature);
}

- (NSArray<THOPluginOutputSuppressionRule *> *)pluginOutputSuppressionRules
{
	if (self.pluginsLoaded == NO) {
		return @[];
	}

	static NSArray<THOPluginOutputSuppressionRule *> *cachedValue = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		NSMutableArray<THOPluginOutputSuppressionRule *> *allRules = [NSMutableArray array];

		for (THOPluginItem *plugin in self.loadedPlugins) {
			if ([plugin supportsFeature:THOPluginItemSupportedFeatureOutputSuppressionRules] == NO) {
				continue;
			}

			NSArray *rules = plugin.outputSuppressionRules;

			if (rules) {
				[allRules addObjectsFromArray:rules];
			}
		}

		cachedValue = [allRules copy];
	});

	return cachedValue;
}

- (NSArray<NSString *> *)supportedUserInputCommands
{
	if (self.pluginsLoaded == NO) {
		return @[];
	}

	static NSArray<NSString *> *cachedValue = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		NSMutableArray<NSString *> *allCommands = [NSMutableArray array];

		for (THOPluginItem *plugin in self.loadedPlugins) {
			if ([plugin supportsFeature:THOPluginItemSupportedFeatureSubscribedUserInputCommands] == NO) {
				continue;
			}

			NSArray *commands = plugin.supportedUserInputCommands;

			for (NSString *command in commands) {
				[allCommands addObjectWithoutDuplication:command];
			}
		}

		[allCommands sortUsingComparator:NSDefaultComparator];

		cachedValue = [allCommands copy];
	});

	return cachedValue;
}

- (NSArray<NSString *> *)supportedServerInputCommands
{
	if (self.pluginsLoaded == NO) {
		return @[];
	}

	static NSArray<NSString *> *cachedValue = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		NSMutableArray<NSString *> *allCommands = [NSMutableArray array];

		for (THOPluginItem *plugin in self.loadedPlugins) {
			if ([plugin supportsFeature:THOPluginItemSupportedFeatureSubscribedServerInputCommands] == NO) {
				continue;
			}

			NSArray *commands = plugin.supportedServerInputCommands;

			for (NSString *command in commands) {
				[allCommands addObjectWithoutDuplication:command];
			}
		}

		[allCommands sortUsingComparator:NSDefaultComparator];

		cachedValue = [allCommands copy];
	});

	return cachedValue;
}

- (NSArray<THOPluginItem *> *)pluginsWithPreferencePanes
{
	if (self.pluginsLoaded == NO) {
		return @[];
	}

	static NSArray<THOPluginItem *> *cachedValue = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		NSMutableArray<THOPluginItem *> *allExtensions = [NSMutableArray array];

		for (THOPluginItem *plugin in self.loadedPlugins) {
			if ([plugin supportsFeature:THOPluginItemSupportedFeaturePreferencePane] == NO) {
				continue;
			}

			[allExtensions addObject:plugin];
		}

		[allExtensions sortUsingComparator:^NSComparisonResult(THOPluginItem *object1, THOPluginItem *object2) {
			return [object1.pluginPreferencesPaneMenuItemTitle compare:object2.pluginPreferencesPaneMenuItemTitle];
		}];

		cachedValue = [allExtensions copy];
	});

	return cachedValue;
}

@end

NS_ASSUME_NONNULL_END
