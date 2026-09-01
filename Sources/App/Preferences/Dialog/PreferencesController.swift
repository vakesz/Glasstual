/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import SwiftUI

public enum PreferencesControllerSelection: UInt, Sendable {
	case `default`
	case notifications
	case style
	case hiddenPreferences
}

public protocol PreferencesControllerDelegate: AnyObject {
	func preferencesDialogWillClose(_ sender: PreferencesController)
}

/** The minimal AppKit window shell around the SwiftUI Settings interface.

 SwiftUI owns navigation, toolbar state, and every first-party pane. This shell
 only configures the native window and presents the AppKit panels that have no
 complete SwiftUI equivalent. */
@MainActor
public final class PreferencesController: WindowBase, NSWindowDelegate {
	let model = PreferencesPaneModel()

	var fontPanelIsOwned = false
	var previousFontManagerAction: Selector?
	private lazy var notifications = NotificationSubscriptions()

	override public init() {
		super.init()
		prepareInitialState()
	}

	private func prepareInitialState() {
		model.actions = self
		model.sections = Self.sections()
		model.onSelectionChange = { [weak self] selection in
			self?.paneChanged(to: selection)
		}
		model.refreshAll()
		installWindow()
		prepareNotifications()
	}

	private func prepareNotifications() {
		notifications.observe(Notification.Name("NativeTranscriptThemeWasModified")) { [weak self] _ in
			self?.model.refreshTheme()
			self?.model.refreshChannelViewFont()
		}
		notifications.observe(.ircClientCapabilitiesDidChange) { [weak self] _ in
			self?.model.refreshIRCv3Connections()
		}
		notifications.observe(.ircWorldClientListWasModified) { [weak self] _ in
			self?.model.refreshIRCv3Connections()
		}
		notifications.observe(PluginManager.scriptCommandsDidChangeNotification) { [weak self] _ in
			self?.model.refreshAddOnCommands()
		}
	}

	// MARK: - Window

