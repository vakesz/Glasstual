// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import os
import Synchronization

/// Where the application keeps its files. Every accessor here creates the
/// directory it names, so callers can write into it straight away.
nonisolated enum ApplicationPaths {
	private static let logger = Logger(
		subsystem: LogSubsystem.current,
		category: "ApplicationPaths"
	)

	/** The security-scoped transcript folder, held open for as long as the
	 process is using it. Main-actor state: every caller -- the settings pane
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

	static func createDirectory(at directoryURL: URL) {
		let alreadyEnsured = ensuredDirectories.withLock { ensured in
			ensured.contains(directoryURL)
		}

		if alreadyEnsured {
			return
		}

		if fileManager.fileExists(at: directoryURL) == false {
			do {
				try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
			} catch {
				/* Not remembered: a directory that could not be created has to
				 be tried again, or every later caller is told a path is ready
				 to write into when it is not. */
				logger.error(
					"Failed to create directory at path: '\(displayPath(for: directoryURL), privacy: .public)' - \(error.localizedDescription, privacy: .public)"
				)

				return
			}
		}

		ensuredDirectories.withLock { ensured in
			_ = ensured.insert(directoryURL)
		}
	}

	// MARK: - Application Specific

	static var applicationBundleURL: URL {
		Bundle.main.bundleURL
	}

	static var applicationResourcesURL: URL {
		Bundle.main.resourceURL ?? Bundle.main.bundleURL
	}

	private static var groupContainerURL: URL? {
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

	static var groupContainerApplicationCaches: String? {
		groupContainerApplicationCachesURL?.path
	}

	private static var groupContainerApplicationCachesURL: URL? {
		guard let sourceURL = groupContainerURL else {
			return nil
		}

		let baseURL = sourceURL.appendingPathComponent("/Library/Caches/")
		createDirectory(at: baseURL)

		return baseURL
	}

	static var applicationSupportURL: URL? {
		guard
			var basePath = firstSearchPath(
				for: .applicationSupportDirectory,
				appending: "/Glasstual/"
			)
		else {
			return nil
		}

		basePath = applyUIReviewDirectory(toPath: basePath)

		guard let baseURL = fileURL(forPath: basePath) else {
			return nil
		}

		createDirectory(at: baseURL)

		return baseURL
	}

	static var groupContainerApplicationSupportURL: URL? {
		guard let sourceURL = groupContainerURL else {
			return nil
		}

		let baseURL = sourceURL.appendingPathComponent("/Library/Application Support/Glasstual/")
		createDirectory(at: baseURL)

		return baseURL
	}

	static var applicationTemporaryURL: URL {
		let baseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appendingPathComponent(productIdentifier, isDirectory: true)

		createDirectory(at: baseURL)

		return baseURL
	}

	static var bundledScriptsURL: URL {
		applicationResourcesURL.appendingPathComponent("/Bundled Scripts/")
	}

	static var customScriptsURL: URL? {
		#if DEBUG
			if ProcessInfo.processInfo.environment["GLASSTUAL_UI_REVIEW_DIRECTORY"] != nil,
			   let supportURL = groupContainerApplicationSupportURL
			{
				let baseURL = supportURL.appendingPathComponent("Scripts", isDirectory: true)
				createDirectory(at: baseURL)

				return baseURL
			}
		#endif

		return fileURL(forPath: firstSearchPath(for: .applicationScriptsDirectory))
	}

	// MARK: - System Specific

	static var systemDiagnosticReportsURL: URL {
		URL(fileURLWithPath: "/Library/Logs/DiagnosticReports", isDirectory: true)
	}

	// MARK: - User Specific

	static var userDiagnosticReportsURL: URL {
		userHomeURL.appendingPathComponent("/Library/Logs/DiagnosticReports")
	}

	static var userDownloadsURL: URL? {
		firstSearchPath(for: .downloadsDirectory).map { URL(fileURLWithPath: $0, isDirectory: true) }
	}

	private static var userHomeURL: URL {
		FileManager.URLOfHomeDirectoryOutsideSandbox
	}

	// MARK: - Transcript folder

	@MainActor
	static var transcriptFolder: String? {
		transcriptFolderURL?.path
	}

	@MainActor
	static var transcriptFolderURL: URL? {
		transcriptFolderURLStorage
	}

	/// Whether a transcript is actually being written: the setting is on and a
	/// folder the application can still reach has been chosen.
	@MainActor
	static var isWritingTranscripts: Bool {
		SettingsKeys.Logging.logToDisk.value && transcriptFolderURL != nil
	}

	@MainActor
	static func setTranscriptFolderURL(_ transcriptFolderURL: Data?) {
		stopUsingTranscriptFolderURL()

		if let transcriptFolderURL {
			SettingsKeys.Logging.transcriptFolderBookmark.value = transcriptFolderURL
		} else {
			SettingsKeys.Logging.transcriptFolderBookmark.reset()
		}
		startUsingTranscriptFolderURL()
	}

	@MainActor
	static func startUsingTranscriptFolderURL() {
		startUsingTranscriptFolderURL(refreshingStaleBookmark: true)
	}

	@MainActor
	static func stopUsingTranscriptFolderURL() {
		let existingURL = transcriptFolderURLStorage
		transcriptFolderURLStorage = nil

		existingURL?.stopAccessingSecurityScopedResource()
	}

	@MainActor
	private static func startUsingTranscriptFolderURL(refreshingStaleBookmark: Bool) {
		/* Security-scoped access is reference counted, so any previous access has to be
		 released before a new one is taken; launch plus a setting reload both call in. */
		stopUsingTranscriptFolderURL()

		let bookmark = SettingsKeys.Logging.transcriptFolderBookmark.value
		guard bookmark.isEmpty == false else { return }

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

			SettingsKeys.Logging.transcriptFolderBookmark.value = newBookmark
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
		guard SettingsKeys.Logging.logToDisk.value else {
			return
		}

		Alerts.alert(
			title: PromptStrings.Logging.staleLocationTitle,
			body: PromptStrings.Logging.staleLocationBody,
			defaultButton: PromptStrings.Action.confirmation
		)
	}

	private static func firstSearchPath(
		for directory: FileManager.SearchPathDirectory,
		appending suffix: String? = nil
	) -> String? {
		guard let firstURL = FileManager.default.urls(for: directory, in: .userDomainMask).first else {
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
