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

@objc public enum PreferencesControllerSelection: UInt, Sendable {
	case `default`
	case notifications
	case style
	case hiddenPreferences
}

@objc(TDCPreferencesControllerDelegate)
public protocol PreferencesControllerDelegate: AnyObject {
	@objc(preferencesDialogWillClose:)
	func preferencesDialogWillClose(_ sender: PreferencesController)
}

/** The Settings window: an AppKit shell around one SwiftUI content view.

 The shell owns the window, its frame autosave, the toolbar, which pane is
 selected, and everything that needs a window to present — the font panel, the
 folder choosers, the style sheet editor and the alerts. The panes themselves
 are SwiftUI and reach back through `PreferencesPaneActionHandler`. */
@objc(TDCPreferencesController)
@MainActor
public final class PreferencesController: WindowBase, NSToolbarDelegate, NSToolbarItemValidation,
	NSWindowDelegate, PreferencesUserStyleSheetDelegate
{
	let model = PreferencesPaneModel()

	private var paneHistory: [String] = []
	private var paneHistoryIndex = 0
	private var navigatingPaneHistory = false
	private var reloadingThemeBySelection = false
	var fontPanelIsOwned = false
	var previousFontManagerAction: Selector?
	var userStyleSheet: PreferencesUserStyleSheet?
	private lazy var notifications = NotificationSubscriptions()

	override public init() {
		super.init()
		prepareInitialState()
	}

	private func prepareInitialState() {
		model.actions = self
		model.entries = Self.sidebarEntries()
		model.versionFooter = Self.versionFooterString
		model.onSelectionChange = { [weak self] identifier in
			self?.paneSelectionChanged(to: identifier)
		}
		model.refreshAll()
		installWindow()
		prepareNotifications()
	}

	private func prepareNotifications() {
		notifications.observe(.themeListDidChange) { [weak self] _ in
			self?.model.refreshThemes()
		}
		notifications.observe(.TVCMainWindowWillReloadTheme) { [weak self] _ in
			self?.model.isReloadingTheme = true
		}
		notifications.observe(.TVCMainWindowDidReloadTheme) { [weak self] notification in
			self?.themeReloadCompleted(notification)
		}
	}

	// MARK: - Window

	private func installWindow() {
		let hostingController = NSHostingController(rootView: PreferencesRootView(model: model))
		let hostedWindow = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: PreferencesLayout.windowDefaultWidth,
				height: PreferencesLayout.windowDefaultHeight
			),
			styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		hostedWindow.contentViewController = hostingController
		hostedWindow.delegate = self
		hostedWindow.isReleasedWhenClosed = false
		hostedWindow.isRestorable = false
		hostedWindow.tabbingMode = .disallowed
		hostedWindow.toolbarStyle = .unified
		hostedWindow.titlebarSeparatorStyle = .automatic
		hostedWindow.preventsApplicationTerminationWhenModal = false
		hostedWindow.autorecalculatesKeyViewLoop = true
		hostedWindow.title = PreferencesStrings.accessibilityTitle
		hostedWindow.minSize = NSSize(
			width: PreferencesLayout.windowMinimumWidth,
			height: PreferencesLayout.windowMinimumHeight
		)
		window = hostedWindow
		installToolbar()
		restoreWindowFrame()
	}

	private func installToolbar() {
		let toolbar = NSToolbar(identifier: "TDCPreferencesControllerToolbar")
		toolbar.delegate = self
		toolbar.allowsUserCustomization = false
		toolbar.autosavesConfiguration = false
		toolbar.displayMode = .iconOnly
		window.toolbar = toolbar
	}

	private func restoreWindowFrame() {
		window.ce_saveSizeAsDefault()
		window.ce_restoreState(for: Self.self)
		if window.frame.width < PreferencesLayout.windowMinimumWidth
			|| window.frame.height < PreferencesLayout.windowMinimumHeight
		{
			window.setContentSize(NSSize(
				width: PreferencesLayout.windowDefaultWidth,
				height: PreferencesLayout.windowDefaultHeight
			))
			window.center()
		}
	}

	override public func show() {
		show(.default)
	}

	@objc(show:)
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

	// MARK: - Sidebar

	/** The catalogue's panes, with one entry appended to the add-on group for
	 every plugin that supplies a preference pane. */
	static func sidebarEntries() -> [PreferencesSidebarEntry] {
		var items: [PreferencesSidebarEntry] = []
		for pane in PreferencesPaneCatalog.panes {
			items.append(PreferencesSidebarEntry(
				identifier: pane.identifier.rawValue,
				title: PreferencesStrings.paneTitle(pane.identifier),
				symbolName: pane.symbolName,
				group: pane.group
			))
			guard pane.group == .addOns else { continue }
			items.append(contentsOf: pluginSidebarEntries())
		}
		return items
	}

	private static func pluginSidebarEntries() -> [PreferencesSidebarEntry] {
		SharedApplication.sharedPluginManager().pluginsWithPreferencePanes.enumerated()
			.map { index, plugin in
				let title: String = if let suppliedTitle = plugin.pluginPreferencesPaneMenuItemTitle,
				                       suppliedTitle.isEmpty == false
				{
					suppliedTitle
				} else {
					PreferencesStrings.addOnPaneTitle
				}
				return PreferencesSidebarEntry(
					identifier: PreferencesPaneCatalog.pluginIdentifier(at: index),
					title: title,
					symbolName: "puzzlepiece.extension",
					group: .addOns
				)
			}
	}

	/** Whether an identifier still names something the sidebar can show. A
	 remembered plugin pane disappears with the plugin, so the check is not
	 only over the enumeration. */
	static func paneExists(_ identifier: String) -> Bool {
		if let index = PreferencesPaneCatalog.pluginIndex(from: identifier) {
			return SharedApplication.sharedPluginManager().pluginsWithPreferencePanes.indices
				.contains(index)
		}
		return PreferencesPaneIdentifier(rawValue: identifier) != nil
	}

	private static var versionFooterString: String {
		let info = Bundle.main.infoDictionary ?? [:]
		return PreferencesStrings.version(
			marketingVersion: info["CFBundleShortVersionString"] as? String ?? "",
			build: info["CFBundleVersion"] as? String ?? ""
		)
	}

	// MARK: - Pane selection

	private func selectPane(withIdentifier identifier: String) {
		guard Self.paneExists(identifier) else { return }
		guard model.selectedPaneIdentifier != identifier else {
			paneSelectionChanged(to: identifier)
			return
		}
		model.selectedPaneIdentifier = identifier
	}

	private func paneSelectionChanged(to identifier: String) {
		window?.title = model.entries.first { $0.identifier == identifier }?.title
			?? PreferencesStrings.accessibilityTitle
		Preferences.Internals.selectedPreferencePane.value = identifier
		recordPaneInHistory(identifier)
		// The two panes whose content is read from outside the key store are
		// refreshed as they are opened rather than polled.
		if identifier == PreferencesPaneIdentifier.style.rawValue {
			model.refreshThemes()
			model.refreshChannelViewFont()
		} else if identifier == PreferencesPaneIdentifier.addOns.rawValue {
			model.refreshAddOnCommands()
		}
	}

	private func recordPaneInHistory(_ identifier: String) {
		guard navigatingPaneHistory == false else { return }
		if paneHistory.isEmpty == false, paneHistoryIndex + 1 < paneHistory.count {
			paneHistory.removeSubrange((paneHistoryIndex + 1) ..< paneHistory.count)
		}
		paneHistory.append(identifier)
		paneHistoryIndex = paneHistory.count - 1
		window?.toolbar?.validateVisibleItems()
	}

	private var canNavigateBack: Bool {
		paneHistoryIndex > 0
	}

	private var canNavigateForward: Bool {
		paneHistoryIndex + 1 < paneHistory.count
	}

	private func navigate(toHistoryIndex index: Int) {
		guard paneHistory.indices.contains(index) else { return }
		paneHistoryIndex = index
		navigatingPaneHistory = true
		selectPane(withIdentifier: paneHistory[index])
		navigatingPaneHistory = false
		window?.toolbar?.validateVisibleItems()
	}

	@objc private func navigateBack(_: Any?) {
		if canNavigateBack {
			navigate(toHistoryIndex: paneHistoryIndex - 1)
		}
	}

	@objc private func navigateForward(_: Any?) {
		if canNavigateForward {
			navigate(toHistoryIndex: paneHistoryIndex + 1)
		}
	}

	// MARK: - Toolbar

	public func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
		switch item.itemIdentifier {
		case PreferencesIdentifiers.toolbarBack: canNavigateBack
		case PreferencesIdentifiers.toolbarForward: canNavigateForward
		default: true
		}
	}

	public func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
		[
			PreferencesIdentifiers.toolbarBack,
			PreferencesIdentifiers.toolbarForward,
			.flexibleSpace,
		]
	}

	public func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
		[PreferencesIdentifiers.toolbarBack, PreferencesIdentifiers.toolbarForward]
	}

	public func toolbar(
		_: NSToolbar,
		itemForItemIdentifier identifier: NSToolbarItem.Identifier,
		willBeInsertedIntoToolbar _: Bool
	) -> NSToolbarItem? {
		let symbolName: String
		let label: String
		let action: Selector
		switch identifier {
		case PreferencesIdentifiers.toolbarBack:
			symbolName = "chevron.left"
			label = PreferencesStrings.backButtonTitle
			action = #selector(navigateBack(_:))
		case PreferencesIdentifiers.toolbarForward:
			symbolName = "chevron.right"
			label = PreferencesStrings.forwardButtonTitle
			action = #selector(navigateForward(_:))
		default: return nil
		}
		let item = NSToolbarItem(itemIdentifier: identifier)
		item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
		item.label = label
		item.paletteLabel = label
		item.toolTip = label
		item.isBordered = true
		item.isNavigational = true
		item.target = self
		item.action = action
		return item
	}

	// MARK: - Theme reloads

	/// Set by the Style pane before it asks for a reload, so the alert about a
	/// style's forced values is only shown for a reload the user started there.
	func beginThemeSelectionReload() {
		reloadingThemeBySelection = true
	}

	private func themeReloadCompleted(_: Notification) {
		model.isReloadingTheme = false
		model.refreshThemes()
		model.refreshChannelViewFont()
		guard reloadingThemeBySelection else { return }
		reloadingThemeBySelection = false
		warnAboutStyleOverrides()
	}

	private func warnAboutStyleOverrides() {
		var forcedValues: [PreferencesThemeOverride] = []
		if TextualPreferences.themeNicknameFormatPreferenceUserConfigurable() == false {
			forcedValues.append(.nicknameFormat)
		}
		if TextualPreferences.themeTimestampFormatPreferenceUserConfigurable() == false {
			forcedValues.append(.timestampFormat)
		}
		if TextualPreferences.themeChannelViewFontPreferenceUserConfigurable() == false {
			forcedValues.append(.channelViewFont)
		}
		guard forcedValues.isEmpty == false else { return }
		let themeName = TPCThemeController.extractThemeName(TextualPreferences.themeName()) ?? ""
		TDCAlert.alertSheet(
			with: window,
			body: PreferencesStrings.preferredSelectionBody(styleName: themeName, overrides: forcedValues),
			title: PreferencesStrings.preferredSelectionTitle,
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil,
			otherButton: nil,
			suppressionKey: "theme_override_info",
			suppressionText: nil,
			completionBlock: nil
		)
	}

	// MARK: - Closing

	@objc(openProxySettingsInSystemPreferences)
	public static func openProxySettingsInSystemPreferences() {
		guard let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Proxies")
		else { return }
		NSWorkspace.shared.open(url)
	}

	@objc public func windowWillClose(_: Notification) {
		notifications.cancelAll()
		releaseFontPanel()
		// The window keeps whatever size the user gave it: nothing resets the
		// frame before it is written out.
		window.ce_saveState(for: Self.self)
		(delegate as? PreferencesControllerDelegate)?.preferencesDialogWillClose(self)
	}
}
