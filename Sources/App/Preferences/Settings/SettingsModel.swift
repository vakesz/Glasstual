// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation
import os
import UniformTypeIdentifiers

struct IRCv3ConnectionSummary: Equatable, Identifiable {
	let id: String
	let name: String
	let isConnected: Bool
	let capabilities: [String]
}

/** A Settings operation that failed.

 Each one names itself and says what to do next, so an alert never reports only
 that something went wrong somewhere in Settings. */
enum SettingsOperation {
	case importTranscriptTheme
	case exportTranscriptTheme
	case applyTranscriptTheme
	case selectTranscriptFolder
	case selectDownloadFolder

	var failureTitle: String {
		let resource: LocalizedStringResource = switch self {
		case .importTranscriptTheme: .Settings.failureImportThemeTitle
		case .exportTranscriptTheme: .Settings.failureExportThemeTitle
		case .applyTranscriptTheme: .Settings.failureApplyThemeTitle
		case .selectTranscriptFolder: .Settings.failureTranscriptFolderTitle
		case .selectDownloadFolder: .Settings.failureDownloadFolderTitle
		}
		return String(localized: resource)
	}

	var failureRecovery: String {
		let resource: LocalizedStringResource = switch self {
		case .importTranscriptTheme: .Settings.failureImportThemeRecovery
		case .exportTranscriptTheme: .Settings.failureExportThemeRecovery
		case .applyTranscriptTheme: .Settings.failureApplyThemeRecovery
		case .selectTranscriptFolder: .Settings.failureTranscriptFolderRecovery
		case .selectDownloadFolder: .Settings.failureDownloadFolderRecovery
		}
		return String(localized: resource)
	}
}

/// What stopped one Settings operation, ready to be shown as an alert.
struct SettingsOperationFailure: Equatable {
	let operation: SettingsOperation
	/// What went wrong, in the words of whatever refused the work.
	let reason: String

	var title: String {
		operation.failureTitle
	}

	var message: String {
		"\(reason)\n\n\(operation.failureRecovery)"
	}
}

enum SettingsImportRequest {
	case transcriptTheme
	case transcriptFolder
	case downloadFolder

	var allowedContentTypes: [UTType] {
		switch self {
		case .transcriptTheme: [.propertyList]
		case .transcriptFolder, .downloadFolder: [.folder]
		}
	}

	/// What the alert says the user was doing when the chosen file or folder
	/// turned out to be unusable.
	var operation: SettingsOperation {
		switch self {
		case .transcriptTheme: .importTranscriptTheme
		case .transcriptFolder: .selectTranscriptFolder
		case .downloadFolder: .selectDownloadFolder
		}
	}
}

/// Pane selection, folder locations, inventory and presentation requests. Theme
/// and font fields read the controller directly rather than keeping a second copy.
@MainActor
@Observable
final class SettingsModel {
	/// Bindings for everything that *is* a preference key.
	let preferences = ObservablePreferences.shared

	/// The defaults databases themselves, for the one question a binding cannot
	/// answer: what is persisted, as opposed to what a read resolves to.
	@ObservationIgnored
	let stores = PreferencesTransferStores.live

	/** The language the application has been told to run in.

	 Read out of what the standard domain has actually persisted rather than
	 through the key: the effective value of `AppleLanguages` also carries the
	 system's own language list, and a Mac set to Hungarian would then show
	 Hungarian here instead of System Default. The discarded read above it is
	 what registers a view reading this property with the observable store, so
	 the picker follows a change made anywhere else. */
	var appLanguage: AppLanguage {
		get {
			_ = preferences[Preferences.Internals.appLanguages]
			let key = Preferences.Internals.appLanguages
			let persisted = stores.persistentDomain(for: key.storage)[key.name] as? [String]
			return AppLanguage(override: persisted)
		}
		set {
			preferences[stored: Preferences.Internals.appLanguages] = newValue.override
		}
	}

