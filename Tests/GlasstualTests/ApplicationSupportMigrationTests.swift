/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import XCTest

final class ApplicationSupportMigrationTests: XCTestCase {
	func testApplicationMetadataMatchesMainBundle() {
		let bundle = Bundle.main

		XCTAssertEqual(
			TPCApplicationInfo.applicationName(),
			bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
		)
		XCTAssertEqual(
			TPCApplicationInfo.applicationVersion(),
			bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
		)
		XCTAssertEqual(
			TPCApplicationInfo.applicationVersionShort(),
			bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
		)
		XCTAssertEqual(TPCApplicationInfo.applicationBundleIdentifier(), bundle.bundleIdentifier)
		XCTAssertEqual(
			TPCApplicationInfo.applicationInfoPlist() as NSDictionary,
			bundle.infoDictionary as NSDictionary?
		)
	}

	func testApplicationRuntimeMetadataIsSane() {
		XCTAssertGreaterThan(TPCApplicationInfo.applicationProcessID(), 0)
		XCTAssertGreaterThanOrEqual(TPCApplicationInfo.timeIntervalSinceApplicationLaunch(), 0)
		XCTAssertEqual(TPCApplicationInfo.applicationBirthday(), 1_279_871_580)
		XCTAssertFalse(TPCApplicationInfo.applicationNameWithoutVersion().isEmpty)
	}

	func testPathInfoExposesBundleAndBundledResourceLocations() {
		let bundle = Bundle.main

		XCTAssertEqual(TPCPathInfo.applicationBundle, bundle.bundlePath)
		XCTAssertEqual(TPCPathInfo.applicationBundleURL, bundle.bundleURL)
		XCTAssertEqual(TPCPathInfo.applicationResources, bundle.resourcePath)
		XCTAssertEqual(TPCPathInfo.applicationResourcesURL, bundle.resourceURL)
		XCTAssertTrue(TPCPathInfo.bundledExtensions.hasSuffix("Bundled Extensions"))
		XCTAssertTrue(TPCPathInfo.bundledScripts.hasSuffix("Bundled Scripts"))
		XCTAssertTrue(TPCPathInfo.bundledThemes.hasSuffix("Bundled Styles"))
		XCTAssertEqual(TPCPathInfo.systemDiagnosticReports, "/Library/Logs/DiagnosticReports")
		XCTAssertFalse(TPCPathInfo.userHome.isEmpty)
	}

