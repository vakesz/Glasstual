/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

@objc(TDCPreferencesControllerSelection)
public enum PreferencesControllerSelection: UInt {
	case `default` = 0
	case notifications
	case style
	case hiddenPreferences
}

@objc(TDCPreferencesControllerDelegate)
public protocol PreferencesControllerDelegate: AnyObject {
	@objc(preferencesDialogWillClose:)
	func preferencesDialogWillClose(_ sender: PreferencesController)
}

private enum PreferencesLayout {
	static let sidebarMinimumWidth = 200.0
	static let sidebarMaximumWidth = 260.0
	static let sidebarPreferredWidth = 215.0
	static let paneContentInset = 20.0
	static let windowMinimumWidth = 980.0
	static let windowMinimumHeight = 600.0
}

private enum PreferencesIdentifiers {
	static let selectedPaneDefaultsKey = "TDCPreferencesController -> Selected Pane"
	static let toolbarBack = NSToolbarItem.Identifier("TDCPreferencesControllerBack")
	static let toolbarForward = NSToolbarItem.Identifier("TDCPreferencesControllerForward")
	static let paneCell = NSUserInterfaceItemIdentifier("TDCPreferencesControllerPaneCell")
	static let groupCell = NSUserInterfaceItemIdentifier("TDCPreferencesControllerGroupCell")
}

private final class PreferencesSidebarItem: NSObject {
	let identifier: String?
	let title: String
	let symbolName: String?
	let children: [PreferencesSidebarItem]?

	init(
		identifier: String? = nil,
		title: String,
		symbolName: String? = nil,
		children: [PreferencesSidebarItem]? = nil
	) {
		self.identifier = identifier
		self.title = title
		self.symbolName = symbolName
		self.children = children
	}

	var isGroup: Bool {
		children != nil
	}
}

private final class PreferencesPaneContainerView: NSView {
	override var isFlipped: Bool {
		true
	}
}

struct PreferencesPaneDescriptor: Equatable {
	let identifier: String
	let symbolName: String
	let contentViewKey: String
	let group: String
}

enum PreferencesPaneCatalog {
	static let mainGroup = "main"
	static let addonsGroup = "addons"
	static let advancedGroup = "advanced"

	static let panes = [
		PreferencesPaneDescriptor(
			identifier: "general",
			symbolName: "gearshape",
			contentViewKey: "contentViewGeneral",
			group: mainGroup
		),
		PreferencesPaneDescriptor(
			identifier: "behavior",
			symbolName: "slider.horizontal.3",
			contentViewKey: "contentViewBehavior",
			group: mainGroup
		),
		PreferencesPaneDescriptor(
			identifier: "notifications",
			symbolName: "bell",
			contentViewKey: "contentViewNotifications",
			group: mainGroup
		),
		PreferencesPaneDescriptor(
			identifier: "highlights",
			symbolName: "text.magnifyingglass",
			contentViewKey: "contentViewHighlights",
			group: mainGroup
		),
		PreferencesPaneDescriptor(
			identifier: "interface",
			symbolName: "macwindow",
			contentViewKey: "contentViewInterface",
			group: mainGroup
		),
		PreferencesPaneDescriptor(
			identifier: "style",
			symbolName: "paintbrush",
			contentViewKey: "contentViewStyle",
			group: mainGroup
		),
		PreferencesPaneDescriptor(
			identifier: "controls",
			symbolName: "keyboard",
			contentViewKey: "contentViewControls",
			group: mainGroup
		),
		PreferencesPaneDescriptor(
			identifier: "addons",
			symbolName: "puzzlepiece.extension",
			contentViewKey: "contentViewInstalledAddons",
			group: addonsGroup
		),
		PreferencesPaneDescriptor(
			identifier: "channelManagement",
			symbolName: "person.2",
			contentViewKey: "contentViewChannelManagement",
			group: advancedGroup
		),
		PreferencesPaneDescriptor(
			identifier: "commandScope",
			symbolName: "terminal",
			contentViewKey: "contentViewCommandScope",
			group: advancedGroup
		),
		PreferencesPaneDescriptor(
			identifier: "compatibility",
			symbolName: "wrench.and.screwdriver",
			contentViewKey: "contentViewCompatibility",
			group: advancedGroup
		),
		PreferencesPaneDescriptor(
			identifier: "floodControl",
			symbolName: "timer",
			contentViewKey: "contentViewFloodControl",
			group: advancedGroup
		),
		PreferencesPaneDescriptor(
			identifier: "incomingData",
			symbolName: "arrow.down.circle",
			contentViewKey: "contentViewIncomingData",
			group: advancedGroup
		),
		PreferencesPaneDescriptor(
			identifier: "fileTransfers",
			symbolName: "arrow.down.app",
			contentViewKey: "contentViewFileTransfers",
			group: advancedGroup
		),
		PreferencesPaneDescriptor(
			identifier: "inlineMedia",
			symbolName: "photo",
			contentViewKey: "contentViewInlineMedia",
			group: advancedGroup
		),
		PreferencesPaneDescriptor(
			identifier: "logLocation",
			symbolName: "folder",
			contentViewKey: "contentViewLogLocation",
			group: advancedGroup
		),
		PreferencesPaneDescriptor(
			identifier: "defaultIdentity",
			symbolName: "person.crop.circle",
			contentViewKey: "contentViewDefaultIdentity",
			group: advancedGroup
		),
		PreferencesPaneDescriptor(
			identifier: "defaultIRCopMessages",
			symbolName: "shield",
			contentViewKey: "contentViewDefaultIRCopMessages",
			group: advancedGroup
		),
		PreferencesPaneDescriptor(
			identifier: "hidden",
			symbolName: "eye.slash",
			contentViewKey: "contentViewHiddenPreferences",
			group: advancedGroup
		),
	]

	static func descriptor(for identifier: String) -> PreferencesPaneDescriptor? {
		panes.first { $0.identifier == identifier }
	}

	static func pluginIdentifier(at index: Int) -> String {
		"plugin-\(index)"
	}

	static func pluginIndex(from identifier: String) -> Int? {
		guard identifier.hasPrefix("plugin-") else { return nil }
		return Int(identifier.dropFirst(7))
	}
}

enum PreferencesValueValidation {
	static let scrollbackSaveRange = 100 ... 50000
	static let scrollbackVisibleRange = 100 ... 15000
	static let inlineMediaWidthRange = 40 ... 2000
	static let inlineMediaHeightRange = 0 ... 6000
	static let fileTransferPortRange = 1024 ... 65535

	static func clamped(_ value: Int, to range: ClosedRange<Int>, allowingZero: Bool = false) -> Int {
		if allowingZero, value == 0 {
			return 0
		}
		return min(max(value, range.lowerBound), range.upperBound)
	}
}

@objc(TXColorUnarchiveFromDataTransformer)
private final class ColorUnarchiveFromDataTransformer: NSSecureUnarchiveFromDataTransformer {
	override class func transformedValueClass() -> AnyClass {
		NSColor.self
	}

	override class func allowsReverseTransformation() -> Bool {
		true
	}