	/// The sidebar's rows, in order, with the panes each one shows.
	var destinations: [SettingsDestination] = []
	var searchText = ""

	var matchingDestinations: [SettingsDestination] {
		destinations.filter { $0.matches(searchText: searchText) }
	}

	private(set) var selection = SettingsSelection.general

	@ObservationIgnored
	var onSelectionChange: ((SettingsSelection) -> Void)?

	var currentDestination: SettingsDestination? {
		destinations.first { $0.selection == selection }
	}

	let themeController: ThemeController

	var transcriptTheme: TranscriptTheme {
		themeController.theme
	}

	/// `nil` when no folder is configured, which the popup shows as its
	/// "no location selected" title.
	var transcriptFolder: URL?
	var downloadFolder: URL?
	var usesCustomDownloadFolder = false

	var ircv3Connections: [IRCv3ConnectionSummary] = []

	/// Presentation requests consumed by the SwiftUI Settings scene. The file
	/// panel's request lives here rather than in the view, so the action that
	/// raises it and the completion that consumes it read one value.
	var fileRequest = PendingFileRequest<SettingsImportRequest>()
	var exportedThemeData: Data?
	var exportedThemeFilename = ""
	var presentationFailure: SettingsOperationFailure?
	var externalURL: URL?
	var showsFontPicker = false
	/// The read and import of a chosen theme file, for whoever needs to wait
	/// for its outcome; the view does not.
	@ObservationIgnored var themeImportTask: Task<Void, Never>?

	init(themeController: ThemeController = AppServices.theme) {
		self.themeController = themeController
	}

	/// Shows a row the sidebar is actually listing. A name the sidebar does not
	/// list leaves the window where it is.
	@discardableResult
	func select(_ destination: SettingsSelection) -> Bool {
		guard destinations.contains(where: { $0.selection == destination }), selection != destination else {
			return false
		}
		selection = destination
		onSelectionChange?(destination)
		return true
	}

	/// Applies an edit to the theme, and reports whether the theme accepted it.
	@discardableResult
	func updateTheme(_ update: (inout TranscriptTheme) -> Void) -> Bool {
		var changed = themeController.theme
		update(&changed)

		guard themeController.apply(changed) else {
			report(String(localized: .TranscriptTheme.invalidValues), from: .applyTranscriptTheme)
			return false
		}
		return true
	}

	func refreshFolders() {
		transcriptFolder = ApplicationPaths.transcriptFolderURL
		downloadFolder = AppServices.fileTransfers.downloadDestinationURL
		usesCustomDownloadFolder = AppServices.fileTransfers.hasCustomDownloadDestination
	}

	func refreshIRCv3Connections() {
		ircv3Connections = AppServices.clientDirectory.clientList.map { client in
			IRCv3ConnectionSummary(
				id: client.uniqueIdentifier,
				name: client.networkNameAlt.isEmpty ? client.serverAddress ?? "" : client.networkNameAlt,
				isConnected: client.isLoggedIn,
				capabilities: client.enabledCapabilityNames.sorted()
			)
		}
	}

	func refreshAll() {
		refreshFolders()
		refreshIRCv3Connections()
	}
}

private let settingsActionsLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "SettingsActions"
)

/// Reads a document the user chose off the main actor, bounded exactly like an
/// imported configuration.
private nonisolated enum SettingsDocumentReader {
	@concurrent
	static func read(from url: URL) async throws -> Data {
		try PreferencesArchive.readData(from: url)
	}
}

/// Presentation intent and the resulting domain updates for Settings. SwiftUI
/// presents each request; this model validates and applies the selected value.
extension SettingsModel {
	// MARK: - Style

	func importTranscriptTheme() {
		fileRequest.present(.transcriptTheme)
	}

	func exportTranscriptTheme() {
		do {
			exportedThemeData = try themeController.exportTheme()
			exportedThemeFilename = "\(themeController.name).plist"
		} catch {
			report(error, from: .exportTranscriptTheme)
		}
	}

