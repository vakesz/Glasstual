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

import Foundation
import Observation
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
enum PreferencesOperation {
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
struct PreferencesOperationFailure: Equatable {
	let operation: PreferencesOperation
	/// What went wrong, in the words of whatever refused the work.
	let reason: String

	var title: String {
		operation.failureTitle
	}

	var message: String {
		"\(reason)\n\n\(operation.failureRecovery)"
	}
}

enum PreferencesImportRequest {
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
	var operation: PreferencesOperation {
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
final class PreferencesPaneModel {
	/// Bindings for everything that *is* a preference key.
	let preferences = ObservablePreferences.shared

	/// The sidebar's rows, in order, with the panes each one shows.
	var destinations: [PreferencesDestination] = []
	var searchText = ""

	var matchingDestinations: [PreferencesDestination] {
		destinations.filter { $0.matches(searchText: searchText) }
	}

	private(set) var selection = PreferencesSelection.general

	@ObservationIgnored
	var onSelectionChange: ((PreferencesSelection) -> Void)?

	var currentDestination: PreferencesDestination? {
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

	var addOnCommands: [String] = []
	var addOnInstallationNote = ""
	var ircv3Connections: [IRCv3ConnectionSummary] = []

	/// Presentation requests consumed by the SwiftUI Settings scene. The file
	/// panel's request lives here rather than in the view, so the action that
	/// raises it and the completion that consumes it read one value.
	var fileRequest = PendingFileRequest<PreferencesImportRequest>()
	var exportedThemeData: Data?
	var exportedThemeFilename = ""
	var presentationFailure: PreferencesOperationFailure?
	var externalURL: URL?
	var showsFontPicker = false
	/// The read and import of a chosen theme file, for whoever needs to wait
	/// for its outcome; the view does not.
	@ObservationIgnored var themeImportTask: Task<Void, Never>?

	@ObservationIgnored
	let notificationConfiguration: NotificationConfigurationModel

	init(themeController: ThemeController = SharedApplication.sharedThemeController()) {
		self.themeController = themeController
		notificationConfiguration = NotificationConfigurationModel(
			notifications: Self.defaultNotificationItems,
			allowsInheritedState: false
		)
	}

	/// Shows a row the sidebar is actually listing. A row that has gone away
	/// with the add-on that supplied it leaves the window where it is.
	@discardableResult
	func select(_ destination: PreferencesSelection) -> Bool {
		guard destinations.contains(where: { $0.selection == destination }), selection != destination else {
			return false
		}
		selection = destination
		onSelectionChange?(destination)
		return true
	}

	/** The nil entries are the separators the alert list draws between groups of
	 related events. */
	private static let defaultNotificationItems: [NotificationConfigurationItem] = {
		let eventTypes: [NotificationEvent?] = [
			.addressBookMatch, nil, .connect, .disconnect, nil, .highlight, nil, .invite, .kick, nil,
			.channelMessage, .channelNotice, nil, .newPrivateMessage, .privateMessage, .privateNotice, nil,
			.userJoined, .userParted, .userDisconnected, nil, .fileTransferReceiveRequested, nil,
			.fileTransferSendSuccessful, .fileTransferReceiveSuccessful, nil,
			.fileTransferSendFailed, .fileTransferReceiveFailed,
		]
		return eventTypes.map { eventType in
			guard let eventType else { return .separator }
			return .configuration(PreferencesNotificationConfiguration(eventType: eventType))
		}
	}()

	/// Applies an edit to the theme, and reports whether the theme accepted it.
	@discardableResult
	func updateTheme(_ update: (inout TranscriptTheme) -> Void) -> Bool {
		var changed = themeController.theme
		update(&changed)

		guard themeController.apply(changed) else {
			report(TranscriptThemeStrings.invalidValues, from: .applyTranscriptTheme)
			return false
		}
		return true
	}

	func refreshFolders() {
		transcriptFolder = PathInfo.transcriptFolderURL
		downloadFolder = SharedApplication.sharedFileTransferCenter().downloadDestinationURL
	}

	func refreshAddOnCommands() {
		let manager = SharedApplication.sharedPluginManager()
		let commands = manager.supportedAppleScriptCommands + manager.supportedUserInputCommands
		addOnCommands = commands.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
		let folderName = manager.customScriptsURL?.lastPathComponent
			?? ApplicationInfo.applicationBundleIdentifier()
		addOnInstallationNote = String(localized: .Settings.addonsInstallNote(folderName))
	}

	func refreshIRCv3Connections() {
		ircv3Connections = AppController.shared.world.clientList.map { client in
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
		refreshAddOnCommands()
		refreshIRCv3Connections()
	}
}