	override class var allowedTopLevelClasses: [AnyClass] {
		super.allowedTopLevelClasses + [NSColor.self]
	}

	override func transformedValue(_ value: Any?) -> Any? {
		if let color = value as? NSColor {
			return color
		}
		guard let data = value as? Data else { return nil }
		return NSKeyedUnarchiver.legacyCompatUnarchivedObject(of: NSColor.self, from: data)
	}

	override func reverseTransformedValue(_ value: Any?) -> Any? {
		guard let color = value as? NSColor else { return nil }
		return try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
	}
}

@objc(TDCPreferencesController)
@MainActor
public final class PreferencesController: WindowBase, NSOutlineViewDataSource, NSOutlineViewDelegate, NSToolbarDelegate,
	NSToolbarItemValidation, @unchecked Sendable
{
	@IBOutlet private var excludeKeywordsArrayController: NSArrayController!
	@IBOutlet private var highlightKeywordsArrayController: NSArrayController!
	@IBOutlet private var installedScriptsController: NSArrayController!
	@IBOutlet private var addExcludeKeywordButton: NSButton!
	@IBOutlet private var highlightNicknameButton: NSButton!
	@IBOutlet private var themeSelectionButton: NSPopUpButton!
	@IBOutlet private var transcriptFolderButton: NSPopUpButton!
	@IBOutlet private var fileTransferDownloadDestinationButton: NSPopUpButton!
	@IBOutlet private var excludeKeywordsTable: NSTableView!
	@IBOutlet private var installedScriptsTable: NSTableView!
	@IBOutlet private var highlightKeywordsTable: NSTableView!
	@IBOutlet private var fileTransferManuallyEnteredIPAddressTextField: NSTextField!
	@IBOutlet private var contentViewGeneral: NSView!
	@IBOutlet private var contentViewHighlights: NSView!
	@IBOutlet private var contentViewNotifications: NSView!
	@IBOutlet private var contentViewBehavior: NSView!
	@IBOutlet private var contentViewControls: NSView!
	@IBOutlet private var contentViewInterface: NSView!
	@IBOutlet private var contentViewStyle: NSView!
	@IBOutlet private var contentViewInstalledAddons: NSView!
	@IBOutlet private var contentViewChannelManagement: NSView!
	@IBOutlet private var contentViewCommandScope: NSView!
	@IBOutlet private var contentViewCompatibility: NSView!
	@IBOutlet private var contentViewFloodControl: NSView!
	@IBOutlet private var contentViewIncomingData: NSView!
	@IBOutlet private var contentViewFileTransfers: NSView!
	@IBOutlet private var contentViewInlineMedia: NSView!
	@IBOutlet private var contentViewLogLocation: NSView!
	@IBOutlet private var contentViewDefaultIdentity: NSView!
	@IBOutlet private var contentViewDefaultIRCopMessages: NSView!
	@IBOutlet private var contentViewHiddenPreferences: NSView!
	@IBOutlet private var forwardNoticeToServerConsoleButton: NSButton!
	@IBOutlet private var forwardNoticeToSelectedChannelButton: NSButton!
	@IBOutlet private var forwardNoticeToQueryButton: NSButton!
	@IBOutlet private var inlineMediaEnabledButton: NSButton!
	@IBOutlet private var notificationControllerHostView: NSView!
	@IBOutlet private var notificationController: NotificationConfigurationViewController!

	private var splitViewController: NSSplitViewController!
	private var sidebarOutlineView: NSOutlineView!
	private var paneScrollView: NSScrollView!
	private var paneContainerView: PreferencesPaneContainerView!
	private weak var presentedPaneView: NSView?
	private var sidebarItems: [PreferencesSidebarItem] = []
	private var sidebarPaneItems: [PreferencesSidebarItem] = []
	private var selectedPaneIdentifier: String?
	private var paneHistory: [String] = []
	private var paneHistoryIndex = 0
	private var navigatingPaneHistory = false
	private var updatingSidebarSelection = false
	private var reloadingTheme = false
	private var reloadingThemeBySelection = false
	private var fontPanelIsOwned = false
	private var previousFontManagerAction: Selector?
	private var userStyleSheet: PreferencesUserStyleSheet?
	private var nibTopLevelObjects: [Any] = []

	override public init() {
		super.init()
		MainActor.assumeIsolated {
			prepareInitialState()
		}
	}

	private func prepareInitialState() {
		var objects: NSArray?
		Bundle.main.loadNibNamed("TDCPreferences", owner: self, topLevelObjects: &objects)
		nibTopLevelObjects = objects as? [Any] ?? []
	}

	override public nonisolated func awakeFromNib() {
		super.awakeFromNib()
		MainActor.assumeIsolated {
			finishAwakeningFromNib()
		}
	}

	private func finishAwakeningFromNib() {
		prepareNotifications()
		notificationController.attachToView(notificationControllerHostView)
		updateFileTransferDownloadDestinationFolder()
		updateForwardNoticeToMatrix()
		updateInlineMediaEnabled()
		updateThemeSelection()
		updateTranscriptFolder()
		onChangedHighlightType(nil)
		onFileTransferIPAddressDetectionMethodChanged(nil)
		installedScriptsTable.sortDescriptors = [NSSortDescriptor(
			key: "string",
			ascending: true,
			selector: #selector(NSString.caseInsensitiveCompare(_:))
		)]
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(onThemeListDidChange(_:)),
			name: .themeListDidChange,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(onThemeWillReload(_:)),
			name: .TVCMainWindowWillReloadTheme,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(onThemeReloadComplete(_:)),
			name: .TVCMainWindowDidReloadTheme,
			object: nil
		)
		contentViewGeneral.layoutSubtreeIfNeeded()
		installAccessibilityLabels()
		installSettingsShell()
		restoreWindowFrame()
		window.autorecalculatesKeyViewLoop = true
		window.preventsApplicationTerminationWhenModal = false
	}

	private func prepareNotifications() {
		let eventTypes: [TXNotificationType?] = [
			.addressBookMatch, nil, .connect, .disconnect, nil, .highlight, nil, .invite, .kick, nil,
			.channelMessage, .channelNotice, nil, .newPrivateMessage, .privateMessage, .privateNotice, nil,
			.userJoined, .userParted, .userDisconnected, nil, .fileTransferReceiveRequested, nil,
			.fileTransferSendSuccessful, .fileTransferReceiveSuccessful, nil,
			.fileTransferSendFailed, .fileTransferReceiveFailed,
		]
		notificationController.notifications = eventTypes.map { eventType in
			guard let eventType else { return " " }
			return PreferencesNotificationConfiguration.object(withEventType: eventType)
		}
	}

	override public nonisolated func show() {
		MainActor.assumeIsolated {
			show(.default)
		}
	}

	@objc(show:)
	public func show(_ selection: PreferencesControllerSelection) {
		var identifier = switch selection {
		case .notifications: "notifications"
		case .style: "style"
		case .hiddenPreferences: "hidden"
		case .default: "general"
		}
		if selection == .default,
		   let remembered = UserDefaults.standard.string(forKey: PreferencesIdentifiers.selectedPaneDefaultsKey),
		   viewForSettingsPaneIdentifier(remembered) != nil
		{
			identifier = remembered
		}
		selectPane(withIdentifier: identifier)
		super.show()
	}

	@objc(settingsSidebarCatalog)
	public func settingsSidebarCatalog() -> [[String: String]] {
		var items: [[String: String]] = []
		for pane in PreferencesPaneCatalog.panes {
			items.append([
				"id": pane.identifier,
				"title": LocalizedKey("TDCPreferencesController[sb-\(pane.identifier)]"),
				"symbol": pane.symbolName,
				"group": pane.group,
			])
			guard pane.group == PreferencesPaneCatalog.addonsGroup else { continue }
			for (index, plugin) in TXSharedApplication.sharedPluginManager().pluginsWithPreferencePanes.enumerated() {
				let title = plugin.pluginPreferencesPaneMenuItemTitle?.isEmpty == false
					? plugin.pluginPreferencesPaneMenuItemTitle!
					: LocalizedKey("TDCPreferencesController[sb-plugin]")
				items.append([
					"id": PreferencesPaneCatalog.pluginIdentifier(at: index),
					"title": title,
					"symbol": "puzzlepiece.extension",
					"group": PreferencesPaneCatalog.addonsGroup,
				])
			}
		}
		return items
	}

	@objc(viewForSettingsPaneIdentifier:)
	public func viewForSettingsPaneIdentifier(_ identifier: String) -> NSView? {
		if let pluginIndex = PreferencesPaneCatalog.pluginIndex(from: identifier) {
			let plugins = TXSharedApplication.sharedPluginManager().pluginsWithPreferencePanes
			guard plugins.indices.contains(pluginIndex) else { return nil }
			return plugins[pluginIndex].pluginPreferencesPaneView
		}
		guard let pane = PreferencesPaneCatalog.descriptor(for: identifier) else { return nil }
		return value(forKey: pane.contentViewKey) as? NSView
	}

	private func sidebarItem(for identifier: String) -> PreferencesSidebarItem? {
		sidebarPaneItems.first { $0.identifier == identifier }
	}

	private func installSettingsShell() {
		window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
		window.toolbarStyle = .unified
		window.titlebarSeparatorStyle = .automatic
		window.titlebarAppearsTransparent = false
		window.minSize = NSSize(
			width: PreferencesLayout.windowMinimumWidth,
			height: PreferencesLayout.windowMinimumHeight
		)
		window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		buildSidebarItems()
		paneHistory = []
		paneHistoryIndex = 0

		let splitController = NSSplitViewController()
		splitController.splitView.dividerStyle = .thin
		let detailController = makeDetailViewController()
		let sidebarItem = NSSplitViewItem(sidebarWithViewController: makeSidebarViewController())
		sidebarItem.canCollapse = false
		sidebarItem.minimumThickness = PreferencesLayout.sidebarMinimumWidth
		sidebarItem.maximumThickness = PreferencesLayout.sidebarMaximumWidth
		sidebarItem.preferredThicknessFraction = PreferencesLayout.sidebarPreferredWidth / PreferencesLayout
			.windowMinimumWidth
		splitController.addSplitViewItem(sidebarItem)
		let detailItem = NSSplitViewItem(viewController: detailController)
		detailItem.minimumThickness = PreferencesLayout.windowMinimumWidth - PreferencesLayout.sidebarMaximumWidth
		splitController.addSplitViewItem(detailItem)
		splitViewController = splitController
		window.contentViewController = splitController

		let toolbar = NSToolbar(identifier: "TDCPreferencesControllerToolbar")
		toolbar.delegate = self
		toolbar.allowsUserCustomization = false
		toolbar.autosavesConfiguration = false
		toolbar.displayMode = .iconOnly
		window.toolbar = toolbar
	}

	private func buildSidebarItems() {
		var rootItems: [PreferencesSidebarItem] = []
		var paneItems: [PreferencesSidebarItem] = []
		var addonItems: [PreferencesSidebarItem] = []
		var advancedItems: [PreferencesSidebarItem] = []
		for entry in settingsSidebarCatalog() {
			guard let identifier = entry["id"], let title = entry["title"],
			      let symbol = entry["symbol"] else { continue }
			let item = PreferencesSidebarItem(identifier: identifier, title: title, symbolName: symbol)
			paneItems.append(item)
			switch entry["group"] {
			case PreferencesPaneCatalog.addonsGroup: addonItems.append(item)
			case PreferencesPaneCatalog.advancedGroup: advancedItems.append(item)
			default: rootItems.append(item)
			}
		}
		if !addonItems.isEmpty {
			rootItems.append(PreferencesSidebarItem(
				title: LocalizedKey("TDCPreferencesController[sb-gr-ad]"),
				children: addonItems
			))
		}
		if !advancedItems.isEmpty {
			rootItems.append(PreferencesSidebarItem(
				title: LocalizedKey("TDCPreferencesController[sb-gr-av]"),
				children: advancedItems
			))
		}
		sidebarItems = rootItems
		sidebarPaneItems = paneItems
	}

	private func makeSidebarViewController() -> NSViewController {
		let outlineView = NSOutlineView(frame: .zero)
		outlineView.style = .sourceList
		outlineView.headerView = nil
		outlineView.floatsGroupRows = false
		outlineView.indentationPerLevel = 0
		outlineView.rowSizeStyle = .default
		outlineView.allowsEmptySelection = false
		outlineView.allowsMultipleSelection = false
		outlineView.autoresizesOutlineColumn = false
		outlineView.focusRingType = .none
		outlineView.setAccessibilityLabel(LocalizedKey("TDCPreferencesController[sb-tt]"))
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
		column.resizingMask = NSTableColumn.ResizingOptions.autoresizingMask
		outlineView.addTableColumn(column)
		outlineView.outlineTableColumn = column
		outlineView.dataSource = self
		outlineView.delegate = self
		sidebarOutlineView = outlineView

		let scrollView = NSScrollView(frame: .zero)
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.documentView = outlineView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = false
		scrollView.automaticallyAdjustsContentInsets = true
		let versionLabel = NSTextField(labelWithString: versionFooterString)
		versionLabel.translatesAutoresizingMaskIntoConstraints = false
		versionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		versionLabel.textColor = .tertiaryLabelColor
		versionLabel.lineBreakMode = .byTruncatingTail
		versionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		let sidebarView = NSView(frame: NSRect(
			x: 0,
			y: 0,
			width: PreferencesLayout.sidebarPreferredWidth,
			height: PreferencesLayout.windowMinimumHeight
		))
		sidebarView.addSubview(scrollView)
		sidebarView.addSubview(versionLabel)
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: sidebarView.topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
			versionLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
			versionLabel.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 18),
			versionLabel.trailingAnchor.constraint(lessThanOrEqualTo: sidebarView.trailingAnchor, constant: -18),
			versionLabel.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor, constant: -10),
		])
		let controller = NSViewController()
		controller.view = sidebarView
		outlineView.reloadData()
		outlineView.expandItem(nil, expandChildren: true)
		return controller
	}

	private var versionFooterString: String {
		let info = Bundle.main.infoDictionary ?? [:]
		return LocalizedKey(
			"TDCPreferencesController[sb-vers]",
			info["CFBundleShortVersionString"] as? String ?? "",
			info["CFBundleVersion"] as? String ?? ""
		)
	}

	private func makeDetailViewController() -> NSViewController {
		let containerView = PreferencesPaneContainerView(frame: .zero)
		containerView.translatesAutoresizingMaskIntoConstraints = false
		paneContainerView = containerView
		let scrollView = NSScrollView(frame: NSRect(
			x: 0,
			y: 0,
			width: PreferencesLayout.windowMinimumWidth - PreferencesLayout.sidebarPreferredWidth,
			height: PreferencesLayout.windowMinimumHeight
		))
		scrollView.documentView = containerView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = false
		scrollView.automaticallyAdjustsContentInsets = true
		paneScrollView = scrollView
		let clipView = scrollView.contentView
		let width = containerView.widthAnchor.constraint(equalTo: clipView.widthAnchor)
		width.priority = .defaultHigh
		let height = containerView.heightAnchor.constraint(equalTo: clipView.heightAnchor)
		height.priority = .defaultHigh
		NSLayoutConstraint.activate([
			containerView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
			containerView.topAnchor.constraint(equalTo: clipView.topAnchor),
			containerView.widthAnchor.constraint(greaterThanOrEqualTo: clipView.widthAnchor),
			containerView.heightAnchor.constraint(greaterThanOrEqualTo: clipView.heightAnchor),
			width, height,
		])
		let controller = NSViewController()
		controller.view = scrollView
		return controller
	}

	private func presentPaneView(_ paneView: NSView) {
		guard presentedPaneView !== paneView else { return }
		presentedPaneView?.removeFromSuperview()
		presentedPaneView = paneView
		guard let containerView = paneContainerView else {
			presentedPaneView = nil
			return
		}
		paneView.translatesAutoresizingMaskIntoConstraints = false
		containerView.addSubview(paneView)
		NSLayoutConstraint.activate([
			paneView.topAnchor.constraint(
				equalTo: containerView.topAnchor,
				constant: PreferencesLayout.paneContentInset
			),
			paneView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
			paneView.leadingAnchor.constraint(
				greaterThanOrEqualTo: containerView.leadingAnchor,
				constant: PreferencesLayout.paneContentInset
			),
			containerView.bottomAnchor.constraint(
				greaterThanOrEqualTo: paneView.bottomAnchor,
				constant: PreferencesLayout.paneContentInset
			),
		])
		containerView.layoutSubtreeIfNeeded()
		scrollPresentedPaneToTop()
	}

	private func scrollPresentedPaneToTop() {
		let clipView = paneScrollView.contentView
		var bounds = clipView.bounds
		bounds.origin = NSPoint(x: 0, y: -clipView.contentInsets.top)
		clipView.scroll(to: clipView.constrainBoundsRect(bounds).origin)
		paneScrollView.reflectScrolledClipView(clipView)
	}

	private func selectPane(withIdentifier identifier: String) {
		guard let item = sidebarItem(for: identifier),
		      let paneView = viewForSettingsPaneIdentifier(identifier) else { return }
		if selectedPaneIdentifier == identifier {
			syncSidebarSelection(to: item)
			return
		}
		selectedPaneIdentifier = identifier
		presentPaneView(paneView)
		window.title = item.title
		syncSidebarSelection(to: item)
		recordPaneInHistory(identifier)
		UserDefaults.standard.set(identifier, forKey: PreferencesIdentifiers.selectedPaneDefaultsKey)
	}

	private func syncSidebarSelection(to item: PreferencesSidebarItem) {
		let row = sidebarOutlineView.row(forItem: item)
		guard row >= 0, sidebarOutlineView.selectedRow != row else { return }
		updatingSidebarSelection = true
		sidebarOutlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		sidebarOutlineView.scrollRowToVisible(row)
		updatingSidebarSelection = false
	}

	private func recordPaneInHistory(_ identifier: String) {
		guard !navigatingPaneHistory else { return }
		if !paneHistory.isEmpty, paneHistoryIndex + 1 < paneHistory.count {
			paneHistory.removeSubrange((paneHistoryIndex + 1) ..< paneHistory.count)
		}
		paneHistory.append(identifier)
		paneHistoryIndex = paneHistory.count - 1
		window.toolbar?.validateVisibleItems()
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
		window.toolbar?.validateVisibleItems()
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

	public func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
		switch item.itemIdentifier {
		case PreferencesIdentifiers.toolbarBack: canNavigateBack
		case PreferencesIdentifiers.toolbarForward: canNavigateForward
		default: true
		}
	}

	public func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
		[
			.sidebarTrackingSeparator,
			PreferencesIdentifiers.toolbarBack,
			PreferencesIdentifiers.toolbarForward,
			.flexibleSpace,
		]
	}

	public func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
		[.sidebarTrackingSeparator, PreferencesIdentifiers.toolbarBack, PreferencesIdentifiers.toolbarForward]
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
			label = LocalizedKey("TDCPreferencesController[tb-back]")
			action = #selector(navigateBack(_:))
		case PreferencesIdentifiers.toolbarForward:
			symbolName = "chevron.right"
			label = LocalizedKey("TDCPreferencesController[tb-forward]")
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

	public func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		guard let item = item as? PreferencesSidebarItem else { return sidebarItems.count }
		return item.children?.count ?? 0
	}

	public func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		guard let item = item as? PreferencesSidebarItem else { return sidebarItems[index] }
		return item.children![index]
	}

	public func outlineView(_: NSOutlineView,
	                        isItemExpandable item: Any) -> Bool
	{
		(item as! PreferencesSidebarItem).isGroup
	}

	public func outlineView(_: NSOutlineView,
	                        isGroupItem item: Any) -> Bool
	{
		(item as! PreferencesSidebarItem).isGroup
	}

	public func outlineView(_: NSOutlineView,
	                        shouldSelectItem item: Any) -> Bool
	{
		!(item as! PreferencesSidebarItem).isGroup
	}

	public func outlineView(_: NSOutlineView, shouldShowOutlineCellForItem _: Any) -> Bool {
		false
	}

	public func outlineView(_: NSOutlineView, shouldCollapseItem _: Any) -> Bool {
		false
	}

	public func outlineView(_ outlineView: NSOutlineView, viewFor _: NSTableColumn?, item: Any) -> NSView? {
		let sidebarItem = item as! PreferencesSidebarItem
		let identifier = sidebarItem.isGroup ? PreferencesIdentifiers.groupCell : PreferencesIdentifiers.paneCell
		let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
			?? makeSidebarCellView(identifier: identifier, hasImageView: !sidebarItem.isGroup)
		cell.textField?.stringValue = sidebarItem.title
		if !sidebarItem.isGroup, let symbolName = sidebarItem.symbolName {
			cell.imageView?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: sidebarItem.title)
		}
		cell.setAccessibilityLabel(sidebarItem.title)
		return cell
	}

	private func makeSidebarCellView(identifier: NSUserInterfaceItemIdentifier, hasImageView: Bool) -> NSTableCellView {
		let cell = NSTableCellView(frame: .zero)
		cell.identifier = identifier
		let textField = NSTextField(labelWithString: "")
		textField.translatesAutoresizingMaskIntoConstraints = false
		textField.lineBreakMode = .byTruncatingTail
		cell.addSubview(textField)
		cell.textField = textField
		NSLayoutConstraint.activate([
			textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
		])
		guard hasImageView else {
			textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor).isActive = true
			return cell
		}
		let imageView = NSImageView(image: NSImage())
		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.imageScaling = .scaleProportionallyDown
		imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
		cell.addSubview(imageView)
		cell.imageView = imageView
		NSLayoutConstraint.activate([
			imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
			imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			imageView.widthAnchor.constraint(equalToConstant: 22),
			imageView.heightAnchor.constraint(equalToConstant: 22),
			textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
		])
		return cell
	}

	public func outlineViewSelectionDidChange(_: Notification) {
		guard !updatingSidebarSelection,
		      let item = sidebarOutlineView.item(atRow: sidebarOutlineView.selectedRow) as? PreferencesSidebarItem,
		      !item.isGroup,
		      let identifier = item.identifier
		else { return }
		selectPane(withIdentifier: identifier)
	}

	private func installAccessibilityLabels() {
		let themeLabel = LocalizedKey("TDCPreferencesController[ax-theme]")
		themeSelectionButton.toolTip = themeLabel
		themeSelectionButton.setAccessibilityLabel(themeLabel)
		let transcriptLabel = LocalizedKey("TDCPreferencesController[ax-transcript-folder]")
		transcriptFolderButton.toolTip = transcriptLabel
		transcriptFolderButton.setAccessibilityLabel(transcriptLabel)
		let downloadLabel = LocalizedKey("TDCPreferencesController[ax-download-folder]")
		fileTransferDownloadDestinationButton.toolTip = downloadLabel
		fileTransferDownloadDestinationButton.setAccessibilityLabel(downloadLabel)
	}

	private func restoreWindowFrame() {
		window.saveSizeAsDefault()
		window.perform(NSSelectorFromString("restoreWindowStateForClass:"), with: type(of: self))
		if window.frame.width < PreferencesLayout.windowMinimumWidth || window.frame.height < PreferencesLayout
			.windowMinimumHeight
		{
			window.setContentSize(NSSize(width: 1020, height: 700))
			window.center()
		}
	}

	private func saveWindowFrame() {
		window.restoreDefaultSizeAndDisplay(false)
		window.perform(NSSelectorFromString("saveWindowStateForClass:"), with: type(of: self))
	}

	@objc public dynamic var installedScripts: [NSDictionary] {
		let pluginManager = TXSharedApplication.sharedPluginManager()
		let scripts = pluginManager.supportedAppleScriptCommands + pluginManager.supportedUserInputCommands
		return (scripts as NSArray).stringArrayControllerObjects.map { $0 as NSDictionary }
	}

	@objc public dynamic var scrollbackSaveLimit: String {
		get { String(TPCPreferences.scrollbackSaveLimit()) }
		set { TPCPreferences.setScrollbackSaveLimit(UInt((newValue as NSString).integerValue)) }
	}

	@objc public dynamic var scrollbackVisibleLimit: String {
		get { String(TPCPreferences.scrollbackVisibleLimit()) }
		set { TPCPreferences.setScrollbackVisibleLimit(UInt((newValue as NSString).integerValue)) }
	}

	@objc public dynamic var completionSuffix: String {
		get { TPCPreferences.tabCompletionSuffix() ?? "" }
		set { TPCPreferences.setTabCompletionSuffix(newValue) }
	}

	@objc public dynamic var inlineMediaMaxWidth: String {
		get { String(TPCPreferences.inlineMediaMaxWidth()) }
		set { TextualPreferences.textual_setInlineMediaMaxWidth(UInt((newValue as NSString).integerValue)) }
	}

	@objc public dynamic var inlineMediaMaxHeight: String {
		get { String(TPCPreferences.inlineMediaMaxHeight()) }
		set { TextualPreferences.textual_setInlineMediaMaxHeight(UInt((newValue as NSString).integerValue)) }
	}

	@objc public dynamic var themeChannelViewFontName: String {
		get { TPCPreferences.themeChannelViewFont()?.displayName ?? "" }
		set {}
	}

	@objc public dynamic var themeChannelViewFontSize: CGFloat {
		get { TPCPreferences.themeChannelViewFontSize() }
		set {}
	}

	@objc public dynamic var fileTransferPortRangeStart: String {
		get { String(TPCPreferences.fileTransferPortRangeStart()) }
		set { TPCPreferences.setFileTransferPortRangeStart(UInt16((newValue as NSString).integerValue)) }
	}

	@objc public dynamic var fileTransferPortRangeEnd: String {
		get { String(TPCPreferences.fileTransferPortRangeEnd()) }
		set { TPCPreferences.setFileTransferPortRangeEnd(UInt16((newValue as NSString).integerValue)) }
	}

	@objc public dynamic var highlightCurrentNickname: Bool {
		get {
			TPCPreferences.highlightMatchingMethod() != .regularExpression && TPCPreferences.highlightCurrentNickname()
		}
		set { TPCPreferences.setHighlightCurrentNickname(newValue) }
	}

	@objc public dynamic var appNapEnabled: Bool {
		get { TPCPreferences.appNapEnabled() }
		set { TPCPreferences.setAppNapEnabled(newValue) }
	}

	@objc public dynamic var onlySpeakEventsForSelection: Bool {
		get { TPCPreferences.onlySpeakEventsForSelection() }
		set {
			TPCPreferences.setOnlySpeakEventsForSelection(newValue)
			willChangeValue(forKey: "channelMessageSpeakChannelName")
			didChangeValue(forKey: "channelMessageSpeakChannelName")
		}
	}

	@objc public dynamic var channelMessageSpeakChannelName: Bool {
		get { !TPCPreferences.onlySpeakEventsForSelection() && TPCPreferences.channelMessageSpeakChannelName() }
		set { TPCPreferences.setChannelMessageSpeakChannelName(newValue) }
	}

	@objc public dynamic var channelMessageSpeakNickname: Bool {
		get { TPCPreferences.channelMessageSpeakNickname() }
		set { TPCPreferences.setChannelMessageSpeakNickname(newValue) }
	}

	@objc public dynamic var serverListUnreadCountBadgeHighlightColor: NSColor {
		get {
			TPCPreferencesUserDefaults.shared()
				.color(forKey: "Server List Unread Message Count Badge Colors -> Highlight") ?? .clear
		}
		set { TPCPreferencesUserDefaults.shared().setColor(
			newValue == .clear ? nil : newValue,
			forKey: "Server List Unread Message Count Badge Colors -> Highlight"
		) }
	}

	@objc public dynamic var userListNoModeColor: NSColor {
		get { TPCPreferencesUserDefaults.shared().color(forKey: "User List Mode Badge Colors -> no mode") ?? .clear }
		set { TPCPreferencesUserDefaults.shared().setColor(
			newValue == .clear ? nil : newValue,
			forKey: "User List Mode Badge Colors -> no mode"
		) }
	}

	@objc public dynamic var logTranscript: Bool {
		get { TPCPreferences.logToDisk() }
		set { TPCPreferences.setLogToDisk(newValue) }
	}

	@objc public dynamic var inlineMediaLimitToBasics: Bool {
		get { TPCPreferences.inlineMediaLimitToBasics() }
		set {
			TextualPreferences.textual_setInlineMediaLimitToBasics(newValue)
			willChangeValue(forKey: "inlineMediaLimitBasicsToFiles")
			didChangeValue(forKey: "inlineMediaLimitBasicsToFiles")
		}
	}

	@objc public dynamic var inlineMediaLimitBasicsToFiles: Bool {
		get { TPCPreferences.inlineMediaLimitToBasics() && TPCPreferences.inlineMediaLimitBasicsToFiles() }
		set { TextualPreferences.textual_setInlineMediaLimitBasicsToFiles(newValue) }
	}

	override public func validateValue(
		_ ioValue: AutoreleasingUnsafeMutablePointer<AnyObject?>,
		forKey key: String
	) throws {
		guard let string = ioValue.pointee as? String else { return }
		var value = (string as NSString).integerValue
		switch key {
		case "scrollbackSaveLimit":
			value = PreferencesValueValidation.clamped(value, to: PreferencesValueValidation.scrollbackSaveRange)
		case "scrollbackVisibleLimit":
			value = PreferencesValueValidation.clamped(
				value,
				to: PreferencesValueValidation.scrollbackVisibleRange,
				allowingZero: true
			)
		case "inlineMediaMaxWidth":
			value = PreferencesValueValidation.clamped(value, to: PreferencesValueValidation.inlineMediaWidthRange)
		case "inlineMediaMaxHeight":
			value = PreferencesValueValidation.clamped(value, to: PreferencesValueValidation.inlineMediaHeightRange)
		case "fileTransferPortRangeStart":
			value = min(
				PreferencesValueValidation.clamped(value, to: PreferencesValueValidation.fileTransferPortRange),
				Int(TPCPreferences.fileTransferPortRangeEnd())
			)
		case "fileTransferPortRangeEnd":
			value = max(
				PreferencesValueValidation.clamped(value, to: PreferencesValueValidation.fileTransferPortRange),
				Int(TPCPreferences.fileTransferPortRangeStart())
			)
		default:
			return
		}
		ioValue.pointee = String(value) as NSString
	}

	private func updateFileTransferDownloadDestinationFolder() {
		let path = TXSharedApplication.sharedFileTransferDialog().downloadDestinationURL
		guard let item = fileTransferDownloadDestinationButton.item(at: 0) else { return }
		guard let path else {
			item.image = nil
			item.title = LocalizedKey("TDCPreferencesController[721-ie]")
			return
		}
		let icon = NSWorkspace.shared.icon(forFile: path.path)
		icon.size = NSSize(width: 16, height: 16)
		item.image = icon
		item.title = path.lastPathComponent
	}

	@IBAction @objc(onFileTransferDownloadDestinationFolderChanged:)
	private func onFileTransferDownloadDestinationFolderChanged(_: Any?) {
		let transferController = TXSharedApplication.sharedFileTransferDialog()
		switch fileTransferDownloadDestinationButton.selectedTag() {
		case 2:
			chooseFolder(with: fileTransferDownloadDestinationButton) { [weak self] bookmark in
				transferController.setDownloadDestinationURL(bookmark)
				self?.updateFileTransferDownloadDestinationFolder()
			}
		case 3:
			fileTransferDownloadDestinationButton.selectItem(at: 0)
			transferController.setDownloadDestinationURL(nil)
			updateFileTransferDownloadDestinationFolder()
		default: break
		}
	}

	private func chooseFolder(with popupButton: NSPopUpButton, completion: @escaping (Data) -> Void) {
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = false
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.canCreateDirectories = true
		panel.resolvesAliases = true
		panel.prompt = LocalizedKey("Prompts[xne-79]")
		panel.beginSheetModal(for: window) { response in
			popupButton.selectItem(at: 0)
			guard response == .OK, let path = panel.url else { return }
			do {
				let bookmark = try path.bookmarkData(
					options: .withSecurityScope,
					includingResourceValuesForKeys: nil,
					relativeTo: nil
				)
				completion(bookmark)
			} catch {
				assertionFailure("Failed to create security-scoped bookmark for \(path.path): \(error)")
			}
		}
	}

	private func updateTranscriptFolder() {
		let path = TPCPathInfo.transcriptFolderURL
		guard let item = transcriptFolderButton.item(at: 0) else { return }
		guard let path else {
			item.image = nil
			item.title = LocalizedKey("TDCPreferencesController[70s-c6]")
			return
		}
		let icon = NSWorkspace.shared.icon(forFile: path.path)
		icon.size = NSSize(width: 16, height: 16)
		item.image = icon
		item.title = path.lastPathComponent
	}

	@IBAction @objc(onChangedTranscriptFolder:)
	private func onChangedTranscriptFolder(_: Any?) {
		switch transcriptFolderButton.selectedTag() {
		case 2:
			chooseFolder(with: transcriptFolderButton) { [weak self] bookmark in
				self?.setTranscriptFolderURL(bookmark)
			}
		case 3:
			transcriptFolderButton.selectItem(at: 0)
			setTranscriptFolderURL(nil)
		default: break
		}
	}

	private func setTranscriptFolderURL(_ bookmark: Data?) {
		TPCPathInfo.setTranscriptFolderURL(bookmark)
		TPCPreferences.performReloadAction(.logTranscripts)
		updateTranscriptFolder()
	}

	private func updateThemeSelection() {
		themeSelectionButton.removeAllItems()
		let controller = TXSharedApplication.sharedThemeController()
		let currentThemeName = controller.name
		let currentStorageLocation = controller.storageLocation
		var bundledItems: [NSMenuItem] = []
		var customItems: [NSMenuItem] = []
		controller.enumerateAvailableThemes { themeName, storageLocation, multipleVariants, _ in
			let displayName = multipleVariants
				? "\(themeName) (\(TPCThemeController.description(for: storageLocation) ?? ""))"
				: themeName
			let item = NSMenuItem(title: displayName, action: nil, keyEquivalent: "")
			item.representedObject = [
				"themeName": themeName,
				"storageLocation": NSNumber(value: storageLocation.rawValue),
			]
			if currentThemeName == themeName, currentStorageLocation == storageLocation {
				item.tag = 100
			}
			if storageLocation == .bundle {
				bundledItems.append(item)
			} else {
				customItems.append(item)
			}
		}
		bundledItems.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
		customItems.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
		guard let menu = themeSelectionButton.menu else { return }
		bundledItems.forEach(menu.addItem)
		if !bundledItems.isEmpty, !customItems.isEmpty {
			menu.addItem(.separator())
		}
		customItems.forEach(menu.addItem)
		themeSelectionButton.selectItem(withTag: 100)
		themeSelectionButton.isEnabled = menu.numberOfItems > 0
	}

	@IBAction @objc(onChangedThemeSelection:)
	private func onChangedThemeSelection(_: Any?) {
		guard let context = themeSelectionButton.selectedItem?.representedObject as? [String: Any],
		      let newThemeName = context["themeName"] as? String,
		      let locationNumber = context["storageLocation"] as? NSNumber,
		      let newStorageLocation = TPCThemeStorageLocation(rawValue: locationNumber.uintValue)
		else { return }
		guard let newTheme = TPCThemeController.buildFilename(newThemeName, for: newStorageLocation) else { return }
		guard TPCPreferences.themeName() != newTheme else { return }
		TPCPreferences.setThemeName(newTheme)
		reloadingThemeBySelection = true
		onChangedTheme(nil)
	}

	private func onChangedThemeSelectionReloadComplete(_: Notification) {
		var forcedValues: [String] = []
		if !TPCPreferences
			.themeNicknameFormatPreferenceUserConfigurable()
		{
			forcedValues.append(LocalizedKey("TDCPreferencesController[77t-de]"))
		}
		if !TPCPreferences
			.themeTimestampFormatPreferenceUserConfigurable()
		{
			forcedValues.append(LocalizedKey("TDCPreferencesController[ddh-hr]"))
		}
		if !TPCPreferences
			.themeChannelViewFontPreferenceUserConfigurable()
		{
			forcedValues.append(LocalizedKey("TDCPreferencesController[we8-i8]"))
		}
		guard !forcedValues.isEmpty else { return }
		let themeName = TPCThemeController.extractThemeName(TPCPreferences.themeName()) ?? ""
		TDCAlert.alertSheet(
			with: window,
			body: LocalizedKey("TDCPreferencesController[q4o-2f]", themeName, forcedValues.joined(separator: "\n")),
			title: LocalizedKey("TDCPreferencesController[uc0-z7]"),
			defaultButton: LocalizedKey("Prompts[c7s-dq]"),
			alternateButton: nil,
			otherButton: nil,
			suppressionKey: "theme_override_info",
			suppressionText: nil,
			completionBlock: nil
		)
	}

	@IBAction @objc(onSelectNewFont:)
	private func onSelectNewFont(_: Any?) {
		guard let currentFont = TPCPreferences.themeChannelViewFont() else { return }
		NSFontManager.shared.setSelectedFont(currentFont, isMultiple: false)
		NSFontManager.shared.orderFrontFontPanel(self)
		if !fontPanelIsOwned {
			previousFontManagerAction = NSFontManager.shared.action
			fontPanelIsOwned = true
		}
		NSFontManager.shared.action = #selector(onChangedChannelViewFont(_:))
	}

	private func releaseFontPanel() {
		guard fontPanelIsOwned else { return }
		fontPanelIsOwned = false
		NSFontManager.shared.setValue(previousFontManagerAction, forKey: "action")
		previousFontManagerAction = nil
		if NSFontPanel.sharedFontPanelExists {
			NSFontPanel.shared.orderOut(self)
		}
	}

	@objc private func onChangedChannelViewFont(_ sender: NSFontManager) {
		guard let currentFont = TPCPreferences.themeChannelViewFont() else { return }
		let newFont = sender.convert(currentFont)
		willChangeValue(forKey: "themeChannelViewFontName")
		willChangeValue(forKey: "themeChannelViewFontSize")
		TPCPreferences.setThemeChannelViewFontName(newFont.fontName)
		TPCPreferences.setThemeChannelViewFontSize(newFont.pointSize)
		didChangeValue(forKey: "themeChannelViewFontName")
		didChangeValue(forKey: "themeChannelViewFontSize")
		onChangedTheme(nil)
	}

	@IBAction @objc(onModifyUserStyleSheetRules:)
	private func onModifyUserStyleSheetRules(_: Any?) {
		let sheet = PreferencesUserStyleSheet(window: window)
		sheet.delegate = self
		sheet.start()
		userStyleSheet = sheet
	}

	@objc(userStyleSheetRulesChanged:)
	private func userStyleSheetRulesChanged(_: PreferencesUserStyleSheet) {
		onChangedTheme(nil)
	}

	@objc(userStyleSheetWillClose:)
	private func userStyleSheetWillClose(_: PreferencesUserStyleSheet) {
		userStyleSheet = nil
	}

	private func updateForwardNoticeToMatrix() {
		let location = TPCPreferences.locationToSendNotices()
		forwardNoticeToServerConsoleButton.state = location == .serverConsole ? .on : .off
		forwardNoticeToSelectedChannelButton.state = location == .selectedChannel ? .on : .off
		forwardNoticeToQueryButton.state = location == .query ? .on : .off
	}

	@IBAction @objc(onChangedForwardNoticeTo:)
	private func onChangedForwardNoticeTo(_ sender: Any?) {
		guard let control = sender as? NSControl,
		      let location = TXNoticeSendLocation(rawValue: UInt(control.tag)) else { return }
		TPCPreferences.setLocationToSendNotices(location)
	}

	@IBAction @objc(onChangedDisableNicknameColorHashing:)
	private func onChangedDisableNicknameColorHashing(_: Any?) {
		onChangedTheme(nil)
	}

	@IBAction @objc(onChangedHighlightType:)
	private func onChangedHighlightType(_: Any?) {
		willChangeValue(forKey: "highlightCurrentNickname")
		didChangeValue(forKey: "highlightCurrentNickname")
		highlightNicknameButton.isEnabled = TPCPreferences.highlightMatchingMethod() != .regularExpression
	}

	private func editTableView(_ tableView: NSTableView) {
		let row = tableView.numberOfRows - 1
		guard row >= 0 else { return }
		tableView.scrollRowToVisible(row)
		tableView.editColumn(0, row: row, with: nil, select: true)
	}

	@IBAction @objc(onAddHighlightKeyword:)
	private func onAddHighlightKeyword(_: Any?) {
		highlightKeywordsArrayController.add(nil)
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			editTableView(highlightKeywordsTable)
		}
	}

	@IBAction @objc(onAddExcludeKeyword:)
	private func onAddExcludeKeyword(_: Any?) {
		excludeKeywordsArrayController.add(nil)
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			editTableView(excludeKeywordsTable)
		}
	}

	@objc(openProxySettingsInSystemPreferences)
	public static func openProxySettingsInSystemPreferences() {
		guard let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Proxies")
		else { return }
		NSWorkspace.shared.open(url)
	}

	private func updateInlineMediaEnabled() {
		inlineMediaEnabledButton.state = TPCPreferences.showInlineMedia() ? .on : .off
	}

	@IBAction @objc(onChangedInlineMediaOption:)
	private func onChangedInlineMediaOption(_: Any?) {
		guard inlineMediaEnabledButton.state != .off else {
			TPCPreferences.setShowInlineMedia(false)
			onChangedTheme(nil)
			return
		}
		TVCLogControllerInlineMediaService.askPermissionToEnableInlineMedia { [weak self] granted in
			Task { @MainActor [weak self] in
				guard let self else { return }
				if granted {
					TPCPreferences.setShowInlineMedia(true)
					onChangedTheme(nil)
				} else {
					inlineMediaEnabledButton.state = .off
				}
			}
		}
	}

	@IBAction @objc(onResetUserListModeColorsToDefaults:)
	private func onResetUserListModeColorsToDefaults(_: Any?) {
		let defaults = TPCPreferencesUserDefaults.shared()
		for item in ["+y", "+q", "+a", "+o", "+h", "+v", "no mode"] {
			defaults.removeObject(forKey: "User List Mode Badge Colors -> \(item)")
		}
		onChangedUserListModeColor(nil)
	}

	@IBAction @objc(onResetServerListUnreadBadgeColorsToDefault:)
	private func onResetServerListUnreadBadgeColorsToDefault(_ sender: Any?) {
		willChangeValue(forKey: "serverListUnreadCountBadgeHighlightColor")
		TPCPreferencesUserDefaults.shared()
			.removeObject(forKey: "Server List Unread Message Count Badge Colors -> Highlight")
		didChangeValue(forKey: "serverListUnreadCountBadgeHighlightColor")
		onChangedServerListUnreadBadgeColor(sender)
	}

	@IBAction @objc(onChangedInputHistoryScheme:)
	private func onChangedInputHistoryScheme(_: Any?) {
		TPCPreferences.performReloadAction(.inputHistoryScope)
	}

	@IBAction @objc(onChangedAppearance:)
	private func onChangedAppearance(_: Any?) {
		TPCPreferences.performReloadAction(.appearance)
	}

	@IBAction @objc(onChangedTheme:)
	private func onChangedTheme(_: Any?) {
		TPCPreferences.performReloadAction([.style, .textDirection])
	}

	@objc private func onThemeWillReload(_: Notification) {
		reloadingTheme = true
	}

	@objc private func onThemeReloadComplete(_ notification: Notification) {
		reloadingTheme = false
		if reloadingThemeBySelection {
			reloadingThemeBySelection = false
			onChangedThemeSelectionReloadComplete(notification)
		}
	}

	@IBAction @objc(onChangedChannelViewArrangement:)
	private func onChangedChannelViewArrangement(_: Any?) {
		TPCPreferences.performReloadAction(.channelViewArrangement)
	}

	@IBAction @objc(onChangedUserListModeColor:)
	private func onChangedUserListModeColor(_ sender: Any?) {
		let preferenceMap = [
			10: "User List Mode Badge Colors -> +y", 9: "User List Mode Badge Colors -> +q",
			8: "User List Mode Badge Colors -> +a", 7: "User List Mode Badge Colors -> +o",
			6: "User List Mode Badge Colors -> +h", 5: "User List Mode Badge Colors -> +v",
			4: "User List Mode Badge Colors -> no mode",
		]
		guard let control = sender as? NSControl, let preferenceKey = preferenceMap[control.tag] else {
			TPCPreferences.performReloadAction([.memberListUserBadges, .memberList])
			return
		}
		TPCPreferences.performReloadAction(.memberListUserBadges, forKey: preferenceKey)
	}

	@IBAction @objc(onChangedMainInputTextViewFontSize:)
	private func onChangedMainInputTextViewFontSize(_: Any?) {
		TPCPreferences.performReloadAction(.textFieldFontSize)
	}

	@IBAction @objc(onFileTransferIPAddressDetectionMethodChanged:)
	private func onFileTransferIPAddressDetectionMethodChanged(_: Any?) {
		fileTransferManuallyEnteredIPAddressTextField.isEnabled = TPCPreferences
			.fileTransferIPAddressDetectionMethod() == .manual
	}

	@IBAction @objc(onChangedHighlightLogging:)
	private func onChangedHighlightLogging(_: Any?) {
		TPCPreferences.performReloadAction(.highlightLogging)
	}

	@IBAction @objc(onChangedUserListModeSortOrder:)
	private func onChangedUserListModeSortOrder(_: Any?) {
		TPCPreferences.performReloadAction(.memberListSortOrder)
	}

	@IBAction @objc(onChangedServerListUnreadBadgeColor:)
	private func onChangedServerListUnreadBadgeColor(_: Any?) {
		TPCPreferences.performReloadAction(.serverListUnreadBadges)
	}

	@IBAction @objc(onChangedScrollbackSaveLimit:)
	private func onChangedScrollbackSaveLimit(_: Any?) {
		TPCPreferences.performReloadAction(.scrollbackSaveLimit)
	}

	@IBAction @objc(onChangedScrollbackVisibleLimit:)
	private func onChangedScrollbackVisibleLimit(_: Any?) {
		TPCPreferences.performReloadAction(.scrollbackVisibleLimit)
	}

	@IBAction @objc(onOpenPathToScripts:)
	private func onOpenPathToScripts(_: Any?) {
		if let url = TPCPathInfo.groupContainerApplicationSupportURL {
			NSWorkspace.shared.open(url)
		}
	}

	@IBAction @objc(onResetPluginApprovals:)
	private func onResetPluginApprovals(_: Any?) {
		PluginManager.resetApprovals()
		TDCAlert.alertSheet(
			with: window,
			body: LocalizedKey("Prompts[h7m-2q]"),
			title: LocalizedKey("Prompts[zp3-7r]"),
			defaultButton: LocalizedKey("Prompts[u5k-9n]"),
			alternateButton: nil,
			otherButton: nil
		)
	}

	private func openPathToThemesCallback(_ returnCode: TDCAlertResponse, originalAlert: NSAlert) {
		switch returnCode {
		case .default:
			openPathToTheme()
		case .alternate:
			onModifyUserStyleSheetRules(nil)
		case .other:
			originalAlert.window.orderOut(nil)
			TXSharedApplication.sharedThemeController().copyActiveTheme(
				to: .custom,
				reloadOnCopy: true,
				openOnCopy: true
			)
		@unknown default: break
		}
	}

	@IBAction @objc(onOpenPathToTheme:)
	private func onOpenPathToTheme(_: Any?) {
		guard TXSharedApplication.sharedThemeController().isBundledTheme else {
			openPathToTheme()
			return
		}
		TDCAlert.alertSheet(
			with: window,
			body: LocalizedKey("TDCPreferencesController[ojj-ap]"),
			title: LocalizedKey("TDCPreferencesController[5jv-aw]"),
			defaultButton: LocalizedKey("TDCPreferencesController[6ws-av]"),
			alternateButton: LocalizedKey("TDCPreferencesController[aib-iy]"),
			otherButton: LocalizedKey("TDCPreferencesController[dj8-1t]")
		) { [weak self] response, _, underlyingAlert in
			guard let self, let alert = underlyingAlert as? NSAlert else { return }
			openPathToThemesCallback(response, originalAlert: alert)
		}
	}

	private func openPathToTheme() {
		NSWorkspace.shared.open(TXSharedApplication.sharedThemeController().originalURL)
	}

	@objc private func onThemeListDidChange(_: Notification) {
		updateThemeSelection()
	}

	@objc public func windowWillClose(_: Notification) {
		NotificationCenter.default.removeObserver(self)
		releaseFontPanel()
		saveWindowFrame()
		(delegate as? PreferencesControllerDelegate)?.preferencesDialogWillClose(self)
	}
}
