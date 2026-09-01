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

enum PreferencesImportRequest: Identifiable {
	case transcriptTheme
	case transcriptFolder
	case downloadFolder

	var id: Self {
		self
	}

	var allowedContentTypes: [UTType] {
		switch self {
		case .transcriptTheme: [.propertyList]
		case .transcriptFolder, .downloadFolder: [.folder]
		}
	}
}

/** The state the panes show that does not live in the key store: what the theme
 controller lists, which folders the security-scoped bookmarks point at, the
 font the style is drawn with, and whether a style reload is in flight.

 The shell refreshes it; the panes only read it. */
@MainActor
@Observable
final class PreferencesPaneModel {
	/// Bindings for everything that *is* a preference key.
	let preferences = ObservablePreferences.shared

	/// The sidebar's sections, with the panes each one shows.
	var sections: [PreferencesSection] = []

	/// The sidebar item and the sub-page it contains change as one value.
	private(set) var selection = PreferencesSelection.general
	private var lastSubPageBySection: [PreferencesSectionIdentifier: String] = [:]

	@ObservationIgnored
	var onSelectionChange: ((PreferencesSelection) -> Void)?

	var currentSection: PreferencesSection? {
		sections.first { $0.identifier == selection.sectionIdentifier }
	}

	var transcriptTheme = TranscriptTheme.lines
	var channelViewFontName = ""
	var channelViewFontSize: CGFloat = 0

	/// `nil` when no folder is configured, which the popup shows as its
	/// "no location selected" title.
	var transcriptFolder: URL?
	var downloadFolder: URL?

	var addOnCommands: [String] = []
	var scriptInstallationInstructions = ""
	var ircv3Connections: [IRCv3ConnectionSummary] = []

	/// Presentation requests consumed by the SwiftUI Settings scene.
	var importRequest: PreferencesImportRequest?
	var exportedThemeData: Data?
	var exportedThemeFilename = ""
	var presentationError: String?
	var externalURL: URL?
	var showsFontPicker = false

	@ObservationIgnored
	let notificationItems: [NotificationConfigurationItem]

	init() {
		notificationItems = Self.defaultNotificationItems
	}

	/// Applies a complete destination only when the sub-page belongs to the
	/// section. Callers never have to repair a partially updated selection.
	@discardableResult
	func select(_ destination: PreferencesSelection) -> Bool {
		guard let section = sections.first(where: { $0.identifier == destination.sectionIdentifier }),
		      section.subPages.contains(where: { $0.identifier == destination.subPageIdentifier })
		else {
			return false
		}
		guard selection != destination else {
			return false
		}
		selection = destination
		lastSubPageBySection[destination.sectionIdentifier] = destination.subPageIdentifier
		onSelectionChange?(destination)
		return true
	}

	/// Selects a sidebar section and restores the sub-page last used in it.
	@discardableResult
	func selectSection(_ identifier: PreferencesSectionIdentifier) -> Bool {
		guard let section = sections.first(where: { $0.identifier == identifier }),
		      let subPage = lastSubPageBySection[identifier] ?? section.subPages.first?.identifier
		else {
			return false
		}

		return select(PreferencesSelection(
			sectionIdentifier: identifier,
			subPageIdentifier: subPage
		))
	}

	/// Changes the picker within the current sidebar section.
	@discardableResult
	func selectSubPage(_ identifier: String) -> Bool {
		select(PreferencesSelection(
			sectionIdentifier: selection.sectionIdentifier,
			subPageIdentifier: identifier
		))
	}

	/** The nil entries are the separators the alert list draws between groups of
	 related events; the order is the one the nib shipped. */
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

	func refreshTheme() {
		transcriptTheme = SharedApplication.sharedThemeController().theme
	}

	func updateTheme(_ update: (inout TranscriptTheme) -> Void) {
		var changed = transcriptTheme
		update(&changed)
		SharedApplication.sharedThemeController().apply(changed)
		refreshTheme()
	}

	func refreshChannelViewFont() {
		let theme = SharedApplication.sharedThemeController().theme
		channelViewFontName = theme.fontName
		channelViewFontSize = theme.fontSize
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
		scriptInstallationInstructions = PromptStrings.DocumentImport.scriptSavePanelBody(
			bundleIdentifier: folderName
		)
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
		refreshTheme()
		refreshChannelViewFont()
		refreshFolders()
		refreshAddOnCommands()
		refreshIRCv3Connections()
	}
}
