/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
@testable import Glasstual
import GlasstualPluginKit
import XCTest

@MainActor
final class ApplicationSupportMigrationTests: XCTestCase {
	func testApplicationMetadataMatchesMainBundle() {
		let bundle = Bundle.main

		XCTAssertEqual(
			ApplicationInfo.applicationName(),
			bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
		)
		XCTAssertEqual(
			ApplicationInfo.applicationVersion(),
			bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
		)
		XCTAssertEqual(
			ApplicationInfo.applicationVersionShort(),
			bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
		)
		XCTAssertEqual(ApplicationInfo.applicationBundleIdentifier(), bundle.bundleIdentifier)
		XCTAssertEqual(
			ApplicationInfo.applicationInfoPlist() as NSDictionary,
			bundle.infoDictionary as NSDictionary?
		)
	}

	func testApplicationRuntimeMetadataIsSane() {
		XCTAssertEqual(NSStringFromClass(ApplicationInfo.self), "TPCApplicationInfo")
		XCTAssertTrue(ApplicationInfo.responds(to: NSSelectorFromString("applicationRunCount")))
		XCTAssertGreaterThan(ApplicationInfo.applicationProcessID(), 0)
		XCTAssertGreaterThanOrEqual(ApplicationInfo.timeIntervalSinceApplicationLaunch(), 0)
		XCTAssertEqual(ApplicationInfo.applicationBirthday(), 1_279_871_580)
		XCTAssertFalse(ApplicationInfo.applicationNameWithoutVersion().isEmpty)
	}

	func testPathInfoExposesBundleAndBundledResourceLocations() {
		let bundle = Bundle.main

		XCTAssertEqual(PathInfo.applicationBundle, bundle.bundlePath)
		XCTAssertEqual(PathInfo.applicationBundleURL, bundle.bundleURL)
		XCTAssertEqual(PathInfo.applicationResources, bundle.resourcePath)
		XCTAssertEqual(PathInfo.applicationResourcesURL, bundle.resourceURL)
		XCTAssertTrue(PathInfo.bundledExtensions.hasSuffix("Bundled Extensions"))
		XCTAssertTrue(PathInfo.bundledScripts.hasSuffix("Bundled Scripts"))
		XCTAssertTrue(PathInfo.bundledThemes.hasSuffix("Bundled Styles"))
		XCTAssertEqual(PathInfo.systemDiagnosticReports, "/Library/Logs/DiagnosticReports")
		XCTAssertFalse(PathInfo.userHome.isEmpty)
	}

