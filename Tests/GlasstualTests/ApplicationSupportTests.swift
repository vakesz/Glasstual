// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Application support metadata, paths and resources", .serialized)
struct ApplicationSupportTests {
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
		#expect(
			ApplicationInfo.applicationInfoPlist().propertyListObject as NSDictionary
				== bundle.infoDictionary as NSDictionary?
		)
	}

	@Test("The process metadata describes a running application")
	func applicationRuntimeMetadataIsSane() {
		#expect(ApplicationInfo.applicationProcessID() > 0)
		#expect(ApplicationInfo.timeIntervalSinceApplicationLaunch() >= 0)
		#expect(ApplicationInfo.applicationBirthday() == 1_279_871_580)
		#expect(ApplicationInfo.applicationName().isEmpty == false)
	}

	@Test("Bundle and bundled resource locations point into the main bundle")
	func applicationPathsExposeBundleAndBundledResourceLocations() {
		let bundle = Bundle.main

		#expect(ApplicationPaths.applicationBundleURL == bundle.bundleURL)
		#expect(ApplicationPaths.applicationResourcesURL == bundle.resourceURL)
		#expect(ApplicationPaths.bundledScriptsURL.path.hasSuffix("Bundled Scripts"))
		#expect(ApplicationPaths.systemDiagnosticReportsURL.path == "/Library/Logs/DiagnosticReports")
	}

	@Test("The temporary directory is created on demand, and so is an explicitly named one")
	func applicationPathsCreateTemporaryDirectoryAndExplicitDirectory() throws {
		let temporaryURL = ApplicationPaths.applicationTemporaryURL
		var isDirectory = ObjCBool(false)
		let temporaryExists = FileManager.default.fileExists(atPath: temporaryURL.path, isDirectory: &isDirectory)

		#expect(temporaryExists)
		#expect(isDirectory.boolValue)
		#expect(temporaryURL.path.contains(Bundle.main.bundleIdentifier ?? ""))

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("GlasstualPathTests-\(UUID().uuidString)", isDirectory: true)

		#expect(FileManager.default.fileExists(atPath: directory.path) == false)

		ApplicationPaths.createDirectory(at: directory)

		#expect(FileManager.default.fileExists(atPath: directory.path))
		try FileManager.default.removeItem(at: directory)
		#expect(FileManager.default.fileExists(atPath: directory.path) == false)
	}

	/// The path used to be recorded as ensured before the creation was even
	/// attempted, so a directory that failed once was never tried again.
	@Test("A directory that could not be created is created on the next call")
	func applicationPathsRetryADirectoryTheyCouldNotCreate() throws {
		let fileManager = FileManager.default
		let blocker = fileManager.temporaryDirectory
			.appendingPathComponent("GlasstualPathTests-\(UUID().uuidString)", isDirectory: false)
		let directory = blocker.appendingPathComponent("directory", isDirectory: true)
		defer { try? fileManager.removeItem(at: blocker) }

		/* A directory cannot be made inside a regular file. */
		try Data().write(to: blocker)

		ApplicationPaths.createDirectory(at: directory)

		#expect(fileManager.fileExists(atPath: directory.path) == false)

		try fileManager.removeItem(at: blocker)

		ApplicationPaths.createDirectory(at: directory)

		#expect(fileManager.fileExists(atPath: directory.path))
	}

	@Test("The bundled property lists load through the resource manager")
	func resourceManagerLoadsKnownPropertyLists() {
		let networks = BundleResources.dictionary(fromResources: "IRCNetworks", cacheValue: false)
		let networkList = BundleResources.array(fromResources: "IRCNetworks", cacheValue: false)
		let staticStore = BundleResources.dictionary(fromResources: "StaticStore")

		#expect(networks != nil || networkList != nil)
		#expect(staticStore != nil)
		#expect((staticStore?.count ?? 0) > 0)
	}

	@Test("A cached resource is served from the cache, and the wrong type reads as nothing")
	func resourceManagerCachesAndRejectsWrongTypes() {
		/* The cache is process-wide; empty it on the way out as well so the
		 entry this test plants does not answer another one's lookup. */
		BundleResources.removeAllCachedResources()
		defer { BundleResources.removeAllCachedResources() }

		let first = BundleResources.dictionary(fromResources: "StaticStore", cacheValue: true)
		let second = BundleResources.dictionary(fromResources: "StaticStore", cacheValue: true)

		#expect(first != nil)
		#expect(first as NSDictionary? == second as NSDictionary?)
		#expect(BundleResources.hasCachedResource(named: "StaticStore"))
		#expect(BundleResources.array(fromResources: "StaticStore", cacheValue: false) == nil)
		#expect(BundleResources.dictionary(fromResources: "DoesNotExistAnywhere", cacheValue: false) == nil)
		#expect(BundleResources.hasCachedResource(named: "DoesNotExistAnywhere") == false)
	}

	@Test("A transcript path is built from the client folder and the item's kind")
	func fileLoggerBuildsConsoleChannelAndQueryPaths() {
		let client = TestClient()
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

		let channelTreeItem: ChatItem = channel
		#expect(FileLogger.writePath(for: channelTreeItem, relativeTo: root) == expectedChannel)

		let query = makeChannel(named: "alice", type: .privateMessage, client: client)
		let expectedQuery = (root as NSString).appendingPathComponent(
			"/\(clientFolder)/\(TranscriptDirectory.privateMessage)/\("alice".safeFilename)/"
		)

		let queryTreeItem: ChatItem = query
		#expect(FileLogger.writePath(for: queryTreeItem, relativeTo: root) == expectedQuery)
	}

	@Test("A utility channel has no transcript path, and neither has a client without a folder")
	func fileLoggerSkipsUtilityChannelsAndRequiresTranscriptFolder() {
		let client = TestClient()
		let utility = makeChannel(named: "Utility", type: .utility, client: client)

		let utilityTreeItem: ChatItem = utility
		#expect(FileLogger.writePath(for: utilityTreeItem, relativeTo: "/tmp/glasstual-logs") == nil)
		#expect(FileLogger.writePath(for: client) == nil)
	}

	@Test("Writing without a transcript folder opens no file")
	func fileLoggerWriteWithoutTranscriptFolderDoesNotOpenFile() async {
		let sink = RecordingFileLogSink()
		let commands = FileLogCommands(sink: FileLogSinkPort { await sink.process($0) })
		let client = TestClient()
		let logger = FileLogger(client: client, commands: commands)

		logger.writePlainText("should not write")

		#expect(await commands.flush())
		#expect(await sink.operations == [.flush])
		withExtendedLifetime(logger) {}
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
		/* A Sounds folder holds more than sounds. None of these may reach the
		 picker as a sound that plays nothing. */
		try Data().write(to: directory.appendingPathComponent(".DS_Store"))
		try Data().write(to: directory.appendingPathComponent(".Hidden.aiff"))
		try Data().write(to: directory.appendingPathComponent("Read Me.txt"))
		try FileManager.default.createDirectory(
			at: directory.appendingPathComponent("Folder", isDirectory: true),
			withIntermediateDirectories: false
		)

		let sounds = SoundPlayer.soundFiles(atPath: directory.path)

		#expect(sounds["Ping"] == directory.appendingPathComponent("Ping.aiff").path)
		#expect(sounds["Tone"] != nil)
		#expect(sounds.count == 2)
	}

	@Test("The list offered to the user contains Beep and is sorted ignoring case")
	func uniqueSoundListContainsBeepAndIsCaseInsensitivelySorted() {
		let sounds = SoundPlayer.availableSoundNames
		let sortedSounds = sounds.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }

		#expect(sounds.contains("Beep"))
		#expect(sounds == sortedSounds)
	}

	/** The launch count is read back out of the defaults suite before it is
	 raised, so a value a hand-edited entry can carry has to survive the
	 increment. The declaration's bound is what keeps one out of the suite in the
	 first place, and the count is read back as an `Int`. */
	@Test("The launch count survives a stored value no count could reach")
	func launchCountSaturatesAndIsBounded() {
		let stored = Preferences.Internals.runCount.value
		defer { Preferences.Internals.runCount.value = stored }

		Preferences.Internals.runCount.value = .max
		ApplicationInfo.incrementApplicationRunCount()

		#expect(ApplicationInfo.applicationRunCount() == .max)

		Preferences.Internals.runCount.value = 41
		ApplicationInfo.incrementApplicationRunCount()

		#expect(ApplicationInfo.applicationRunCount() == 42)
		#expect(Preferences.Internals.runCount.coerce(.integer(Int(Int32.max))) != nil)
		#expect(Preferences.Internals.runCount.coerce(.string("\(UInt.max)")) == nil)
	}

	/** A transcript row carries a date read back off disk, and one that is not a
	 moment `localtime_r` can name would trap on the narrowing to `time_t`.
	 An unformattable stamp reads as no stamp, which is what callers expect. */
	@Test(
		"A stored date that is not a moment formats as nothing rather than trapping",
		arguments: [Double.nan, .infinity, -.infinity, 1e300, -1e300] as [TimeInterval]
	)
	func storedDatesThatAreNotMomentsFormatAsNothing(_ seconds: TimeInterval) {
		let date = Date(timeIntervalSince1970: seconds)

		#expect(DateFormatting.timestamp(date, format: "[%H:%M:%S]") == nil)
	}

	@Test("A stored date that is a moment still formats")
	func storedDatesThatAreMomentsStillFormat() throws {
		let date = Date(timeIntervalSince1970: 1_709_641_800)
		let formatted = try #require(DateFormatting.timestamp(date, format: "[%H:%M:%S]"))

		#expect(formatted.hasPrefix("["))
		#expect(formatted.hasSuffix("]"))
	}

	private func makeChannel(named name: String, type: ChannelType, client: Client) -> Channel {
		let channel = Channel(config: ChannelConfig(channelName: name, type: type))

		channel.associatedClient = client

		return channel
	}
}
