/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import os
import Synchronization

/// Where the application keeps its files. Every accessor here creates the
/// directory it names, so callers can write into it straight away.
public nonisolated enum PathInfo { // nonisolated: value
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "PathInfo"
	)

	private static let transcriptBookmarkDefaultsKey = "LogTranscriptDestinationSecurityBookmark_5"

	/** The security-scoped transcript folder, held open for as long as the
	 process is using it. Main-actor state: every caller -- the preferences pane
	 that picks the folder, the file logger that writes into it, the menu item
	 that opens it -- is already there. */
	@MainActor
	private static var transcriptFolderURLStorage: URL?

	/** Directories this process has already created. Several of the path
	 accessors below are read on hot paths — the transcript folder is asked for
	 on every log line — and each one used to hit `fileExists` before answering.
	 The set is checked instead; a directory removed underneath a running
	 application is not a case any of these callers recover from anyway. */
	private static let ensuredDirectories = Mutex<Set<URL>>([])

	private static var fileManager: FileManager {
		.default
	}

	private static var productIdentifier: String {
		ApplicationInfo.applicationBundleIdentifier()
	}

	// MARK: - Directory creation

	public static func createDirectory(atPath directoryPath: String) {
		createDirectory(at: URL(fileURLWithPath: directoryPath, isDirectory: true))
	}

	public static func createDirectory(at directoryURL: URL) {
		let alreadyEnsured = ensuredDirectories.withLock { ensured in
			ensured.insert(directoryURL).inserted == false
		}

		if alreadyEnsured {
			return
		}

		if fileManager.fileExists(at: directoryURL) {
			return
		}

		do {
			try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
		} catch {
			logger.error(
				"Failed to create directory at path: '\(displayPath(for: directoryURL), privacy: .public)' - \(error.localizedDescription, privacy: .public)"
			)
		}
	}

	// MARK: - Application Specific

	public static var applicationBundle: String {
		Bundle.main.bundlePath
	}

	public static var applicationBundleURL: URL {
		Bundle.main.bundleURL
	}

	public static var applicationResources: String {
		Bundle.main.resourcePath ?? ""
	}

	public static var applicationResourcesURL: URL {
		Bundle.main.resourceURL ?? Bundle.main.bundleURL
	}

	public static var applicationCaches: String? {
		guard
			var basePath = firstSearchPath(
				for: .cachesDirectory,
				appending: "/\(productIdentifier)/"
			)
		else {
			return nil
		}

		basePath = applyUIReviewDirectory(toPath: basePath)
		createDirectory(atPath: basePath)

		return basePath
	}

	public static var applicationCachesURL: URL? {
		fileURL(forPath: applicationCaches)
	}

	public static var groupContainer: String? {
		groupContainerURL?.path
	}

	public static var groupContainerURL: URL? {
		guard
			var baseURL = fileManager.containerURL(
				forSecurityApplicationGroupIdentifier: ApplicationGroup.identifier
			)
		else {
			return nil
		}

		#if DEBUG
			if let reviewDirectory = uiReviewDirectoryName {
				baseURL =
					baseURL
						.appendingPathComponent("UI Reviews", isDirectory: true)
						.appendingPathComponent(reviewDirectory, isDirectory: true)
				createDirectory(at: baseURL)
			}
		#endif

		return baseURL
	}

	public static var groupContainerApplicationCaches: String? {
		groupContainerApplicationCachesURL?.path
	}

	public static var groupContainerApplicationCachesURL: URL? {
		guard let sourceURL = groupContainerURL else {
			return nil
		}

		let baseURL = sourceURL.appendingPathComponent("/Library/Caches/")
		createDirectory(at: baseURL)

		return baseURL
	}

	public static var applicationSupport: String? {
		guard
			var basePath = firstSearchPath(
				for: .applicationSupportDirectory,
				appending: "/Glasstual/"
			)
		else {
			return nil
		}

		basePath = applyUIReviewDirectory(toPath: basePath)
		createDirectory(atPath: basePath)

		return basePath
	}

	public static var applicationSupportURL: URL? {
		fileURL(forPath: applicationSupport)
	}

	public static var groupContainerApplicationSupport: String? {
		groupContainerApplicationSupportURL?.path
	}

	public static var groupContainerApplicationSupportURL: URL? {
		guard let sourceURL = groupContainerURL else {
			return nil
		}

		let baseURL = sourceURL.appendingPathComponent("/Library/Application Support/Glasstual/")
		createDirectory(at: baseURL)

		return baseURL
	}

	public static var applicationLogs: String? {
		guard
			var basePath = firstSearchPath(
				for: .libraryDirectory,
				appending: "/Logs/\(productIdentifier)/"
			)
		else {
			return nil
		}

		basePath = applyUIReviewDirectory(toPath: basePath)
		createDirectory(atPath: basePath)

		return basePath
	}

	public static var applicationLogsURL: URL? {
		fileURL(forPath: applicationLogs)
	}

	public static var applicationTemporary: String {
		let basePath = (NSTemporaryDirectory() as NSString)
			.appendingPathComponent("/\(productIdentifier)/")

		createDirectory(atPath: basePath)

		return basePath
	}

	public static var applicationTemporaryURL: URL {
		URL(fileURLWithPath: applicationTemporary, isDirectory: true)
	}

	public static var applicationTemporaryProcessSpecific: String {
		let processIdentifier = ProcessInfo.processInfo.processIdentifier
		let basePath = (applicationTemporary as NSString)
			.appendingPathComponent("/tmp-\(processIdentifier)")

		createDirectory(atPath: basePath)

		return basePath
	}

	public static var applicationTemporaryProcessSpecificURL: URL {
		URL(fileURLWithPath: applicationTemporaryProcessSpecific, isDirectory: true)
	}

	public static var bundledExtensions: String {
		bundledExtensionsURL.path
	}

	public static var bundledExtensionsURL: URL {
		applicationResourcesURL.appendingPathComponent("/Bundled Extensions/")
	}

	public static var bundledScripts: String {
		bundledScriptsURL.path
	}

	public static var bundledScriptsURL: URL {
		applicationResourcesURL.appendingPathComponent("/Bundled Scripts/")
	}

	public static var customExtensions: String? {
		customExtensionsURL?.path
	}

	public static var customExtensionsURL: URL? {
		guard let sourceURL = groupContainerApplicationSupportURL else {
			return nil
		}

		let baseURL = sourceURL.appendingPathComponent("/Extensions/")
		createDirectory(at: baseURL)

		return baseURL
	}

	public static var customScripts: String? {
		#if DEBUG
			if ProcessInfo.processInfo.environment["GLASSTUAL_UI_REVIEW_DIRECTORY"] != nil,
			   let supportURL = groupContainerApplicationSupportURL
			{
				let baseURL = supportURL.appendingPathComponent("Scripts", isDirectory: true)
				createDirectory(at: baseURL)

				return baseURL.path
			}
		#endif

		return firstSearchPath(for: .applicationScriptsDirectory)
	}

	public static var customScriptsURL: URL? {
		fileURL(forPath: customScripts)
	}

	// MARK: - System Specific

	public static var systemApplications: String? {
		firstSearchPath(for: .applicationDirectory, in: .systemDomainMask)
	}

	public static var systemApplicationsURL: URL? {
		fileURL(forPath: systemApplications)
	}

	public static var systemDiagnosticReports: String {
		"/Library/Logs/DiagnosticReports"
	}

	public static var systemDiagnosticReportsURL: URL {
		URL(fileURLWithPath: systemDiagnosticReports, isDirectory: true)
	}

	// MARK: - User Specific

	public static var userApplicationScripts: String? {
		userApplicationScriptsURL?.path
	}

	public static var userApplicationScriptsURL: URL? {
		customScriptsURL?.deletingLastPathComponent()
	}

	public static var userDiagnosticReports: String {
		userDiagnosticReportsURL.path
	}

	public static var userDiagnosticReportsURL: URL {
		userHomeURL.appendingPathComponent("/Library/Logs/DiagnosticReports")
	}

	public static var userDownloads: String? {
		firstSearchPath(for: .downloadsDirectory)
	}

	public static var userDownloadsURL: URL? {
		fileURL(forPath: userDownloads)
	}

	public static var userHome: String {
		FileManager.pathOfHomeDirectoryOutsideSandbox
	}

	public static var userHomeURL: URL {
		FileManager.URLOfHomeDirectoryOutsideSandbox
	}

	public static var userPreferences: String? {
		firstSearchPath(for: .libraryDirectory, appending: "/Preferences/")
	}

	public static var userPreferencesURL: URL? {
		fileURL(forPath: userPreferences)
	}

	// MARK: - Transcript folder

	@MainActor
	public static var transcriptFolder: String? {
		transcriptFolderURL?.path
	}

	@MainActor
	public static var transcriptFolderURL: URL? {
		transcriptFolderURLStorage
	}

	@MainActor
	public static func setTranscriptFolderURL(_ transcriptFolderURL: Data?) {
		stopUsingTranscriptFolderURL()

		TextualUserDefaults.container.set(transcriptFolderURL, forKey: transcriptBookmarkDefaultsKey)
		startUsingTranscriptFolderURL()
	}

	@MainActor
	public static func startUsingTranscriptFolderURL() {
		startUsingTranscriptFolderURL(refreshingStaleBookmark: true)
	}

	@MainActor
	public static func stopUsingTranscriptFolderURL() {
		let existingURL = transcriptFolderURLStorage
		transcriptFolderURLStorage = nil

		existingURL?.stopAccessingSecurityScopedResource()
	}

	@MainActor
	private static func startUsingTranscriptFolderURL(refreshingStaleBookmark: Bool) {
		/* Security-scoped access is reference counted, so any previous access has to be
		 released before a new one is taken; launch plus a preference reload both call in. */
		stopUsingTranscriptFolderURL()

		guard let bookmark = TextualUserDefaults.container.data(forKey: transcriptBookmarkDefaultsKey) else {
			return
		}

		var resolvedBookmarkIsStale = true
		let resolvedBookmark: URL

		do {
			resolvedBookmark = try URL(
				resolvingBookmarkData: bookmark,
				options: .withSecurityScope,
				relativeTo: nil,
				bookmarkDataIsStale: &resolvedBookmarkIsStale
			)
		} catch {
			logger.error("Error resolving bookmark for URL: \(error.localizedDescription, privacy: .public)")
			warnUserAboutStaleTranscriptFolderURL()

			return
		}

		if resolvedBookmarkIsStale {
			/* A refreshed bookmark that also resolves stale must not recurse. */
			guard refreshingStaleBookmark else {
				warnUserAboutStaleTranscriptFolderURL()

				return
			}

			var newBookmark: Data?

			if resolvedBookmark.startAccessingSecurityScopedResource() {
				newBookmark = try? resolvedBookmark.bookmarkData(
					options: .withSecurityScope,
					includingResourceValuesForKeys: nil,
					relativeTo: nil
				)
				resolvedBookmark.stopAccessingSecurityScopedResource()
			}

			guard let newBookmark else {
				warnUserAboutStaleTranscriptFolderURL()

				return
			}

			TextualUserDefaults.container.set(newBookmark, forKey: transcriptBookmarkDefaultsKey)
			startUsingTranscriptFolderURL(refreshingStaleBookmark: false)

			return
		}

		/* Record the URL only once access succeeded so that a later stop stays balanced. */
		guard resolvedBookmark.startAccessingSecurityScopedResource() else {
			logger.error("Failed to access bookmark")

			return
		}

		transcriptFolderURLStorage = resolvedBookmark
	}

	// MARK: - Helpers

	@MainActor
	private static func warnUserAboutStaleTranscriptFolderURL() {
		guard Preferences.Logging.logToDisk.value else {
			return
		}

		TDCAlert.alert(
			withMessage: PromptStrings.Logging.staleLocationBody,
			title: PromptStrings.Logging.staleLocationTitle,
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil
		)
	}

	private static func firstSearchPath(
		for directory: FileManager.SearchPathDirectory,
		in domainMask: FileManager.SearchPathDomainMask = .userDomainMask,
		appending suffix: String? = nil
	) -> String? {
		guard let firstURL = FileManager.default.urls(for: directory, in: domainMask).first else {
			return nil
		}
		let firstPath = firstURL.path

		guard let suffix else {
			return firstPath
		}

		return (firstPath as NSString).appendingPathComponent(suffix)
	}

	private static func fileURL(forPath path: String?) -> URL? {
		guard let path else {
			return nil
		}

		return URL(fileURLWithPath: path, isDirectory: true)
	}

	private static func displayPath(for url: URL) -> String {
		url.standardizedTildePath ?? url.path
	}

	private static func applyUIReviewDirectory(toPath basePath: String) -> String {
		#if DEBUG
			guard let reviewDirectory = uiReviewDirectoryName else {
				return basePath
			}

			return ((basePath as NSString).appendingPathComponent("UI Reviews") as NSString)
				.appendingPathComponent(reviewDirectory)
		#else
			return basePath
		#endif
	}

	#if DEBUG
		private static var uiReviewDirectoryName: String? {
			let reviewDirectory = ProcessInfo.processInfo.environment["GLASSTUAL_UI_REVIEW_DIRECTORY"] ?? ""

			guard reviewDirectory.isEmpty == false else {
				return nil
			}

			return (reviewDirectory as NSString).lastPathComponent
		}
	#endif
}