	func testPathInfoCreatesTemporaryDirectoryAndExplicitDirectoryHelper() throws {
		let temporaryPath = TPCPathInfo.applicationTemporary
		var isDirectory = ObjCBool(false)

		XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryPath, isDirectory: &isDirectory))
		XCTAssertTrue(isDirectory.boolValue)
		XCTAssertTrue(temporaryPath.contains(Bundle.main.bundleIdentifier ?? ""))

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("GlasstualPathTests-\(UUID().uuidString)", isDirectory: true)

		XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

		TPCPathInfo._createDirectory(at: directory)

		XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
		try FileManager.default.removeItem(at: directory)
		XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
	}

	func testResourceManagerLoadsKnownPropertyLists() {
		let networks = TPCResourceManager.dictionary(fromResources: "IRCNetworks", cacheValue: false)
		let networkList = TPCResourceManager.array(fromResources: "IRCNetworks", cacheValue: false)
		let staticStore = TPCResourceManager.dictionary(fromResources: "StaticStore")

		XCTAssertTrue(networks != nil || networkList != nil)
		XCTAssertNotNil(staticStore)
		XCTAssertGreaterThan(staticStore?.count ?? 0, 0)
	}

	func testResourceManagerCachesAndRejectsWrongTypes() {
		TPCResourceManager.sharedResourcesCache.removeAllObjects()

		let first = TPCResourceManager.dictionary(fromResources: "StaticStore", cacheValue: true)
		let second = TPCResourceManager.dictionary(fromResources: "StaticStore", cacheValue: true)
		let cacheKey = "StaticStore.plist / Root Folder / Root Object" as NSString

		XCTAssertNotNil(first)
		XCTAssertEqual(first as NSDictionary?, second as NSDictionary?)
		XCTAssertNotNil(TPCResourceManager.sharedResourcesCache.object(forKey: cacheKey))
		XCTAssertEqual(
			TPCResourceManager.sharedResourcesCache.object(forKey: cacheKey) as? NSDictionary,
			first as NSDictionary?
		)
		XCTAssertNil(TPCResourceManager.array(fromResources: "StaticStore", cacheValue: false))
		XCTAssertNil(TPCResourceManager.dictionary(fromResources: "DoesNotExistAnywhere", cacheValue: false))
	}

	func testResourceManagerDocumentTypeConstants() {
		XCTAssertEqual(TPCResourceManagerBundleDocumentTypeExtension, ".bundle")
		XCTAssertEqual(TPCResourceManagerBundleDocumentTypeExtensionWithoutPeriod, "bundle")
		XCTAssertEqual(TPCResourceManagerScriptDocumentTypeExtension, ".scpt")
		XCTAssertEqual(TPCResourceManagerScriptDocumentTypeExtensionWithoutPeriod, "scpt")
	}

	func testFileLoggerBuildsConsoleChannelAndQueryPaths() {
		let client = GLTTestClient()
		let root = "/tmp/glasstual-logs"
		let identifier = String(client.uniqueIdentifier.prefix(5))
		let clientFolder = "\(client.name.safeFilename) (\(identifier))"

		let expectedConsole = (root as NSString).appendingPathComponent(
			"/\(clientFolder)/\(TLOFileLoggerConsoleDirectoryName)/"
		)

		XCTAssertEqual(TLOFileLogger.writePath(for: client, relativeTo: root), expectedConsole)

		let channel = makeChannel(named: "#chat", type: .channel, client: client)
		let expectedChannel = (root as NSString).appendingPathComponent(
			"/\(clientFolder)/\(TLOFileLoggerChannelDirectoryName)/\("#chat".safeFilename)/"
		)

		XCTAssertEqual(TLOFileLogger.writePath(for: channel, relativeTo: root), expectedChannel)

		let query = makeChannel(named: "alice", type: .privateMessage, client: client)
		let expectedQuery = (root as NSString).appendingPathComponent(
			"/\(clientFolder)/\(TLOFileLoggerPrivateMessageDirectoryName)/\("alice".safeFilename)/"
		)

		XCTAssertEqual(TLOFileLogger.writePath(for: query, relativeTo: root), expectedQuery)
	}

	func testFileLoggerSkipsUtilityChannelsAndRequiresTranscriptFolder() {
		let client = GLTTestClient()
		let utility = makeChannel(named: "Utility", type: .utility, client: client)

		XCTAssertNil(TLOFileLogger.writePath(for: utility, relativeTo: "/tmp/glasstual-logs"))
		XCTAssertNil(TLOFileLogger.writePath(for: client))
	}

	func testFileLoggerWriteWithoutTranscriptFolderDoesNotOpenFile() {
		let logger = TLOFileLogger(client: GLTTestClient())

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

		let sounds = TLOSoundPlayer.soundFiles(atPath: directory.path)

		XCTAssertEqual(sounds["Ping"], directory.appendingPathComponent("Ping.aiff").path)
		XCTAssertNotNil(sounds["Tone"])
		XCTAssertEqual(sounds.count, 2)
	}

	func testUniqueSoundListContainsBeepAndIsCaseInsensitivelySorted() {
		let sounds = TLOSoundPlayer.uniqueListOfSounds()
		let sortedSounds = sounds.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }

		XCTAssertTrue(sounds.contains("Beep"))
		XCTAssertEqual(sounds, sortedSounds)
	}

	private func makeChannel(named name: String, type: IRCChannelType, client: IRCClient) -> IRCChannel {
		let channel = IRCChannel(configDictionary: [
			"channelName": name,
			"channelType": type.rawValue,
		])

		channel.setValue(client, forKey: "associatedClient")

		return channel
	}
}
