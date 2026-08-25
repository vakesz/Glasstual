import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCChannelPrivate.h"
// #import "IRCTreeItemPrivate.h"
// #import "NSStringHelper.h"
// #import "TLOFileLoggerPrivate.h"
// #import "TLOSoundPlayerPrivate.h"
// #import "TPCApplicationInfo.h"
// #import "TPCPathInfoPrivate.h"
// #import "TPCResourceManager.h"
// #pragma mark - Application metadata
// #pragma mark - Paths
// #pragma mark - Resources
// #pragma mark - File logger
// #pragma mark - Sounds
/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class ApplicationSupportMigrationTests: XCTestCase {
    @objc
    func testApplicationMetadataMatchesMainBundle() {
        let bundle: NSBundle! = NSBundle.mainBundle

        XCTAssertEqualObjects(TPCApplicationInfo.applicationName, bundle.objectForInfoDictionaryKey("CFBundleName"))
        XCTAssertEqualObjects(TPCApplicationInfo.applicationVersion, bundle.objectForInfoDictionaryKey("CFBundleVersion"))
        XCTAssertEqualObjects(TPCApplicationInfo.applicationVersionShort, bundle.objectForInfoDictionaryKey("CFBundleShortVersionString"))
        XCTAssertEqualObjects(TPCApplicationInfo.applicationBundleIdentifier, bundle.bundleIdentifier)
        XCTAssertEqualObjects(TPCApplicationInfo.applicationInfoPlist, bundle.infoDictionary)
    }
    @objc
    func testApplicationRuntimeMetadataIsSane() {
        XCTAssertGreaterThan(TPCApplicationInfo.applicationProcessID, 0)

        XCTAssertGreaterThanOrEqual(TPCApplicationInfo.timeIntervalSinceApplicationLaunch, 0)

        XCTAssertEqual(TPCApplicationInfo.applicationBirthday, 1.2798716e+09)

        XCTAssertGreaterThan(TPCApplicationInfo.applicationNameWithoutVersion.length, 0)
    }
    @objc
    func testPathInfoExposesBundleAndBundledResourceLocations() {
        let bundle: NSBundle! = NSBundle.mainBundle

        XCTAssertEqualObjects(TPCPathInfo.applicationBundle, bundle.bundlePath)
        XCTAssertEqualObjects(TPCPathInfo.applicationBundleURL, bundle.bundleURL)
        XCTAssertEqualObjects(TPCPathInfo.applicationResources, bundle.resourcePath)
        XCTAssertEqualObjects(TPCPathInfo.applicationResourcesURL, bundle.resourceURL)

        XCTAssertTrue(TPCPathInfo.bundledExtensions.hasSuffix("Bundled Extensions"))
        XCTAssertTrue(TPCPathInfo.bundledScripts.hasSuffix("Bundled Scripts"))
        XCTAssertTrue(TPCPathInfo.bundledThemes.hasSuffix("Bundled Styles"))

        XCTAssertEqualObjects(TPCPathInfo.systemDiagnosticReports, "/Library/Logs/DiagnosticReports")

        XCTAssertGreaterThan(TPCPathInfo.userHome.length, 0)
    }
    @objc
    func testPathInfoCreatesTemporaryDirectoryAndExplicitDirectoryHelper() {
        let temporaryPath: String! = TPCPathInfo.applicationTemporary
        var isDirectory = false

        XCTAssertTrue(NSFileManager.defaultManager.fileExistsAtPath(temporaryPath, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory)
        XCTAssertTrue(temporaryPath.containsString(NSBundle.mainBundle.bundleIdentifier))

        let directory: URL! = URL.fileURLWithPath(NSTemporaryDirectory().stringByAppendingPathComponent(String(format: "GlasstualPathTests-%@", NSUUID.UUID.UUIDString)))

        XCTAssertFalse(NSFileManager.defaultManager.fileExistsAtURL(directory))

        TPCPathInfo._createDirectoryAtURL(directory)

        XCTAssertTrue(NSFileManager.defaultManager.fileExistsAtURL(directory))
        XCTAssertTrue(NSFileManager.defaultManager.removeItemAtURL(directory, error: nil))
    }
    @objc
    func testResourceManagerLoadsKnownPropertyLists() {
        let networks: NSDictionary! = TPCResourceManager.dictionaryFromResources("IRCNetworks", cacheValue: false)
        let networkList: NSArray! = TPCResourceManager.arrayFromResources("IRCNetworks", cacheValue: false)
        let staticStore: NSDictionary! = TPCResourceManager.dictionaryFromResources("StaticStore")

        XCTAssertTrue(networks != nil || networkList != nil)
        XCTAssertNotNil(staticStore)
        XCTAssertGreaterThan(staticStore.count, 0)
    }
    @objc
    func testResourceManagerCachesAndRejectsWrongTypes() {
        TPCResourceManager.sharedResourcesCache.removeAllObjects()

        let first: NSDictionary! = TPCResourceManager.dictionaryFromResources("StaticStore", cacheValue: true)
        let second: NSDictionary! = TPCResourceManager.dictionaryFromResources("StaticStore", cacheValue: true)
        let cacheKey = "StaticStore.plist / Root Folder / Root Object"

        XCTAssertNotNil(first)

        XCTAssertEqualObjects(first, second)

        XCTAssertNotNil(TPCResourceManager.sharedResourcesCache.objectForKey(cacheKey))

        XCTAssertEqualObjects(TPCResourceManager.sharedResourcesCache.objectForKey(cacheKey), first)

        XCTAssertNil(TPCResourceManager.arrayFromResources("StaticStore", cacheValue: false))
        XCTAssertNil(TPCResourceManager.dictionaryFromResources("DoesNotExistAnywhere", cacheValue: false))
    }
    @objc
    func testResourceManagerDocumentTypeConstants() {
        XCTAssertEqualObjects(TPCResourceManagerBundleDocumentTypeExtension, ".bundle")
        XCTAssertEqualObjects(TPCResourceManagerBundleDocumentTypeExtensionWithoutPeriod, "bundle")
        XCTAssertEqualObjects(TPCResourceManagerScriptDocumentTypeExtension, ".scpt")
        XCTAssertEqualObjects(TPCResourceManagerScriptDocumentTypeExtensionWithoutPeriod, "scpt")
    }
    @objc
    func testFileLoggerBuildsConsoleChannelAndQueryPaths() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        let root = "/tmp/glasstual-logs"
        let clientFolder: String! = String(format: "%@ (%@)", client.name.safeFilename, client.uniqueIdentifier.substringToIndex(5))
        let expectedConsole: String! = root.stringByAppendingPathComponent(String(format: "/%@/%@/", clientFolder, TLOFileLoggerConsoleDirectoryName))

        XCTAssertEqualObjects(TLOFileLogger.writePathForItem(client, relativeTo: root), expectedConsole)

        var channel: UnsafeMutablePointer<IRCChannel>! = IRCChannel(configDictionary: ["channelName": "#chat"])

        channel.associatedClient = client

        let expectedChannel: String! = root.stringByAppendingPathComponent(String(format: "/%@/%@/%@/", clientFolder, TLOFileLoggerChannelDirectoryName, "#chat".safeFilename))

        XCTAssertEqualObjects(TLOFileLogger.writePathForItem(channel, relativeTo: root), expectedChannel)

        var query: UnsafeMutablePointer<IRCChannel>! = IRCChannel(configDictionary: ["channelName": "alice", "channelType": IRCChannelTypePrivateMessage])

        query.associatedClient = client

        let expectedQuery: String! = root.stringByAppendingPathComponent(String(format: "/%@/%@/%@/", clientFolder, TLOFileLoggerPrivateMessageDirectoryName, "alice".safeFilename))

        XCTAssertEqualObjects(TLOFileLogger.writePathForItem(query, relativeTo: root), expectedQuery)
    }
    @objc
    func testFileLoggerSkipsUtilityChannelsAndRequiresTranscriptFolder() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        var utility: UnsafeMutablePointer<IRCChannel>! = IRCChannel(configDictionary: ["channelName": "Utility", "channelType": IRCChannelTypeUtility])

        utility.associatedClient = client
        XCTAssertNil(TLOFileLogger.writePathForItem(utility, relativeTo: "/tmp/glasstual-logs"))
        XCTAssertNil(TLOFileLogger.writePathForItem(client))
    }
    @objc
    func testFileLoggerWriteWithoutTranscriptFolderDoesNotOpenFile() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        let logger: UnsafeMutablePointer<TLOFileLogger>! = TLOFileLogger(client: client)

        logger.writePlainText("should not write")

        XCTAssertNil(logger.filePath)
        XCTAssertNil(logger.writePath)
        XCTAssertNil(logger.fileName)
    }
    @objc
    func testSoundFileDiscoveryMapsNamesAndPreservesLegacyCollisionBehavior() {
        let directory: URL! = URL.fileURLWithPath(NSTemporaryDirectory().stringByAppendingPathComponent(String(format: "GlasstualSoundTests-%@", NSUUID.UUID.UUIDString)))
        let fileManager: NSFileManager! = NSFileManager.defaultManager

        XCTAssertTrue(fileManager.createDirectoryAtURL(directory, withIntermediateDirectories: true, attributes: nil, error: nil))

        /*
        @try{XCTAssertTrue([[NSDatadata]writeToURL:[directoryURLByAppendingPathComponent:@"Ping.aiff"]atomically:YES]);XCTAssertTrue([[NSDatadata]writeToURL:[directoryURLByAppendingPathComponent:@"Tone.aiff"]atomically:YES]);XCTAssertTrue([[NSDatadata]writeToURL:[directoryURLByAppendingPathComponent:@"Tone.wav"]atomically:YES]);NSDictionary<NSString*,NSString*>*sounds=[TLOSoundPlayersoundFilesAtPath:directory.path];XCTAssertEqualObjects(sounds[@"Ping"],[directory.pathstringByAppendingPathComponent:@"Ping.aiff"]);XCTAssertNotNil(sounds[@"Tone"]);XCTAssertEqual(sounds.count,2);}@finally{XCTAssertTrue([fileManagerremoveItemAtURL:directoryerror:nil]);}
        */
    }
    @objc
    func testUniqueSoundListContainsBeepAndIsCaseInsensitivelySorted() {
        let sounds: [String]! = TLOSoundPlayer.uniqueListOfSounds
        let sortedSounds: [String]! = sounds.sortedArrayUsingSelector(#selector(caseInsensitiveCompare(_:)))

        XCTAssertTrue(sounds.containsObject("Beep"))
        XCTAssertEqualObjects(sounds, sortedSounds)
    }
}