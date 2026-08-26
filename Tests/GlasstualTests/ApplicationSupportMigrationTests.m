/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import <XCTest/XCTest.h>

#import "GLTTestClient.h"
#import "IRCChannelPrivate.h"
#import "IRCTreeItemPrivate.h"
#import "NSStringHelper.h"
#import "TLOFileLoggerPrivate.h"
#import "TLOSoundPlayerPrivate.h"
#import "TPCApplicationInfo.h"
#import "TPCPathInfoPrivate.h"
#import "TPCResourceManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface ApplicationSupportMigrationTests : XCTestCase
@end

@implementation ApplicationSupportMigrationTests

#pragma mark - Application metadata

- (void)testApplicationMetadataMatchesMainBundle
{
	NSBundle *bundle = NSBundle.mainBundle;

	XCTAssertEqualObjects(TPCApplicationInfo.applicationName, [bundle objectForInfoDictionaryKey:@"CFBundleName"]);
	XCTAssertEqualObjects(TPCApplicationInfo.applicationVersion,
						  [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]);
	XCTAssertEqualObjects(TPCApplicationInfo.applicationVersionShort,
						  [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
	XCTAssertEqualObjects(TPCApplicationInfo.applicationBundleIdentifier, bundle.bundleIdentifier);
	XCTAssertEqualObjects(TPCApplicationInfo.applicationInfoPlist, bundle.infoDictionary);
}

- (void)testApplicationRuntimeMetadataIsSane
{
	XCTAssertGreaterThan(TPCApplicationInfo.applicationProcessID, 0);
	XCTAssertGreaterThanOrEqual(TPCApplicationInfo.timeIntervalSinceApplicationLaunch, 0);
	XCTAssertEqual(TPCApplicationInfo.applicationBirthday, 1279871580.0);
	XCTAssertGreaterThan(TPCApplicationInfo.applicationNameWithoutVersion.length, 0);
}

#pragma mark - Paths

- (void)testPathInfoExposesBundleAndBundledResourceLocations
{
	NSBundle *bundle = NSBundle.mainBundle;

	XCTAssertEqualObjects(TPCPathInfo.applicationBundle, bundle.bundlePath);
	XCTAssertEqualObjects(TPCPathInfo.applicationBundleURL, bundle.bundleURL);
	XCTAssertEqualObjects(TPCPathInfo.applicationResources, bundle.resourcePath);
	XCTAssertEqualObjects(TPCPathInfo.applicationResourcesURL, bundle.resourceURL);

	XCTAssertTrue([TPCPathInfo.bundledExtensions hasSuffix:@"Bundled Extensions"]);
	XCTAssertTrue([TPCPathInfo.bundledScripts hasSuffix:@"Bundled Scripts"]);
	XCTAssertTrue([TPCPathInfo.bundledThemes hasSuffix:@"Bundled Styles"]);
	XCTAssertEqualObjects(TPCPathInfo.systemDiagnosticReports, @"/Library/Logs/DiagnosticReports");
	XCTAssertGreaterThan(TPCPathInfo.userHome.length, 0);
}

- (void)testPathInfoCreatesTemporaryDirectoryAndExplicitDirectoryHelper
{
	NSString *temporaryPath = TPCPathInfo.applicationTemporary;
	BOOL isDirectory = NO;

	XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:temporaryPath isDirectory:&isDirectory]);
	XCTAssertTrue(isDirectory);
	XCTAssertTrue([temporaryPath containsString:NSBundle.mainBundle.bundleIdentifier]);

	NSURL *directory =
		[NSURL fileURLWithPath:[NSTemporaryDirectory()
								   stringByAppendingPathComponent:[NSString stringWithFormat:@"GlasstualPathTests-%@",
																							 NSUUID.UUID.UUIDString]]];

	XCTAssertFalse([NSFileManager.defaultManager fileExistsAtURL:directory]);

	[TPCPathInfo _createDirectoryAtURL:directory];

	XCTAssertTrue([NSFileManager.defaultManager fileExistsAtURL:directory]);
	XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:directory error:nil]);
}

#pragma mark - Resources

- (void)testResourceManagerLoadsKnownPropertyLists
{
	NSDictionary *networks = [TPCResourceManager dictionaryFromResources:@"IRCNetworks" cacheValue:NO];
	NSArray *networkList = [TPCResourceManager arrayFromResources:@"IRCNetworks" cacheValue:NO];
	NSDictionary *staticStore = [TPCResourceManager dictionaryFromResources:@"StaticStore"];

	XCTAssertTrue(networks != nil || networkList != nil);
	XCTAssertNotNil(staticStore);
	XCTAssertGreaterThan(staticStore.count, 0);
}

- (void)testResourceManagerCachesAndRejectsWrongTypes
{
	[TPCResourceManager.sharedResourcesCache removeAllObjects];

	NSDictionary *first = [TPCResourceManager dictionaryFromResources:@"StaticStore" cacheValue:YES];
	NSDictionary *second = [TPCResourceManager dictionaryFromResources:@"StaticStore" cacheValue:YES];
	NSString *cacheKey = @"StaticStore.plist / Root Folder / Root Object";

	XCTAssertNotNil(first);
	XCTAssertEqualObjects(first, second);
	XCTAssertNotNil([TPCResourceManager.sharedResourcesCache objectForKey:cacheKey]);
	XCTAssertEqualObjects([TPCResourceManager.sharedResourcesCache objectForKey:cacheKey], first);

	XCTAssertNil([TPCResourceManager arrayFromResources:@"StaticStore" cacheValue:NO]);
	XCTAssertNil([TPCResourceManager dictionaryFromResources:@"DoesNotExistAnywhere" cacheValue:NO]);
}