	func resetTranscriptTheme() {
		themeController.reset()
	}

	func selectChannelViewFont() {
		showsFontPicker = true
	}

	func applyChannelViewFont(name: String, size: CGFloat) {
		updateTheme {
			$0.fontName = name
			$0.fontSize = size
		}
	}

	// MARK: - Folders

	func selectTranscriptFolder() {
		fileRequest.present(.transcriptFolder)
	}

	func clearTranscriptFolder() {
		setTranscriptFolder(nil)
	}

	func selectDownloadFolder() {
		fileRequest.present(.downloadFolder)
	}

	func clearDownloadFolder() {
		AppServices.fileTransfers.setDownloadDestinationURL(nil)
		refreshFolders()
	}

	func completeImport(_ result: Result<URL, any Error>, request: SettingsImportRequest) {
		do {
			let url = try result.get()

			switch request {
			case .transcriptTheme:
				importTranscriptTheme(from: url)
			case .transcriptFolder:
				try withSecurityScopedAccess(to: url) {
					try setTranscriptFolder(securityScopedBookmark(for: url))
				}
			case .downloadFolder:
				try withSecurityScopedAccess(to: url) {
					try AppServices.fileTransfers.setDownloadDestinationURL(
						securityScopedBookmark(for: url)
					)
					refreshFolders()
				}
			}
		} catch {
			// A closed file panel is the user saying "nothing", not a failure.
			guard (error as? CocoaError)?.code != .userCancelled else { return }
			report(error, from: request.operation)
		}
	}

	/** A chosen theme is arbitrary user input of arbitrary size.

	 Reading it with `Data(contentsOf:)` on the main actor blocked the whole
	 application for as long as the file took to read, so the read runs off the
	 main actor under the same regular-file check and 16 MB cap an imported
	 configuration gets, and takes its own security-scoped access. */
	private func importTranscriptTheme(from url: URL) {
		themeImportTask = Task { @MainActor in
			do {
				let data = try await SettingsDocumentReader.read(from: url)
				try themeController.importTheme(from: data)
			} catch {
				report(error, from: .importTranscriptTheme)
			}
		}
	}

	/// Bookmarking a chosen folder needs the panel's security-scoped access for
	/// the length of the call.
	private func withSecurityScopedAccess<Value>(to url: URL, _ body: () throws -> Value) rethrows -> Value {
		let accessWasGranted = url.startAccessingSecurityScopedResource()
		defer {
			if accessWasGranted {
				url.stopAccessingSecurityScopedResource()
			}
		}

		return try body()
	}

	func completeExport(_ result: Result<URL, any Error>) {
		exportedThemeData = nil
		if case let .failure(error) = result, (error as? CocoaError)?.code != .userCancelled {
			report(error, from: .exportTranscriptTheme)
		}
	}

	private func setTranscriptFolder(_ bookmark: Data?) {
		ApplicationPaths.setTranscriptFolderURL(bookmark)
		PreferenceReload.perform(.logTranscripts)
		refreshFolders()
	}

	private func securityScopedBookmark(for url: URL) throws -> Data {
		do {
			return try url.bookmarkData(
				options: .withSecurityScope,
				includingResourceValuesForKeys: nil,
				relativeTo: nil
			)
		} catch {
			settingsActionsLogger.error(
				"Failed to retain access to the chosen folder: \(error.localizedDescription, privacy: .public)"
			)
			throw error
		}
	}

	func report(_ error: any Error, from operation: SettingsOperation) {
		report(error.localizedDescription, from: operation)
	}

	/// Names the operation that stopped, so the alert can say what to do about
	/// it rather than only that something in Settings went wrong.
	func report(_ reason: String, from operation: SettingsOperation) {
		presentationFailure = SettingsOperationFailure(operation: operation, reason: reason)
	}
}
