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

/** The Settings window: an AppKit shell around one SwiftUI content view.

 The shell owns the window, its toolbar of sections, which section and pane are
 shown, the frame it is restored to, and everything that needs a window to
 present — the font panel, the folder choosers, the style sheet editor and the
 alerts. The panes themselves are SwiftUI and reach back through
 `PreferencesPaneActionHandler`. */
@MainActor
public final class PreferencesController: WindowBase, NSToolbarDelegate, NSWindowDelegate,
	PreferencesUserStyleSheetDelegate
{
	private static let toolbarItemPrefix = "TDCPreferencesControllerSection."

	let model = PreferencesPaneModel()

	private var contentController: NSHostingController<PreferencesRootView>!
	private var reloadingThemeBySelection = false

	/// Which pane each section was left on, so coming back to a section comes
	/// back to the segment the user was reading.
	private var lastPaneBySection: [PreferencesSectionIdentifier: String] = [:]

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
		model.sections = Self.sections()
		model.onSelectionChange = { [weak self] selection in
			self?.paneChanged(to: selection, animate: true)
		}
		model.refreshAll()
		installWindow()
		prepareNotifications()
	}

	private func prepareNotifications() {
		notifications.observe(.themeListDidChange) { [weak self] _ in
			self?.model.refreshThemes()
		}
		notifications.observe(.mainWindowWillReloadTheme) { [weak self] _ in
			self?.model.isReloadingTheme = true
		}
		notifications.observe(.mainWindowDidReloadTheme) { [weak self] notification in
			self?.themeReloadCompleted(notification)
		}
	}

	// MARK: - Window

	private func installWindow() {
		let hostingController = NSHostingController(rootView: PreferencesRootView(model: model))
		contentController = hostingController
		let hostedWindow = PreferencesWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: PreferencesLayout.windowWidth,
				height: PreferencesLayout.windowMinimumHeight
			),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)
		hostedWindow.contentViewController = hostingController
		hostedWindow.delegate = self
		hostedWindow.isReleasedWhenClosed = false
		hostedWindow.isRestorable = false
		hostedWindow.tabbingMode = .disallowed
		hostedWindow.toolbarStyle = .preference
		hostedWindow.preventsApplicationTerminationWhenModal = false
		hostedWindow.autorecalculatesKeyViewLoop = true
		hostedWindow.title = PreferencesStrings.accessibilityTitle
		window = hostedWindow
		installToolbar()
		window.ce_restoreState(for: .preferences)
	}

	private func installToolbar() {
		let toolbar = NSToolbar(identifier: "TDCPreferencesControllerToolbar")
		toolbar.delegate = self
		toolbar.allowsUserCustomization = false
		toolbar.autosavesConfiguration = false
		toolbar.displayMode = .iconAndLabel
		window.toolbar = toolbar
	}

	/** Grows or shrinks the window to the pane that is showing, keeping its
	 top-left corner and its width, the way a settings window behaves. */
	private func resizeToFitContent(animate: Bool) {
		guard let window, let contentView = window.contentView else { return }
		contentView.layoutSubtreeIfNeeded()
		let screen = window.screen ?? NSScreen.main
		let available = screen.map { Double($0.visibleFrame.height) }
			?? PreferencesLayout.windowMinimumHeight
		let height = min(
			max(contentController.view.fittingSize.height, PreferencesLayout.windowMinimumHeight),
			available - PreferencesLayout.windowScreenInset
		)
		let current = window.contentRect(forFrameRect: window.frame)
		guard abs(current.height - height) > 0.5
			|| abs(current.width - PreferencesLayout.windowWidth) > 0.5
		else { return }
		let content = NSRect(
			x: current.minX,
			y: current.maxY - height,
			width: PreferencesLayout.windowWidth,
			height: height
		)
		/* A taller pane grows downwards from the anchored top edge, so keep the
		 whole window above the Dock and inside the screen. */
		var frame = window.frameRect(forContentRect: content)
		if let screen {
			frame = window.constrainFrameRect(frame, to: screen)
		}
		window.setFrame(frame, display: true, animate: animate)
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
		selectPane(withIdentifier: identifier, animate: false)
		super.show()
	}

	// MARK: - Sections

	/** The toolbar's sections: one for each main pane, one gathering the add-on
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
	private func selectPane(withIdentifier identifier: String, animate: Bool) {
		guard let section = model.sections.first(where: { section in
			section.subPages.contains { $0.contains(identifier) }
		}),
			let subPage = section.subPages.first(where: { $0.contains(identifier) })
		else { return }
		let selection = PreferencesSelection(
			sectionIdentifier: section.identifier,
			subPageIdentifier: subPage.identifier
		)
		let changed = model.select(selection)
		window?.toolbar?.selectedItemIdentifier = Self.toolbarIdentifier(for: section.identifier)
		window?.title = section.title
		if changed == false {
			// The model publishes only changes, so finish an idempotent request here.
			paneChanged(to: selection, animate: animate)
		}
	}

	private func paneChanged(to selection: PreferencesSelection, animate: Bool) {
		let identifier = selection.subPageIdentifier
		lastPaneBySection[selection.sectionIdentifier] = identifier
		Preferences.Internals.selectedPreferencePane.value = identifier
		// The two panes whose content is read from outside the key store are
		// refreshed as they are opened rather than polled.
		if identifier == PreferencesPaneIdentifier.style.rawValue {
			model.refreshThemes()
			model.refreshChannelViewFont()
		} else if identifier == PreferencesPaneIdentifier.addOns.rawValue {
			model.refreshAddOnCommands()
		}
		// The hosted view has not laid the new pane out yet.
		DispatchQueue.main.async { [weak self] in
			self?.resizeToFitContent(animate: animate)
		}
	}

	@objc private func selectSection(_ sender: NSToolbarItem) {
		let raw = sender.itemIdentifier.rawValue.dropFirst(Self.toolbarItemPrefix.count)
		guard let identifier = PreferencesSectionIdentifier(rawValue: String(raw)),
		      let section = model.sections.first(where: { $0.identifier == identifier }),
		      let pane = lastPaneBySection[identifier] ?? section.subPages.first?.identifier
		else { return }
		selectPane(withIdentifier: pane, animate: true)
	}

	// MARK: - Toolbar

	private static func toolbarIdentifier(
		for section: PreferencesSectionIdentifier
	) -> NSToolbarItem.Identifier {
		NSToolbarItem.Identifier(toolbarItemPrefix + section.rawValue)
	}

	private var sectionItemIdentifiers: [NSToolbarItem.Identifier] {
		model.sections.map { Self.toolbarIdentifier(for: $0.identifier) }
	}

	public func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
		sectionItemIdentifiers
	}

	public func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
		sectionItemIdentifiers
	}

	public func toolbarSelectableItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
		sectionItemIdentifiers
	}

	public func toolbar(
		_: NSToolbar,
		itemForItemIdentifier identifier: NSToolbarItem.Identifier,
		willBeInsertedIntoToolbar _: Bool
	) -> NSToolbarItem? {
		let raw = identifier.rawValue.dropFirst(Self.toolbarItemPrefix.count)
		guard let sectionIdentifier = PreferencesSectionIdentifier(rawValue: String(raw)),
		      let section = model.sections.first(where: { $0.identifier == sectionIdentifier })
		else { return nil }
		let item = NSToolbarItem(itemIdentifier: identifier)
		item.image = NSImage(
			systemSymbolName: section.symbolName,
			accessibilityDescription: section.title
		)
		item.label = section.title
		item.paletteLabel = section.title
		item.toolTip = section.title
		item.target = self
		item.action = #selector(selectSection(_:))
		/* The label is what VoiceOver reads for a toolbar item; the image's
		 accessibility description above covers the icon on its own. */
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
