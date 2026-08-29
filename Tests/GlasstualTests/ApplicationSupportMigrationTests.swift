/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

@MainActor
@Suite("Application support metadata, paths and resources", .serialized)
struct ApplicationSupportMigrationTests {
	@Test("Application metadata is read straight out of the main bundle")
	func applicationMetadataMatchesMainBundle() {
		let bundle = Bundle.main

		#expect(ApplicationInfo.applicationName() == bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
		#expect(
			ApplicationInfo.applicationVersion() == bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
		)
		#expect(
			ApplicationInfo.applicationVersionShort()
				== bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
		)
		#expect(ApplicationInfo.applicationBundleIdentifier() == bundle.bundleIdentifier)
		#expect(ApplicationInfo.applicationInfoPlist() as NSDictionary == bundle.infoDictionary as NSDictionary?)
	}

	@Test("The process metadata describes a running application")
	func applicationRuntimeMetadataIsSane() {
		#expect(ApplicationInfo.applicationProcessID() > 0)
		#expect(ApplicationInfo.timeIntervalSinceApplicationLaunch() >= 0)
		#expect(ApplicationInfo.applicationBirthday() == 1_279_871_580)
		#expect(ApplicationInfo.applicationNameWithoutVersion().isEmpty == false)
	}

	@Test("Bundle and bundled resource locations point into the main bundle")
	func pathInfoExposesBundleAndBundledResourceLocations() {
		let bundle = Bundle.main

		#expect(PathInfo.applicationBundle == bundle.bundlePath)
		#expect(PathInfo.applicationBundleURL == bundle.bundleURL)
		#expect(PathInfo.applicationResources == bundle.resourcePath)
		#expect(PathInfo.applicationResourcesURL == bundle.resourceURL)
		#expect(PathInfo.bundledExtensions.hasSuffix("Bundled Extensions"))
		#expect(PathInfo.bundledScripts.hasSuffix("Bundled Scripts"))
		#expect(PathInfo.bundledThemes.hasSuffix("Bundled Styles"))
		#expect(PathInfo.systemDiagnosticReports == "/Library/Logs/DiagnosticReports")
		#expect(PathInfo.userHome.isEmpty == false)
	}

	@Test("The temporary directory is created on demand, and so is an explicitly named one")
	func pathInfoCreatesTemporaryDirectoryAndExplicitDirectoryHelper() throws {
		let temporaryPath = PathInfo.applicationTemporary
		var isDirectory = ObjCBool(false)
		let temporaryExists = FileManager.default.fileExists(atPath: temporaryPath, isDirectory: &isDirectory)

		#expect(temporaryExists)
		#expect(isDirectory.boolValue)
		#expect(temporaryPath.contains(Bundle.main.bundleIdentifier ?? ""))

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("GlasstualPathTests-\(UUID().uuidString)", isDirectory: true)

		#expect(FileManager.default.fileExists(atPath: directory.path) == false)

		PathInfo.createDirectory(at: directory)

		#expect(FileManager.default.fileExists(atPath: directory.path))
		try FileManager.default.removeItem(at: directory)
		#expect(FileManager.default.fileExists(atPath: directory.path) == false)
	}

	@Test("The bundled property lists load through the resource manager")
	func resourceManagerLoadsKnownPropertyLists() {
		let networks = ResourceManager.dictionary(fromResources: "IRCNetworks", cacheValue: false)
		let networkList = ResourceManager.array(fromResources: "IRCNetworks", cacheValue: false)
		let staticStore = ResourceManager.dictionary(fromResources: "StaticStore")

		#expect(networks != nil || networkList != nil)
		#expect(staticStore != nil)
		#expect((staticStore?.count ?? 0) > 0)
	}

	@Test("A cached resource is served from the cache, and the wrong type reads as nothing")
	func resourceManagerCachesAndRejectsWrongTypes() {
		/* The cache is process-wide; empty it on the way out as well so the
		 entry this test plants does not answer another one's lookup. */
		ResourceManager.removeAllCachedResources()
		defer { ResourceManager.removeAllCachedResources() }

		let first = ResourceManager.dictionary(fromResources: "StaticStore", cacheValue: true)
		let second = ResourceManager.dictionary(fromResources: "StaticStore", cacheValue: true)

		#expect(first != nil)
		#expect(first as NSDictionary? == second as NSDictionary?)
		#expect(ResourceManager.hasCachedResource(named: "StaticStore"))
		#expect(ResourceManager.array(fromResources: "StaticStore", cacheValue: false) == nil)
		#expect(ResourceManager.dictionary(fromResources: "DoesNotExistAnywhere", cacheValue: false) == nil)
		#expect(ResourceManager.hasCachedResource(named: "DoesNotExistAnywhere") == false)
	}

	@Test("A transcript path is built from the client folder and the item's kind")
	func fileLoggerBuildsConsoleChannelAndQueryPaths() {
		let client = GLTTestClient()
		let root = "/tmp/glasstual-logs"
		let identifier = String(client.uniqueIdentifier.prefix(5))
		let clientFolder = "\(client.name.safeFilename) (\(identifier))"

		let expectedConsole = (root as NSString).appendingPathComponent(
			"/\(clientFolder)/\(TranscriptDirectory.console)/"
		)

		#expect(FileLogger.writePath(for: client, relativeTo: root) == expectedConsole)

		let channel = makeChannel(named: "#chat", type: .channel, client: client)
		let expectedChannel = (root as NSString).appendingPathComponent(
			"/\(clientFolder)/\(TranscriptDirectory.channel)/\("#chat".safeFilename)/"
		)

		let channelTreeItem: TreeItem = channel
		#expect(FileLogger.writePath(for: channelTreeItem, relativeTo: root) == expectedChannel)

		let query = makeChannel(named: "alice", type: .privateMessage, client: client)
		let expectedQuery = (root as NSString).appendingPathComponent(
			"/\(clientFolder)/\(TranscriptDirectory.privateMessage)/\("alice".safeFilename)/"
		)

		let queryTreeItem: TreeItem = query
		#expect(FileLogger.writePath(for: queryTreeItem, relativeTo: root) == expectedQuery)
	}

	@Test("A utility channel has no transcript path, and neither has a client without a folder")
	func fileLoggerSkipsUtilityChannelsAndRequiresTranscriptFolder() {
		let client = GLTTestClient()
		let utility = makeChannel(named: "Utility", type: .utility, client: client)

		let utilityTreeItem: TreeItem = utility
		#expect(FileLogger.writePath(for: utilityTreeItem, relativeTo: "/tmp/glasstual-logs") == nil)
		#expect(FileLogger.writePath(for: client) == nil)
	}

	@Test("Writing without a transcript folder opens no file")
	func fileLoggerWriteWithoutTranscriptFolderDoesNotOpenFile() {
		let logger = FileLogger(client: GLTTestClient())

		logger.writePlainText("should not write")

		#expect(logger.filePath == nil)
		#expect(logger.writePath == nil)
		#expect(logger.fileName == nil)
	}

	@Test("Sounds are keyed by name, and a name claimed twice keeps one file")
	func soundFileDiscoveryMapsNamesAndPreservesLegacyCollisionBehavior() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("GlasstualSoundTests-\(UUID().uuidString)", isDirectory: true)

		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		try Data().write(to: directory.appendingPathComponent("Ping.aiff"))
		try Data().write(to: directory.appendingPathComponent("Tone.aiff"))
		try Data().write(to: directory.appendingPathComponent("Tone.wav"))

		let sounds = SoundPlayer.soundFiles(atPath: directory.path)

		#expect(sounds["Ping"] == directory.appendingPathComponent("Ping.aiff").path)
		#expect(sounds["Tone"] != nil)
		#expect(sounds.count == 2)
	}

	@Test("The list offered to the user contains Beep and is sorted ignoring case")
	func uniqueSoundListContainsBeepAndIsCaseInsensitivelySorted() {
		let sounds = SoundPlayer.uniqueListOfSounds()
		let sortedSounds = sounds.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }

		#expect(sounds.contains("Beep"))
		#expect(sounds == sortedSounds)
	}

	private func makeChannel(named name: String, type: ChannelType, client: IRCClient) -> Channel {
		let channel = Channel(config: ChannelConfig(channelName: name, type: type))

		channel.associatedClient = client

		return channel
	}
}