	func testPathInfoCreatesTemporaryDirectoryAndExplicitDirectoryHelper() throws {
		let temporaryPath = PathInfo.applicationTemporary
		var isDirectory = ObjCBool(false)

		XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryPath, isDirectory: &isDirectory))
		XCTAssertTrue(isDirectory.boolValue)
		XCTAssertTrue(temporaryPath.contains(Bundle.main.bundleIdentifier ?? ""))

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("GlasstualPathTests-\(UUID().uuidString)", isDirectory: true)

		XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

		PathInfo.createDirectory(at: directory)

		XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
		try FileManager.default.removeItem(at: directory)
		XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
	}

	func testResourceManagerLoadsKnownPropertyLists() {
		let networks = ResourceManager.dictionary(fromResources: "IRCNetworks", cacheValue: false)
		let networkList = ResourceManager.array(fromResources: "IRCNetworks", cacheValue: false)
		let staticStore = ResourceManager.dictionary(fromResources: "StaticStore")

		XCTAssertTrue(networks != nil || networkList != nil)
		XCTAssertNotNil(staticStore)
		XCTAssertGreaterThan(staticStore?.count ?? 0, 0)
	}

	func testResourceManagerCachesAndRejectsWrongTypes() {
		ResourceManager.sharedResourcesCache.removeAllObjects()

		let first = ResourceManager.dictionary(fromResources: "StaticStore", cacheValue: true)
		let second = ResourceManager.dictionary(fromResources: "StaticStore", cacheValue: true)
		let cacheKey = "StaticStore.plist / Root Folder / Root Object" as NSString

		XCTAssertNotNil(first)
		XCTAssertEqual(first as NSDictionary?, second as NSDictionary?)
		XCTAssertNotNil(ResourceManager.sharedResourcesCache.object(forKey: cacheKey))
		XCTAssertEqual(
			ResourceManager.sharedResourcesCache.object(forKey: cacheKey) as? NSDictionary,
			first as NSDictionary?
		)
		XCTAssertNil(ResourceManager.array(fromResources: "StaticStore", cacheValue: false))
		XCTAssertNil(ResourceManager.dictionary(fromResources: "DoesNotExistAnywhere", cacheValue: false))
	}

	func testResourceManagerDocumentTypeConstants() {
		XCTAssertEqual(ResourceDocumentType.bundleFileExtension, ".bundle")
		XCTAssertEqual(ResourceDocumentType.bundleFilenameExtension, "bundle")
		XCTAssertEqual(ResourceDocumentType.scriptFileExtension, ".scpt")
		XCTAssertEqual(ResourceDocumentType.scriptFilenameExtension, "scpt")
	}

	func testPreferencesReloadActionsPreserveLegacyBitAssignments() {
		XCTAssertEqual(PreferencesReloadAction.appearance.rawValue, 1 << 0)
		XCTAssertEqual(PreferencesReloadAction.channelViewArrangement.rawValue, 1 << 1)
		XCTAssertEqual(PreferencesReloadAction.dockIconBadges.rawValue, 1 << 2)
		XCTAssertEqual(PreferencesReloadAction.highlightKeywords.rawValue, 1 << 3)
		XCTAssertEqual(PreferencesReloadAction.highlightLogging.rawValue, 1 << 4)
		XCTAssertEqual(PreferencesReloadAction.ircCommandCache.rawValue, 1 << 5)
		XCTAssertEqual(PreferencesReloadAction.inputHistoryScope.rawValue, 1 << 6)
		XCTAssertEqual(PreferencesReloadAction.logTranscripts.rawValue, 1 << 7)
		XCTAssertEqual(PreferencesReloadAction.memberList.rawValue, 1 << 9)
		XCTAssertEqual(PreferencesReloadAction.memberListSortOrder.rawValue, 1 << 10)
		XCTAssertEqual(PreferencesReloadAction.memberListUserBadges.rawValue, 1 << 11)
		XCTAssertEqual(PreferencesReloadAction.preferencesChanged.rawValue, 1 << 12)
		XCTAssertEqual(PreferencesReloadAction.scrollbackSaveLimit.rawValue, 1 << 13)
		XCTAssertEqual(PreferencesReloadAction.scrollbackVisibleLimit.rawValue, 1 << 14)
		XCTAssertEqual(PreferencesReloadAction.serverList.rawValue, 1 << 15)
		XCTAssertEqual(PreferencesReloadAction.serverListUnreadBadges.rawValue, 1 << 16)
		XCTAssertEqual(PreferencesReloadAction.style.rawValue, 1 << 17)
		XCTAssertEqual(PreferencesReloadAction.textDirection.rawValue, 1 << 19)
		XCTAssertEqual(PreferencesReloadAction.textFieldFontSize.rawValue, 1 << 20)
	}

	func testFileLoggerBuildsConsoleChannelAndQueryPaths() {
		let client = GLTTestClient()
		let root = "/tmp/glasstual-logs"
		let identifier = String(client.uniqueIdentifier.prefix(5))
		let clientFolder = "\(client.name.safeFilename) (\(identifier))"

		let expectedConsole = (root as NSString).appendingPathComponent(
			"/\(clientFolder)/\(TranscriptDirectory.console)/"
		)

		XCTAssertEqual(FileLogger.writePath(for: client, relativeTo: root), expectedConsole)

		let channel = makeChannel(named: "#chat", type: .channel, client: client)
		let expectedChannel = (root as NSString).appendingPathComponent(
			"/\(clientFolder)/\(TranscriptDirectory.channel)/\("#chat".safeFilename)/"
		)

		let channelTreeItem: TreeItem = channel
		XCTAssertEqual(FileLogger.writePath(for: channelTreeItem, relativeTo: root), expectedChannel)

		let query = makeChannel(named: "alice", type: .privateMessage, client: client)
		let expectedQuery = (root as NSString).appendingPathComponent(
			"/\(clientFolder)/\(TranscriptDirectory.privateMessage)/\("alice".safeFilename)/"
		)

		let queryTreeItem: TreeItem = query
		XCTAssertEqual(FileLogger.writePath(for: queryTreeItem, relativeTo: root), expectedQuery)
	}

	func testFileLoggerSkipsUtilityChannelsAndRequiresTranscriptFolder() {
		let client = GLTTestClient()
		let utility = makeChannel(named: "Utility", type: .utility, client: client)

		let utilityTreeItem: TreeItem = utility
		XCTAssertNil(FileLogger.writePath(for: utilityTreeItem, relativeTo: "/tmp/glasstual-logs"))
		XCTAssertNil(FileLogger.writePath(for: client))
	}

	func testFileLoggerWriteWithoutTranscriptFolderDoesNotOpenFile() {
		let logger = FileLogger(client: GLTTestClient())

		logger.writePlainText("should not write")

		XCTAssertNil(logger.filePath)
		XCTAssertNil(logger.writePath)
		XCTAssertNil(logger.fileName)
	}

	func testSoundFileDiscoveryMapsNamesAndPreservesLegacyCollisionBehavior() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("GlasstualSoundTests-\(UUID().uuidString)", isDirectory: true)

		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		try Data().write(to: directory.appendingPathComponent("Ping.aiff"))
		try Data().write(to: directory.appendingPathComponent("Tone.aiff"))
		try Data().write(to: directory.appendingPathComponent("Tone.wav"))

		let sounds = SoundPlayer.soundFiles(atPath: directory.path)

		XCTAssertEqual(sounds["Ping"], directory.appendingPathComponent("Ping.aiff").path)
		XCTAssertNotNil(sounds["Tone"])
		XCTAssertEqual(sounds.count, 2)
	}

	func testUniqueSoundListContainsBeepAndIsCaseInsensitivelySorted() {
		let sounds = SoundPlayer.uniqueListOfSounds()
		let sortedSounds = sounds.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }

		XCTAssertTrue(sounds.contains("Beep"))
		XCTAssertEqual(sounds, sortedSounds)
	}

	private func makeChannel(named name: String, type: ChannelType, client: IRCClient) -> Channel {
		let channel = Channel(config: ChannelConfig(channelName: name, type: type))

		channel.setValue(client, forKey: "associatedClient")

		return channel
	}
}