- (void)testResourceManagerDocumentTypeConstants
{
	XCTAssertEqualObjects(TPCResourceManagerBundleDocumentTypeExtension, @".bundle");
	XCTAssertEqualObjects(TPCResourceManagerBundleDocumentTypeExtensionWithoutPeriod, @"bundle");
	XCTAssertEqualObjects(TPCResourceManagerScriptDocumentTypeExtension, @".scpt");
	XCTAssertEqualObjects(TPCResourceManagerScriptDocumentTypeExtensionWithoutPeriod, @"scpt");
}

#pragma mark - File logger

- (void)testFileLoggerBuildsConsoleChannelAndQueryPaths
{
	GLTTestClient *client = [GLTTestClient testClient];
	NSString *root = @"/tmp/glasstual-logs";
	NSString *clientFolder =
		[NSString stringWithFormat:@"%@ (%@)", client.name.safeFilename, [client.uniqueIdentifier substringToIndex:5]];

	NSString *expectedConsole =
		[root stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@/%@/",
																		clientFolder,
																		TLOFileLoggerConsoleDirectoryName]];
	XCTAssertEqualObjects([TLOFileLogger writePathForItem:client relativeTo:root], expectedConsole);

	IRCChannel *channel = [[IRCChannel alloc] initWithConfigDictionary:@{@"channelName" : @"#chat"}];
	channel.associatedClient = client;

	NSString *expectedChannel =
		[root stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@/%@/%@/",
																		clientFolder,
																		TLOFileLoggerChannelDirectoryName,
																		@"#chat".safeFilename]];
	XCTAssertEqualObjects([TLOFileLogger writePathForItem:channel relativeTo:root], expectedChannel);

	IRCChannel *query = [[IRCChannel alloc]
		initWithConfigDictionary:@{@"channelName" : @"alice", @"channelType" : @(IRCChannelTypePrivateMessage)}];
	query.associatedClient = client;

	NSString *expectedQuery =
		[root stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@/%@/%@/",
																		clientFolder,
																		TLOFileLoggerPrivateMessageDirectoryName,
																		@"alice".safeFilename]];
	XCTAssertEqualObjects([TLOFileLogger writePathForItem:query relativeTo:root], expectedQuery);
}

- (void)testFileLoggerSkipsUtilityChannelsAndRequiresTranscriptFolder
{
	GLTTestClient *client = [GLTTestClient testClient];
	IRCChannel *utility = [[IRCChannel alloc]
		initWithConfigDictionary:@{@"channelName" : @"Utility", @"channelType" : @(IRCChannelTypeUtility)}];
	utility.associatedClient = client;

	XCTAssertNil([TLOFileLogger writePathForItem:utility relativeTo:@"/tmp/glasstual-logs"]);
	XCTAssertNil([TLOFileLogger writePathForItem:client]);
}

- (void)testFileLoggerWriteWithoutTranscriptFolderDoesNotOpenFile
{
	GLTTestClient *client = [GLTTestClient testClient];
	TLOFileLogger *logger = [[TLOFileLogger alloc] initWithClient:client];

	[logger writePlainText:@"should not write"];

	XCTAssertNil(logger.filePath);
	XCTAssertNil(logger.writePath);
	XCTAssertNil(logger.fileName);
}

#pragma mark - Sounds

- (void)testSoundFileDiscoveryMapsNamesAndPreservesLegacyCollisionBehavior
{
	NSURL *directory =
		[NSURL fileURLWithPath:[NSTemporaryDirectory()
								   stringByAppendingPathComponent:[NSString stringWithFormat:@"GlasstualSoundTests-%@",
																							 NSUUID.UUID.UUIDString]]];
	NSFileManager *fileManager = NSFileManager.defaultManager;

	XCTAssertTrue([fileManager createDirectoryAtURL:directory
						withIntermediateDirectories:YES
										 attributes:nil
											  error:nil]);

	@try {
		XCTAssertTrue([[NSData data] writeToURL:[directory URLByAppendingPathComponent:@"Ping.aiff"] atomically:YES]);
		XCTAssertTrue([[NSData data] writeToURL:[directory URLByAppendingPathComponent:@"Tone.aiff"] atomically:YES]);
		XCTAssertTrue([[NSData data] writeToURL:[directory URLByAppendingPathComponent:@"Tone.wav"] atomically:YES]);

		NSDictionary<NSString *, NSString *> *sounds = [TLOSoundPlayer soundFilesAtPath:directory.path];

		XCTAssertEqualObjects(sounds[@"Ping"], [directory.path stringByAppendingPathComponent:@"Ping.aiff"]);
		XCTAssertNotNil(sounds[@"Tone"]);
		XCTAssertEqual(sounds.count, 2);
	} @finally {
		XCTAssertTrue([fileManager removeItemAtURL:directory error:nil]);
	}
}

- (void)testUniqueSoundListContainsBeepAndIsCaseInsensitivelySorted
{
	NSArray<NSString *> *sounds = TLOSoundPlayer.uniqueListOfSounds;
	NSArray<NSString *> *sortedSounds = [sounds sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];

	XCTAssertTrue([sounds containsObject:@"Beep"]);
	XCTAssertEqualObjects(sounds, sortedSounds);
}

@end

NS_ASSUME_NONNULL_END
