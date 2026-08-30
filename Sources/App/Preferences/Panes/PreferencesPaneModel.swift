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
import Observation

/** What a pane asks its AppKit shell to do.

 Everything here needs a window: a sheet, an open panel, the font panel, or a
 permission prompt. The panes stay declarative and the shell keeps owning
 presentation. */
@MainActor
protocol PreferencesPaneActionHandler: AnyObject {
	func selectChannelViewFont()
	func browseStyleFiles()
	func editUserStyleSheetRules()
	func selectTheme(_ choice: PreferencesThemeChoice)
	func selectTranscriptFolder()
	func clearTranscriptFolder()
	func selectDownloadFolder()
	func clearDownloadFolder()
	func openCustomAddOnsFolder()
	func setInlineMediaEnabled(_ enabled: Bool)
}

/// One entry of the style popup in the Style pane.
struct PreferencesThemeChoice: Identifiable, Hashable, Sendable {
	let themeName: String
	let storageLocation: TPCThemeStorageLocation
	let title: String

	var id: String {
		"\(storageLocation.rawValue):\(themeName)"
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

	@ObservationIgnored
	weak var actions: (any PreferencesPaneActionHandler)?

	/// Set while a style reload runs; the controls that would restart it are
	/// disabled until it finishes.
	var isReloadingTheme = false

	/// The toolbar's sections, with the panes each one shows.
	var sections: [PreferencesSection] = []

	/// The toolbar item and the sub-page it contains change as one value.
	private(set) var selection = PreferencesSelection.general

	@ObservationIgnored
	var onSelectionChange: ((PreferencesSelection) -> Void)?

	var currentSection: PreferencesSection? {
		sections.first { $0.identifier == selection.sectionIdentifier }
	}

	var themes: [PreferencesThemeChoice] = []
	var selectedTheme: PreferencesThemeChoice?
	var channelViewFontName = ""
	var channelViewFontSize: CGFloat = 0

	/// `nil` when no folder is configured, which the popup shows as its
	/// "no location selected" title.
	var transcriptFolder: URL?
	var downloadFolder: URL?

	var addOnCommands: [String] = []
	var scriptInstallationInstructions = ""

	/** The AppKit alert table the Notifications pane hosts.

	 It is built and attached once: `attachToView` refuses a second host, and a
	 SwiftUI representable is remade every time the pane comes back. */
	@ObservationIgnored
	let notificationConfiguration = NotificationConfigurationViewController()

	@ObservationIgnored
	let notificationHostView = NSView(frame: .zero)

	init() {
		notificationConfiguration.notifications = Self.notificationItems
		notificationConfiguration.attachToView(notificationHostView)
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
		onSelectionChange?(destination)
		return true
	}

	/// Changes the picker within the current toolbar section.
	@discardableResult
	func selectSubPage(_ identifier: String) -> Bool {
		select(PreferencesSelection(
			sectionIdentifier: selection.sectionIdentifier,
			subPageIdentifier: identifier
		))
	}

	/** The nil entries are the separators the alert list draws between groups of
	 related events; the order is the one the nib shipped. */
	private static let notificationItems: [NotificationConfigurationItem] = {
		let eventTypes: [TXNotificationType?] = [
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

	func refreshThemes() {
		let controller = SharedApplication.sharedThemeController()
		var choices: [PreferencesThemeChoice] = []
		controller.enumerateAvailableThemes { themeName, storageLocation, multipleVariants, _ in
			let title = multipleVariants
				? "\(themeName) (\(TPCThemeController.description(for: storageLocation) ?? ""))"
				: themeName
			choices.append(
				PreferencesThemeChoice(themeName: themeName, storageLocation: storageLocation, title: title)
			)
		}
		themes = choices.sorted { first, second in
			if first.storageLocation != second.storageLocation {
				return first.storageLocation == .bundle
			}
			return first.title.localizedStandardCompare(second.title) == .orderedAscending
		}
		selectedTheme = themes.first {
			$0.themeName == controller.name && $0.storageLocation == controller.storageLocation
		}
	}

	func refreshChannelViewFont() {
		channelViewFontName = TextualPreferences.themeChannelViewFont()?.displayName ?? ""
		channelViewFontSize = TextualPreferences.themeChannelViewFontSize()
	}

	func refreshFolders() {
		transcriptFolder = PathInfo.transcriptFolderURL
		downloadFolder = SharedApplication.sharedFileTransferDialog().downloadDestinationURL
	}

	func refreshAddOnCommands() {
		let manager = SharedApplication.sharedPluginManager()
		let commands = manager.supportedAppleScriptCommands + manager.supportedUserInputCommands
		addOnCommands = commands.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
		let folderName = PathInfo.customScriptsURL?.lastPathComponent
			?? ApplicationInfo.applicationBundleIdentifier()
		scriptInstallationInstructions = PromptStrings.DocumentImport.scriptSavePanelBody(
			bundleIdentifier: folderName
		)
	}

	func refreshAll() {
		refreshThemes()
		refreshChannelViewFont()
		refreshFolders()
		refreshAddOnCommands()
	}
}
