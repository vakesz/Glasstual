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

	/// The sidebar, in the order the catalogue declares it, with the add-on
	/// panes plugins contribute already folded in.
	var entries: [PreferencesSidebarEntry] = []

	var versionFooter = ""

	/** Which pane the detail column shows.

	 The list writes it, and the shell answers by retitling the window,
	 remembering the choice and recording it for the back and forward buttons —
	 which is why the reaction is a callback rather than something the view
	 does. */
	var selectedPaneIdentifier: String? {
		didSet {
			guard let selectedPaneIdentifier, selectedPaneIdentifier != oldValue else { return }
			onSelectionChange?(selectedPaneIdentifier)
		}
	}

	@ObservationIgnored
	var onSelectionChange: ((String) -> Void)?

	var themes: [PreferencesThemeChoice] = []
	var selectedTheme: PreferencesThemeChoice?
	var channelViewFontName = ""
	var channelViewFontSize: CGFloat = 0

	/// `nil` when no folder is configured, which the popup shows as its
	/// "no location selected" title.
	var transcriptFolder: URL?
	var downloadFolder: URL?

	var addOnCommands: [String] = []

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
	}

	func refreshAll() {
		refreshThemes()
		refreshChannelViewFont()
		refreshFolders()
		refreshAddOnCommands()
	}
}