	private func installWindow() {
		let hostingController = NSHostingController(rootView: PreferencesRootView(model: model))
		let hostedWindow = PreferencesWindow(
			contentRect: NSRect(origin: .zero, size: PreferencesLayout.windowSize),
			styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		hostedWindow.contentViewController = hostingController
		hostedWindow.delegate = self
		hostedWindow.isReleasedWhenClosed = false
		hostedWindow.isRestorable = false
		hostedWindow.tabbingMode = .disallowed
		hostedWindow.toolbarStyle = .automatic
		hostedWindow.minSize = PreferencesLayout.minimumWindowSize
		hostedWindow.preventsApplicationTerminationWhenModal = false
		hostedWindow.autorecalculatesKeyViewLoop = true
		hostedWindow.title = PreferencesStrings.accessibilityTitle
		window = hostedWindow
		window.ce_restoreState(for: .preferences)
	}

	override public func show() {
		show(.default)
	}

	public func show(_ selection: PreferencesControllerSelection) {
		let requestedPane: PreferencesPaneIdentifier = switch selection {
		case .notifications: .notifications
		case .style: .style
		case .hiddenPreferences: .hidden
		case .default: .general
		}
		var identifier = requestedPane.rawValue
		if selection == .default,
		   let remembered = Preferences.Internals.selectedPreferencePane.storedValue,
		   Self.paneExists(remembered)
		{
			identifier = remembered
		}
		selectPane(withIdentifier: identifier)
		super.show()
	}

	// MARK: - Sections

	/** The sidebar sections: one for each main pane, one gathering the add-on
	 panes the plugins supply, and one gathering the advanced panes. */
	static func sections() -> [PreferencesSection] {
		PreferencesSectionIdentifier.allCases.map { identifier in
			PreferencesSection(
				identifier: identifier,
				title: sectionTitle(identifier),
				subPages: subPages(in: identifier)
			)
		}
	}

	private static func sectionTitle(_ identifier: PreferencesSectionIdentifier) -> String {
		if let pane = identifier.pane {
			return PreferencesStrings.paneTitle(pane)
		}
		return identifier == .addOns
			? PreferencesStrings.addOnsGroupTitle
			: PreferencesStrings.advancedGroupTitle
	}

	private static func subPages(in section: PreferencesSectionIdentifier) -> [PreferencesSubPage] {
		if let pane = section.pane {
			return [subPage(for: entry(for: pane))]
		}
		if section == .addOns {
			return ([entry(for: .addOns)] + pluginEntries()).map(subPage(for:))
		}
		return PreferencesAdvancedGroup.allCases.map { group in
			PreferencesSubPage(
				identifier: group.identifier,
				title: advancedGroupTitle(group),
				panes: group.panes.map(entry(for:))
			)
		}
	}

	private static func subPage(for pane: PreferencesPaneEntry) -> PreferencesSubPage {
		PreferencesSubPage(identifier: pane.identifier, title: pane.title, panes: [pane])
	}

	private static func advancedGroupTitle(_ group: PreferencesAdvancedGroup) -> String {
		switch group {
		case .connection: PreferencesAdvancedStrings.connection
		case .channels: PreferencesAdvancedStrings.channels
		case .identity: PreferencesAdvancedStrings.identity
		case .media: PreferencesAdvancedStrings.media
		case .system: PreferencesAdvancedStrings.system
		}
	}

	private static func entry(for pane: PreferencesPaneIdentifier) -> PreferencesPaneEntry {
		let descriptor = PreferencesPaneCatalog.descriptor(for: pane.rawValue)
		return PreferencesPaneEntry(
			identifier: pane.rawValue,
			title: PreferencesStrings.paneTitle(pane),
			symbolName: descriptor?.symbolName ?? "gearshape",
			group: descriptor?.group ?? .main
		)
	}

	private static func pluginEntries() -> [PreferencesPaneEntry] {
		SharedApplication.sharedPluginManager().pluginsWithPreferencePanes.enumerated()
			.map { index, plugin in
				let title: String = if let suppliedTitle = plugin.pluginPreferencesPaneMenuItemTitle,
				                       suppliedTitle.isEmpty == false
				{
					suppliedTitle
				} else {
					PreferencesStrings.addOnPaneTitle
				}
				return PreferencesPaneEntry(
					identifier: PreferencesPaneCatalog.pluginIdentifier(at: index),
					title: title,
					symbolName: "puzzlepiece.extension",
					group: .addOns
				)
			}
	}

	/** Whether an identifier still names a pane the window can show. A remembered
	 plugin pane disappears with the plugin, so the check is not only over the
	 enumeration. */
	static func paneExists(_ identifier: String) -> Bool {
		if let index = PreferencesPaneCatalog.pluginIndex(from: identifier) {
			return SharedApplication.sharedPluginManager().pluginsWithPreferencePanes.indices
				.contains(index)
		}
		if PreferencesPaneIdentifier(rawValue: identifier) != nil {
			return true
		}
		return PreferencesAdvancedGroup.allCases.contains { $0.identifier == identifier }
	}

	// MARK: - Selection

	/** Shows whichever sub-page holds `identifier`, which may name a sub-page or
	 one of the panes inside it — a value stored before the advanced panes were
	 grouped still finds its way home. */
	private func selectPane(withIdentifier identifier: String) {
		guard let section = model.sections.first(where: { section in
			section.subPages.contains { $0.contains(identifier) }
		}),
			let subPage = section.subPages.first(where: { $0.contains(identifier) })
		else { return }
		let selection = PreferencesSelection(
			sectionIdentifier: section.identifier,
			subPageIdentifier: subPage.identifier
		)
		if model.select(selection) == false {
			paneChanged(to: selection)
		}
	}

	private func paneChanged(to selection: PreferencesSelection) {
		let identifier = selection.subPageIdentifier
		Preferences.Internals.selectedPreferencePane.value = identifier
		// The two panes whose content is read from outside the key store are
		// refreshed as they are opened rather than polled.
		if identifier == PreferencesPaneIdentifier.style.rawValue {
			model.refreshTheme()
			model.refreshChannelViewFont()
		} else if identifier == PreferencesPaneIdentifier.addOns.rawValue {
			model.refreshAddOnCommands()
		} else if identifier == PreferencesPaneIdentifier.ircv3.rawValue {
			model.refreshIRCv3Connections()
		}
	}

	// MARK: - Closing

	public static func openProxySettingsInSystemPreferences() {
		guard let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Proxies")
		else { return }
		NSWorkspace.shared.open(url)
	}

	public func windowWillClose(_: Notification) {
		notifications.cancelAll()
		releaseFontPanel()
		// The window keeps wherever the user put it: nothing moves the frame
		// before it is written out.
		window.ce_saveState(for: .preferences)
		(delegate as? PreferencesControllerDelegate)?.preferencesDialogWillClose(self)
	}
}
