/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import os

@objc(TPCPathInfo)
public final class PathInfo: NSObject {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "PathInfo"
	)

	private static let transcriptBookmarkDefaultsKey = "LogTranscriptDestinationSecurityBookmark_5"
	private static let transcriptLock = NSLock()
	private nonisolated(unsafe) static var storedTranscriptFolderURL: URL?

	private static var fileManager: FileManager {
		.default
	}

	private static var productIdentifier: String {
		ApplicationInfo.applicationBundleIdentifier()
	}

	// MARK: - Directory creation

	@objc(_createDirectoryAtPath:)
	public static func createDirectory(atPath directoryPath: String) {
		createDirectory(at: URL(fileURLWithPath: directoryPath, isDirectory: true))
	}

	@objc(_createDirectoryAtURL:)
	public static func createDirectory(at directoryURL: URL) {
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

	@objc public static var applicationBundle: String {
		Bundle.main.bundlePath
	}

	@objc public static var applicationBundleURL: URL {
		Bundle.main.bundleURL
	}

	@objc public static var applicationResources: String {
		Bundle.main.resourcePath ?? ""
	}

	@objc public static var applicationResourcesURL: URL {
		Bundle.main.resourceURL ?? Bundle.main.bundleURL
	}

	@objc public static var applicationCaches: String? {
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

	@objc public static var applicationCachesURL: URL? {
		fileURL(forPath: applicationCaches)
	}

	@objc public static var groupContainer: String? {
		groupContainerURL?.path
	}

	@objc public static var groupContainerURL: URL? {
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

	@objc public static var groupContainerApplicationCaches: String? {
		groupContainerApplicationCachesURL?.path
	}

	@objc public static var groupContainerApplicationCachesURL: URL? {
		guard let sourceURL = groupContainerURL else {
			return nil
		}

		let baseURL = sourceURL.appendingPathComponent("/Library/Caches/")
		createDirectory(at: baseURL)

		return baseURL
	}

	@objc public static var applicationSupport: String? {
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

	@objc public static var applicationSupportURL: URL? {
		fileURL(forPath: applicationSupport)
	}

	@objc public static var groupContainerApplicationSupport: String? {
		groupContainerApplicationSupportURL?.path
	}

	@objc public static var groupContainerApplicationSupportURL: URL? {
		guard let sourceURL = groupContainerURL else {
			return nil
		}

		let baseURL = sourceURL.appendingPathComponent("/Library/Application Support/Glasstual/")
		createDirectory(at: baseURL)

		return baseURL
	}

	@objc public static var applicationLogs: String? {
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

	@objc public static var applicationLogsURL: URL? {
		fileURL(forPath: applicationLogs)
	}

	@objc public static var applicationTemporary: String {
		let basePath = (NSTemporaryDirectory() as NSString)
			.appendingPathComponent("/\(productIdentifier)/")

		createDirectory(atPath: basePath)

		return basePath
	}

	@objc public static var applicationTemporaryURL: URL {
		URL(fileURLWithPath: applicationTemporary, isDirectory: true)
	}

	@objc public static var applicationTemporaryProcessSpecific: String {
		let processIdentifier = ProcessInfo.processInfo.processIdentifier
		let basePath = (applicationTemporary as NSString)
			.appendingPathComponent("/tmp-\(processIdentifier)")

		createDirectory(atPath: basePath)

		return basePath
	}

	@objc public static var applicationTemporaryProcessSpecificURL: URL {
		URL(fileURLWithPath: applicationTemporaryProcessSpecific, isDirectory: true)
	}

	@objc public static var bundledExtensions: String {
		bundledExtensionsURL.path
	}

	@objc public static var bundledExtensionsURL: URL {
		applicationResourcesURL.appendingPathComponent("/Bundled Extensions/")
	}

	@objc public static var bundledScripts: String {
		bundledScriptsURL.path
	}

	@objc public static var bundledScriptsURL: URL {
		applicationResourcesURL.appendingPathComponent("/Bundled Scripts/")
	}

	@objc public static var bundledThemes: String {
		bundledThemesURL.path
	}

	@objc public static var bundledThemesURL: URL {
		applicationResourcesURL.appendingPathComponent("/Bundled Styles/")
	}

	@objc public static var customExtensions: String? {
		customExtensionsURL?.path
	}

	@objc public static var customExtensionsURL: URL? {
		guard let sourceURL = groupContainerApplicationSupportURL else {
			return nil
		}

		let baseURL = sourceURL.appendingPathComponent("/Extensions/")
		createDirectory(at: baseURL)

		return baseURL
	}

	@objc public static var customScripts: String? {
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

	@objc public static var customScriptsURL: URL? {
		fileURL(forPath: customScripts)
	}

	@objc public static var customThemes: String? {
		customThemesURL?.path
	}

	@objc public static var customThemesURL: URL? {
		guard let sourceURL = groupContainerApplicationSupportURL else {
			return nil
		}

		let baseURL = sourceURL.appendingPathComponent("/Styles/")
		createDirectory(at: baseURL)

		return baseURL
	}

	// MARK: - System Specific

	@objc public static var systemApplications: String? {
		firstSearchPath(for: .applicationDirectory, in: .systemDomainMask)
	}

	@objc public static var systemApplicationsURL: URL? {
		fileURL(forPath: systemApplications)
	}

	@objc public static var systemDiagnosticReports: String {
		"/Library/Logs/DiagnosticReports"
	}

	@objc public static var systemDiagnosticReportsURL: URL {
		URL(fileURLWithPath: systemDiagnosticReports, isDirectory: true)
	}

	// MARK: - User Specific

	@objc public static var userApplicationScripts: String? {
		userApplicationScriptsURL?.path
	}

	@objc public static var userApplicationScriptsURL: URL? {
		customScriptsURL?.deletingLastPathComponent()
	}

	@objc public static var userDiagnosticReports: String {
		userDiagnosticReportsURL.path
	}

	@objc public static var userDiagnosticReportsURL: URL {
		userHomeURL.appendingPathComponent("/Library/Logs/DiagnosticReports")
	}

	@objc public static var userDownloads: String? {
		firstSearchPath(for: .downloadsDirectory)
	}

	@objc public static var userDownloadsURL: URL? {
		fileURL(forPath: userDownloads)
	}

	@objc public static var userHome: String {
		FileManager.pathOfHomeDirectoryOutsideSandbox
	}

	@objc public static var userHomeURL: URL {
		FileManager.URLOfHomeDirectoryOutsideSandbox
	}

	@objc public static var userPreferences: String? {
		firstSearchPath(for: .libraryDirectory, appending: "/Preferences/")
	}

	@objc public static var userPreferencesURL: URL? {
		fileURL(forPath: userPreferences)
	}

	// MARK: - Transcript folder

	@objc public static var transcriptFolder: String? {
		transcriptFolderURL?.path
	}

	@objc public static var transcriptFolderURL: URL? {
		transcriptLock.lock()
		defer { transcriptLock.unlock() }

		return storedTranscriptFolderURL
	}

	@objc public static func setTranscriptFolderURL(_ transcriptFolderURL: Data?) {
		transcriptLock.lock()
		if let storedTranscriptFolderURL {
			storedTranscriptFolderURL.stopAccessingSecurityScopedResource()
			self.storedTranscriptFolderURL = nil
		}
		transcriptLock.unlock()

		TextualUserDefaults.shared().set(transcriptFolderURL, forKey: transcriptBookmarkDefaultsKey)
		startUsingTranscriptFolderURL()
	}

	@objc public static func startUsingTranscriptFolderURL() {
		guard let bookmark = TextualUserDefaults.shared().data(forKey: transcriptBookmarkDefaultsKey) else {
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
			var newBookmark: Data?

			if resolvedBookmark.startAccessingSecurityScopedResource() {
				newBookmark = try? resolvedBookmark.bookmarkData(
					options: .withSecurityScope,
					includingResourceValuesForKeys: nil,
					relativeTo: nil
				)
				resolvedBookmark.stopAccessingSecurityScopedResource()
			}

			if let newBookmark {
				setTranscriptFolderURL(newBookmark)
			} else {
				warnUserAboutStaleTranscriptFolderURL()
			}

			return
		}

		transcriptLock.lock()
		storedTranscriptFolderURL = resolvedBookmark
		transcriptLock.unlock()

		if resolvedBookmark.startAccessingSecurityScopedResource() == false {
			logger.error("Failed to access bookmark")
		}
	}

	// MARK: - Helpers

	private static func warnUserAboutStaleTranscriptFolderURL() {
		guard TextualPreferences.logToDisk() else {
			return
		}

		_ = TDCAlert.alert(
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
		(url as NSURL).textualStandardizedTildePath ?? url.path
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
