/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import Foundation

public typealias TVCMainWindow = MainWindow

public extension Notification.Name {
	static let TVCMainWindowAppearanceChanged = Notification.Name("TVCMainWindowAppearanceChangedNotification")
	static let TVCMainWindowRedrawSubviews = Notification.Name("TVCMainWindowRedrawSubviewsNotification")
	static let TVCMainWindowWillReloadTheme = Notification.Name("TVCMainWindowWillReloadThemeNotification")
	static let TVCMainWindowDidReloadTheme = Notification.Name("TVCMainWindowDidReloadThemeNotification")
	static let TVCMainWindowSelectionChanged = Notification.Name("TVCMainWindowSelectionChangedNotification")
	static let mainWindowAppearanceChanged = Notification.Name("TVCMainWindowAppearanceChangedNotification")
	static let mainWindowRedrawSubviews = Notification.Name("TVCMainWindowRedrawSubviewsNotification")
	static let mainWindowWillReloadTheme = Notification.Name("TVCMainWindowWillReloadThemeNotification")
	static let mainWindowDidReloadTheme = Notification.Name("TVCMainWindowDidReloadThemeNotification")
	static let mainWindowSelectionChanged = Notification.Name("TVCMainWindowSelectionChangedNotification")
}

@objc public enum ServerListNavigationMovement: UInt {
	case all
	case active
	case unread
}

private enum ServerListNavigationSelection {
	case any
	case channel
	case server
}

struct MainWindowShiftSelectionOptions: OptionSet {
	let rawValue: UInt

	static let maintainGrouping = Self(rawValue: 1 << 0)
	static let performDeselect = Self(rawValue: 1 << 1)
	static let performDeselectChildren = Self(rawValue: 1 << 2)
}

struct MainWindowMouseLocation: OptionSet {
	let rawValue: UInt

	static let outsideWindow: Self = []
	static let insideWindow = Self(rawValue: 1 << 1)
	static let insideWindowTitle = Self(rawValue: 1 << 2)
	static let onTopOfWindowTitleControl = Self(rawValue: 1 << 3)
}

enum MainWindowConstants {
	static let toggleServerListToolbarItem = NSToolbarItem.Identifier("TVCMainWindowToggleServerList")
	static let toggleMemberListToolbarItem = NSToolbarItem.Identifier("TVCMainWindowToggleMemberList")
	static let treeItemPasteboardType = NSPasteboard.PasteboardType("com.vakesz.glasstual.tree-item")
	static let restorableSelectionKey = "TVCMainWindowSelectedItems"
	static let sidebarFooterHeight: CGFloat = 32
	static let maximumSelectedRows = 6
}

enum MainWindowMemberListVisibilityPolicy {
	static func shouldExpand(
		isChannel: Bool,
		isLoggedIn: Bool,
		isHiddenByUser: Bool
	) -> Bool {
		isChannel && isLoggedIn && isHiddenByUser == false
	}
}

@inline(__always)
func nativeLogController(_ controller: TVCLogController) -> LogController {
	controller
}

@inline(__always)
func legacyTreeItem(_ item: TreeItem) -> IRCTreeItem {
	item
}

@inline(__always)
func nativeChannel(_ item: IRCTreeItem?) -> IRCChannel? {
	item as? IRCChannel
}

@MainActor
@objc(TVCMainWindow)
@objcMembers
public final class MainWindow: NSWindow, NSWindowDelegate, NSWindowRestoration, NSToolbarDelegate,
	MemberListKeyEventDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, TVCServerListDelegate,
	CustomKeyboardEventResponder
{
	@IBOutlet var channelView: MainWindowChannelView!
	@IBOutlet public var mainMenuProxy: TXMenuControllerMainWindowProxy!
	@IBOutlet public var formattingMenu: TextViewIRCFormattingMenu!
	@IBOutlet public var inputTextField: MainWindowTextView!
	@IBOutlet private var nibContentSplitView: NSSplitView!
	@IBOutlet public var loadingScreen: MainWindowLoadingScreenView!
	@IBOutlet public var memberList: MemberList!
	@IBOutlet public var serverList: ServerList!

	public private(set) var contentSplitViewController: NSSplitViewController!
	var serverListSplitItem: NSSplitViewItem!
	var memberListSplitItem: NSSplitViewItem!
	private var sidebarFooterController: NSSplitViewItemAccessoryViewController?
	var inputHistory: InputHistory!
	var nicknameCompletionStatus: NicknameCompletionStatus!
	private var appearanceStorage: MainWindowAppearance?
	public var userInterfaceObjects: MainWindowAppearance {
		guard let appearanceStorage else {
			preconditionFailure("Main-window appearance requested before the nib finished loading")
		}
		return appearanceStorage
	}

	public internal(set) var selectedItems: [IRCTreeItem] = []
	public internal(set) var selectedItem: IRCTreeItem?
	var previousSelectedItemsId: [String] = []
	var previousSelectedItemId: String?
	private var lastKeyWindowStateChange: TimeInterval = 0
	private var lastKeyWindowRedrawFailedBecauseOfOcclusion = false
	private var keyEventHandler: KeyEventHandler!
	var cachedSwipeOriginPoint: NSPoint?
	public internal(set) var textSizeMultiplier = 1.0
	var isReloadingTheme = false
	private var hasAwakenedFromNib = false
	private var hasInstalledFieldEditorMenu = false
	private let notifications = NotificationSubscriptions()

	public var ignoreOutlineViewSelectionChanges = false
	public var ignoreNextOutlineViewSelectionChange = false

	override public init(
		contentRect: NSRect,
		styleMask style: NSWindow.StyleMask,
		backing bufferingType: NSWindow.BackingStoreType,
		defer flag: Bool
	) {
		super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
		prepareInitialState()
	}

	private func prepareInitialState() {
		inputHistory = InputHistory(window: self)
		keyEventHandler = KeyEventHandler()
		nicknameCompletionStatus = NicknameCompletionStatus(window: self)
		updateAppearance()
	}

	/* ISOLATION-EXCEPTION: `NSObject.awakeFromNib()` is declared nonisolated, so the
	 override cannot be main-actor isolated. AppKit decodes nibs on the main thread
	 only, which is what makes the assumption safe. */
	override public nonisolated func awakeFromNib() {
		super.awakeFromNib()
		MainActor.assumeIsolated {
			guard hasAwakenedFromNib == false else { return }
			hasAwakenedFromNib = true
			finishAwakeningFromNib()
		}
	}

	private func finishAwakeningFromNib() {
		let controller: ApplicationController = AppController.shared
		controller.applicationWakeStepOne()

		delegate = self
		allowsConcurrentViewDrawing = false
		autorecalculatesKeyViewLoop = true
		isRestorable = true
		restorationClass = Self.self
		installWindowChrome()
		installFormattingMenuDecorations()
		updateAppearance()
		_ = reloadLoadingScreen()
		makeMain()
		makeKeyAndOrderFront(nil)
		loadWindowState()
		updateChannelViewArrangement()

		SharedApplication.sharedThemeController().load()
		controller.menuController?.prepareInitialState()
		registerKeyHandlers()
		controller.world.setupConfiguration()
		setupTrees()
		DockIcon.drawWithoutCount()
		observeNotifications()
		controller.applicationWakeStepTwo()
	}

	var world: IRCWorld {
		AppController.shared.world
	}

	var menuController: TXMenuController {
		guard let menuController = AppController.shared.menuController else {
			preconditionFailure("Menu controller is unavailable while the main window is loading")
		}
		return menuController
	}

	public func inputHistoryManager() -> InputHistory {
		inputHistory
	}

	public func reloadingTheme() -> Bool {
		isReloadingTheme
	}

	private func installWindowChrome() {
		styleMask.insert(.fullSizeContentView)
		titlebarAppearsTransparent = false
		titlebarSeparatorStyle = .automatic
		toolbarStyle = .unified
		titleVisibility = .visible
		installToolbar()
		installContentSplitViewController()
	}

	private func installToolbar() {
		let toolbar = NSToolbar(identifier: "TVCMainWindowToolbar")
		toolbar.delegate = self
		toolbar.allowsUserCustomization = false
		toolbar.autosavesConfiguration = false
		toolbar.displayMode = .iconOnly
		self.toolbar = toolbar
	}

	public func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
		[
			MainWindowConstants.toggleServerListToolbarItem,
			.sidebarTrackingSeparator,
			.flexibleSpace,
			.space,
			MainWindowConstants.toggleMemberListToolbarItem,
		]
	}

	public func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
		[
			MainWindowConstants.toggleServerListToolbarItem,
			.sidebarTrackingSeparator,
			.flexibleSpace,
			MainWindowConstants.toggleMemberListToolbarItem,
		]
	}

	public func toolbar(
		_: NSToolbar,
		itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
		willBeInsertedIntoToolbar _: Bool
	) -> NSToolbarItem? {
		let symbolName: String
		let label: String
		let action: Selector
		let navigational: Bool

		switch itemIdentifier {
		case MainWindowConstants.toggleServerListToolbarItem:
			symbolName = "sidebar.left"
			label = MainWindowStrings.Toolbar.toggleServerList
			action = #selector(toggleServerListVisibility)
			navigational = true
		case MainWindowConstants.toggleMemberListToolbarItem:
			symbolName = "sidebar.right"
			label = MainWindowStrings.Toolbar.toggleMemberList
			action = #selector(toggleMemberListVisibility)
			navigational = false
		default:
			return nil
		}

		let item = NSToolbarItem(itemIdentifier: itemIdentifier)
		item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
		item.label = label
		item.paletteLabel = label
		item.toolTip = label
		item.isBordered = true
		item.isNavigational = navigational
		item.target = self
		item.action = action
		return item
	}
}

// MARK: - Window chrome

private extension MainWindow {
	func installContentSplitViewController() {
		guard let nibContentSplitView, nibContentSplitView.subviews.count >= 3 else {
			assertionFailure("TVCMainWindow.xib must provide a three-pane content split view")
			return
		}

		let panes = Array(nibContentSplitView.subviews.prefix(3))
		for pane in panes {
			pane.removeFromSuperview()
			pane.translatesAutoresizingMaskIntoConstraints = true
			pane.autoresizingMask = [.width, .height]
		}

		let serverController = NSViewController()
		serverController.view = panes[0]
		let channelController = NSViewController()
		channelController.view = panes[1]
		let memberController = NSViewController()
		memberController.view = panes[2]

		let sidebarItem = NSSplitViewItem(sidebarWithViewController: serverController)
		sidebarItem.canCollapse = true
		sidebarItem.minimumThickness = 180
		sidebarItem.maximumThickness = 280
		sidebarItem.preferredThicknessFraction = 0.22
		sidebarItem.holdingPriority = .defaultLow + 1

		let contentItem = NSSplitViewItem(viewController: channelController)
		contentItem.automaticallyAdjustsSafeAreaInsets = true

		let inspectorItem = NSSplitViewItem(inspectorWithViewController: memberController)
		inspectorItem.canCollapse = true
		inspectorItem.minimumThickness = 160
		inspectorItem.maximumThickness = 260
		inspectorItem.preferredThicknessFraction = 0.18
		inspectorItem.holdingPriority = .defaultLow + 1

		installSidebarFooter(on: sidebarItem)
		installInputAccessory(on: contentItem)

		let splitController = NSSplitViewController()
		splitController.addSplitViewItem(sidebarItem)
		splitController.addSplitViewItem(contentItem)
		splitController.addSplitViewItem(inspectorItem)
		splitController.splitView.dividerStyle = .thin
		splitController.splitView.isVertical = true
		splitController.splitView.autosaveName = "TVCMainWindowContentSplitView"

		guard let contentView else {
			assertionFailure("Main window has no content view")
			return
		}

		let splitHost = splitController.view
		splitHost.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(splitHost, positioned: .below, relativeTo: loadingScreen)
		NSLayoutConstraint.activate([
			splitHost.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			splitHost.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			splitHost.topAnchor.constraint(equalTo: contentView.topAnchor),
			splitHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
		])

		nibContentSplitView.removeFromSuperview()
		if let loadingScreen {
			loadingScreen.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				loadingScreen.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
				loadingScreen.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
				loadingScreen.topAnchor.constraint(equalTo: contentView.topAnchor),
				loadingScreen.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			])
		}

		contentSplitViewController = splitController
		serverListSplitItem = sidebarItem
		memberListSplitItem = inspectorItem
		configureLists()
	}

	func installSidebarFooter(on sidebarItem: NSSplitViewItem) {
		let addButton = NSButton(
			image: NSImage(
				systemSymbolName: "plus",
				accessibilityDescription: MainWindowStrings.InputBar.addServerOrChannel
			)!,
			target: self,
			action: #selector(presentSidebarAddMenu(_:))
		)
		configureSidebarButton(addButton, title: MainWindowStrings.InputBar.addServerOrChannel)

		let searchButton = sidebarFooterButton(
			symbolName: "magnifyingglass",
			title: MainWindowStrings.InputBar.searchChannels,
			action: #selector(TXMenuController.showChannelSpotlightWindow(_:))
		)
		let settingsButton = sidebarFooterButton(
			symbolName: "ellipsis.circle",
			title: MainWindowStrings.InputBar.more,
			action: #selector(presentSidebarMoreMenu(_:))
		)
		settingsButton.target = self

		let footer = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: MainWindowConstants.sidebarFooterHeight))
		footer.translatesAutoresizingMaskIntoConstraints = false
		[addButton, searchButton, settingsButton].forEach(footer.addSubview)
		NSLayoutConstraint.activate([
			footer.heightAnchor.constraint(equalToConstant: MainWindowConstants.sidebarFooterHeight),
			addButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 10),
			addButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
			settingsButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -10),
			settingsButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
			searchButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -6),
			searchButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
			searchButton.leadingAnchor.constraint(greaterThanOrEqualTo: addButton.trailingAnchor, constant: 8),
		])

		let accessory = NSSplitViewItemAccessoryViewController()
		accessory.view = footer
		accessory.automaticallyAppliesContentInsets = true
		sidebarItem.addBottomAlignedAccessoryViewController(accessory)
		sidebarFooterController = accessory
	}

	func installInputAccessory(on contentItem: NSSplitViewItem) {
		guard let inputBar = inputTextField.contentView else { return }
		inputBar.removeFromSuperview()
		inputBar.translatesAutoresizingMaskIntoConstraints = true
		inputBar.autoresizingMask = [.width, .height]

		let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: 400, height: 44))
		glass.cornerRadius = 22
		glass.contentView = inputBar
		glass.style = .regular

		let accessory = NSSplitViewItemAccessoryViewController()
		accessory.view = glass
		accessory.automaticallyAppliesContentInsets = true
		contentItem.addBottomAlignedAccessoryViewController(accessory)
	}

	func configureLists() {
		serverList.style = .sourceList
		serverList.selectionHighlightStyle = .regular
		serverList.usesAutomaticRowHeights = false
		serverList.rowSizeStyle = .custom
		serverList.rowHeight = 28
		serverList.indentationPerLevel = 14
		serverList.floatsGroupRows = false

		memberList.style = .sourceList
		memberList.selectionHighlightStyle = .regular
		memberList.usesAutomaticRowHeights = false
		memberList.rowSizeStyle = .custom
		memberList.rowHeight = 24
	}

	func sidebarFooterButton(symbolName: String, title: String, action: Selector) -> NSButton {
		let button = NSButton(
			image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title)!,
			target: menuController,
			action: action
		)
		configureSidebarButton(button, title: title)
		return button
	}

	func configureSidebarButton(_ button: NSButton, title: String) {
		button.translatesAutoresizingMaskIntoConstraints = false
		button.bezelStyle = .accessoryBarAction
		button.isBordered = false
		button.toolTip = title
	}

	@objc func presentSidebarAddMenu(_ sender: Any?) {
		guard let anchor = sender as? NSView else { return }
		let menu = menuController.mainWindowSegmentedControllerCellMenu
		menuController.applySymbols(to: menu)
		menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height), in: anchor)
	}

	@objc func presentSidebarMoreMenu(_ sender: Any?) {
		guard let anchor = sender as? NSView else { return }
		let menu = NSMenu()
		func item(
			_ title: String,
			_ symbol: String,
			_ action: Selector,
			_ command: MenuCommand
		) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = menuController
			item.command = command
			item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
			return item
		}
		menu.addItem(
			item(
				MainWindowStrings.InputBar.markAllAsRead,
				"checkmark.circle",
				#selector(TXMenuController.markAllAsRead(_:)),
				.markAllRead
			)
		)
		menu.addItem(
			item(
				MainWindowStrings.InputBar.disableAllNotifications,
				"bell.slash",
				#selector(TXMenuController.toggleMuteOnNotifications(_:)),
				.disableNotifications
			)
		)
		menu.addItem(.separator())
		menu.addItem(
			item(
				MainWindowStrings.InputBar.addressBook,
				"person.crop.circle",
				#selector(TXMenuController.showAddressBook(_:)),
				.addressBook
			)
		)
		menu.addItem(
			item(
				MainWindowStrings.InputBar.fileTransfers,
				"arrow.down.circle",
				#selector(TXMenuController.showFileTransfersWindow(_:)),
				.fileTransfers
			)
		)
		menu.addItem(.separator())
		menu.addItem(
			item(
				MainWindowStrings.InputBar.hideMemberList,
				"sidebar.right",
				#selector(TXMenuController.toggleMemberListVisibility(_:)),
				.toggleMemberList
			)
		)
		menu.addItem(
			.separator()
		)
		menu.addItem(
			item(
				MainWindowStrings.InputBar.settings,
				"gear",
				#selector(TXMenuController.showPreferencesWindow(_:)),
				.settings
			)
		)
		menuController.applySymbols(to: menu)
		menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height), in: anchor)
	}
}

// MARK: - Appearance and lifecycle

extension MainWindow {
	private func observeNotifications() {
		notifications.observe(Notification.Name("TXApplicationAppearanceChangedNotification")) { [weak self] _ in
			self?.updateAppearance()
		}
		notifications.observe(Notification.Name("TXSystemAppearanceChangedNotification")) { [weak self] _ in
			self?.notifySystemAppearanceChanged()
		}
		notifications.observe(Notification.Name("TPCThemeAppearanceChangedNotification")) { [weak self] _ in
			self?.reloadTheme()
		}
		notifications.observe(Notification.Name("TPCThemeVarietyChangedNotification")) { [weak self] _ in
			self?.reloadTheme()
		}
	}

	public var isUsingDarkAppearance: Bool {
		userInterfaceObjects.isDarkAppearance
	}

	private func updateAppearance() {
		guard let appearance = MainWindowAppearance() else { return }
		appearanceStorage = appearance
		self.appearance = appearance.appKitAppearanceTarget == .window ? appearance.appKitAppearance : nil
		notifyMainWindowAppearanceChanged()
	}

	private func notifyMainWindowAppearanceChanged() {
		contentView?.superview?.notifyApplicationAppearanceChanged()
		if styleMask.contains(.titled) {
			for controller in titlebarAccessoryViewControllers {
				controller.view.notifyApplicationAppearanceChanged()
			}
		}
		NotificationCenter.default.post(name: .mainWindowAppearanceChanged, object: self)
	}

	private func loadWindowState() {
		migrateLegacyWindowFrame()
		restoreSavedContentSplitViewState()
	}

	private func migrateLegacyWindowFrame() {
		let legacyKey = "NSWindow Frame -> Internal (v3) -> Main Window"
		let defaults = UserDefaults.standard
		guard let legacyFrame = defaults.string(forKey: legacyKey) else { return }
		let autosaveName = frameAutosaveName
		if autosaveName.isEmpty == false, defaults.string(forKey: "NSWindow Frame \(autosaveName)") == nil {
			setFrame(from: legacyFrame)
			saveFrame(usingName: autosaveName)
		}
		defaults.removeObject(forKey: legacyKey)
	}

	@objc public func prepareForApplicationTermination() {
		notifications.cancelAll()
		saveContentSplitViewState()
		saveSelection()
		serverList.dataSource = nil
		serverList.delegate = nil
		serverList.keyDelegate = nil
		memberList.keyDelegate = nil
		memberList.assign(to: nil)
		delegate = nil
		selectedItems = []
		selectedItem = nil
		close()
	}

	public static func restoreWindow(
		withIdentifier _: NSUserInterfaceItemIdentifier,
		state _: NSCoder,
		completionHandler: @escaping (NSWindow?, (any Error)?) -> Void
	) {
		completionHandler(AppController.shared.mainWindow, nil)
	}

	override public func encodeRestorableState(with coder: NSCoder) {
		super.encodeRestorableState(with: coder)
		coder.encode(selectedItems.map(\.uniqueIdentifier), forKey: MainWindowConstants.restorableSelectionKey)
	}

	override public func restoreState(with coder: NSCoder) {
		super.restoreState(with: coder)
		guard let world = AppController.shared.world else { return }
		let classes: [AnyClass] = [NSArray.self, NSString.self]
		guard let identifiers = coder
			.decodeObject(of: classes, forKey: MainWindowConstants.restorableSelectionKey) as? [String],
			identifiers.isEmpty == false
		else { return }
		let selection = world.findItems(withIds: identifiers)
		guard selection.isEmpty == false else { return }
		adjustSelection(with: selection, selectedItem: nil)
	}
}

// MARK: - Window delegate

public extension MainWindow {
	private func reloadMainWindowFrameOnScreenChange() {
		guard AppController.shared.applicationIsTerminating == false else { return }
		DockIcon.resetCachedCount()
		DockIcon.updateDockIcon()
		updateAppearance()
	}

	private func resetSelectedItemState() {
		guard AppController.shared.applicationIsTerminating == false else { return }
		if let selectedItem {
			selectedItem.resetState()
			noteItemWasViewed(selectedItem)
		}
		DockIcon.updateDockIcon()
	}

	func noteItemWasViewed(_ item: IRCTreeItem) {
		guard isKeyWindow, let channel = item.associatedChannel else { return }
		channel.associatedClient.markChannel(asRead: channel)
	}

	private func reloadSubviewDrawings() {
		NotificationCenter.default.post(name: .mainWindowRedrawSubviews, object: self)
	}

	func windowDidDeminiaturize(_: Notification) {}

	func windowDidChangeScreen(_: Notification) {
		reloadMainWindowFrameOnScreenChange()
	}

	func windowDidChangeOcclusionState(_: Notification) {
		guard ceIsOccluded == false else { return }
		if lastKeyWindowRedrawFailedBecauseOfOcclusion {
			lastKeyWindowRedrawFailedBecauseOfOcclusion = false
			reloadSubviewDrawings()
		} else if Date.timeIntervalSinceReferenceDate - lastKeyWindowStateChange > 1 {
			reloadSubviewDrawings()
		}
	}

	func windowDidBecomeKey(_: Notification) {
		lastKeyWindowStateChange = Date.timeIntervalSinceReferenceDate
		resetSelectedItemState()
		if ceIsOccluded {
			lastKeyWindowRedrawFailedBecauseOfOcclusion = true
			return
		}
		reloadSubviewDrawings()
	}

	func windowDidResignKey(_: Notification) {
		lastKeyWindowStateChange = Date.timeIntervalSinceReferenceDate
		reloadSubviewDrawings()
	}

	func window(_: NSWindow, shouldPopUpDocumentPathMenu _: NSMenu) -> Bool {
		false
	}

	func window(
		_: NSWindow,
		shouldDragDocumentWith _: NSEvent,
		from _: NSPoint,
		with _: NSPasteboard
	) -> Bool {
		false
	}

	func windowDidResize(_: Notification) {
		inputTextField.recalculateTextViewSize()
	}

	func windowShouldZoom(_: NSWindow, toFrame _: NSRect) -> Bool {
		ceIsInFullscreenMode == false
	}

	func window(_: NSWindow, willUseFullScreenContentSize proposedSize: NSSize) -> NSSize {
		proposedSize
	}

	func window(
		_: NSWindow,
		willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions
	) -> NSApplication.PresentationOptions {
		proposedOptions
	}

	func windowWillReturnFieldEditor(_: NSWindow, to _: Any?) -> Any? {
		if hasInstalledFieldEditorMenu == false {
			hasInstalledFieldEditorMenu = true
			let editorMenu = inputTextField.menu ?? NSMenu()
			let formatterMenu = formattingMenu.formatterMenu!
			if editorMenu.indexOfItem(withTitle: formatterMenu.title) < 0 {
				editorMenu.addItem(.separator())
				editorMenu.addItem(formatterMenu)
			}
			inputTextField.menu = editorMenu
		}
		return inputTextField
	}
}

// MARK: - Formatting menu

private extension MainWindow {
	func installFormattingMenuDecorations() {
		for menu in [formattingMenu.foregroundColorMenu!, formattingMenu.backgroundColorMenu!] {
			for item in menu.items where item.isSeparatorItem == false && item.action != nil {
				item.image = Self.formattingMenuImage(forColorTag: item.tag)
			}
		}

		guard let formatterMenu = formattingMenu.formatterMenu?.submenu else { return }
		if let monospaceItem = formatterMenu.item(withTag: TextFormatterCommand.monospace.rawValue) {
			monospaceItem.attributedTitle = NSAttributedString(
				string: monospaceItem.title,
				attributes: [.font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
			)
		}
		if let spoilerItem = formatterMenu.item(withTag: TextFormatterCommand.spoiler.rawValue) {
			spoilerItem.attributedTitle = NSAttributedString(
				string: spoilerItem.title,
				attributes: [
					.font: NSFont.menuFont(ofSize: 0),
					.foregroundColor: NSColor.windowBackgroundColor,
					.backgroundColor: NSColor.labelColor,
				]
			)
		}
	}

	static func formattingMenuImage(forColorTag tag: Int) -> NSImage? {
		if TextFormatterCommand(rawValue: tag) == .rainbowColor {
			return NSImage(systemSymbolName: "rainbow", accessibilityDescription: nil)
		}
		let colors = NSColor.formatterColors
		guard tag >= 0, tag < colors.count else { return nil }
		let color = colors[tag]
		let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
			let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
			color.setFill()
			circle.fill()
			NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
			circle.lineWidth = 1
			circle.stroke()
			return true
		}
		image.isTemplate = false
		return image
	}
}

// MARK: - Keyboard shortcuts

extension MainWindow {
	private func register(
		key: KeyCode,
		modifiers: NSEvent.ModifierFlags = [],
		perform action: @escaping (MainWindow, NSEvent) -> Void
	) {
		keyEventHandler.register(key: key, modifiers: modifiers) { [weak self] event in
			guard let self else { return }
			action(self, event)
		}
	}

	private func register(
		character: Character,
		modifiers: NSEvent.ModifierFlags,
		perform action: @escaping (MainWindow, NSEvent) -> Void
	) {
		keyEventHandler.register(character: character, modifiers: modifiers) { [weak self] event in
			guard let self else { return }
			action(self, event)
		}
	}

	private func registerInput(
		key: KeyCode,
		modifiers: NSEvent.ModifierFlags = [],
		perform action: @escaping (MainWindow, NSEvent) -> Void
	) {
		inputTextField.register(key: key, modifiers: modifiers) { [weak self] event in
			guard let self else { return }
			action(self, event)
		}
	}

	private func registerInput(
		character: Character,
		modifiers: NSEvent.ModifierFlags,
		perform action: @escaping (MainWindow, NSEvent) -> Void
	) {
		inputTextField.register(character: character, modifiers: modifiers) { [weak self] event in
			guard let self else { return }
			action(self, event)
		}
	}

	public func performedCustomKeyboardEvent(_ event: NSEvent) -> Bool {
		keyEventHandler.processKeyEvent(event)
	}

	@objc public func redirectKeyDown(_ event: NSEvent) {
		inputTextField.focus()
		guard event.keyCode != KeyCode.enter.rawValue, event.keyCode != KeyCode.returnKey.rawValue else { return }
		inputTextField.keyDown(with: event)
	}

	@objc public func memberListKeyDown(_ event: NSEvent) {
		redirectKeyDown(event)
	}

	@objc public func serverListKeyDown(_ event: NSEvent) {
		redirectKeyDown(event)
	}

	private func registerKeyHandlers() {
		register(key: .escape) { $0.exitFullscreenMode($1) }
		register(key: .tab) { $0.tab($1) }
		register(key: .tab, modifiers: .shift) { $0.shiftTab($1) }
		register(key: .tab, modifiers: .option) { $0.selectPreviousSelection($1) }
		register(character: "b", modifiers: .command) { $0.textFormattingBold($1) }
		register(character: "u", modifiers: [.control, .shift]) { $0.textFormattingUnderline($1) }
		register(character: "i", modifiers: [.control, .shift]) { $0.textFormattingItalic($1) }
		register(character: "c", modifiers: [.control, .shift]) { $0.textFormattingForegroundColor($1) }
		register(character: "h", modifiers: [.control, .shift]) { $0.textFormattingBackgroundColor($1) }
		register(character: ".", modifiers: .command) { $0.speakPendingNotifications($1) }
		register(character: "p", modifiers: .control) { $0.inputHistoryUp($1) }
		register(character: "n", modifiers: .control) { $0.inputHistoryDown($1) }

		registerInput(key: .enter, modifiers: .control) { $0.sendControlEnterMessageMaybe($1) }
		registerInput(key: .returnKey, modifiers: .command) { $0.sendMessageAsAction($1) }
		registerInput(key: .enter, modifiers: .command) { $0.sendMessageAsAction($1) }
		registerInput(character: "l", modifiers: [.option, .command]) { $0.focusWebview($1) }
		registerInput(key: .upArrow) { $0.inputHistoryUpWithScrollCheck($1) }
		registerInput(key: .upArrow, modifiers: .option) { $0.inputHistoryUpWithScrollCheck($1) }
		registerInput(key: .downArrow) { $0.inputHistoryDownWithScrollCheck($1) }
		registerInput(key: .downArrow, modifiers: .option) { $0.inputHistoryDownWithScrollCheck($1) }
	}
}

// MARK: - Navigation

public extension MainWindow {
	private func navigateServerListEntries(
		_ scannedRows: [IRCTreeItem]?,
		entryCount: Int,
		startingPoint: Int,
		isMovingDown: Bool,
		navigationType: ServerListNavigationMovement,
		selectionType: ServerListNavigationSelection
	) {
		guard entryCount > 0, startingPoint >= 0, startingPoint < entryCount else { return }
		var position = startingPoint
		repeat {
			position += isMovingDown ? 1 : -1
			if position >= entryCount || position < 0 {
				position = isMovingDown ? 0 : entryCount - 1
			}
			if position == startingPoint {
				return
			}
			guard let item = scannedRows?[position] ?? serverList.item(atRow: position) as? IRCTreeItem
			else { continue }
			switch selectionType {
			case .channel
				where item.isChannel == false && item.isPrivateMessage == false
				&& item.associatedChannel?.isDirectChat != true:
				continue
			case .server where item.isClient == false:
				continue
			default:
				break
			}
			let matches = navigationType == .all || (navigationType == .active && item.isActive) ||
				(navigationType == .unread && item.isUnread)
			if matches {
				select(item); return
			}
		} while true
	}

	@objc(navigateChannelEntries:withNavigationType:)
	func navigateChannelEntries(_ isMovingDown: Bool, withNavigationType navigationType: ServerListNavigationMovement) {
		if TextualPreferences.channelNavigationIsServerSpecific() {
			navigateChannelEntriesWithinServerScope(isMovingDown, navigationType: navigationType)
		} else {
			navigateChannelEntriesOutsideServerScope(isMovingDown, navigationType: navigationType)
		}
	}

	private func navigateChannelEntriesOutsideServerScope(
		_ isMovingDown: Bool,
		navigationType: ServerListNavigationMovement
	) {
		navigateServerListEntries(
			nil,
			entryCount: serverList.numberOfRows,
			startingPoint: serverList.row(forItem: selectedItem),
			isMovingDown: isMovingDown,
			navigationType: navigationType,
			selectionType: .channel
		)
	}

	private func navigateChannelEntriesWithinServerScope(
		_ isMovingDown: Bool,
		navigationType: ServerListNavigationMovement
	) {
		guard let selectedClient else { return }
		var rows = (serverList.items(inContainingGroupOf: selectedItem as Any) as? [IRCTreeItem]) ?? []
		rows.append(selectedClient)
		navigateServerListEntries(
			rows,
			entryCount: rows.count,
			startingPoint: rows.firstIndex(where: { $0 === selectedItem }) ?? -1,
			isMovingDown: isMovingDown,
			navigationType: navigationType,
			selectionType: .channel
		)
	}

	@objc(navigateServerEntries:withNavigationType:)
	func navigateServerEntries(_ isMovingDown: Bool, withNavigationType navigationType: ServerListNavigationMovement) {
		let rows = (serverList.groupItems as? [IRCTreeItem]) ?? []
		navigateServerListEntries(
			rows,
			entryCount: rows.count,
			startingPoint: rows.firstIndex(where: { $0 === selectedClient }) ?? -1,
			isMovingDown: isMovingDown,
			navigationType: navigationType,
			selectionType: .server
		)
	}

	@objc func navigateToNextEntry(_ isMovingDown: Bool) {
		navigateServerListEntries(
			nil,
			entryCount: serverList.numberOfRows,
			startingPoint: serverList.row(forItem: selectedItem),
			isMovingDown: isMovingDown,
			navigationType: .all,
			selectionType: .any
		)
	}

	@objc func selectPreviousChannel(_: NSEvent?) {
		navigateChannelEntries(false, withNavigationType: .all)
	}

	@objc func selectNextChannel(_: NSEvent?) {
		navigateChannelEntries(true, withNavigationType: .all)
	}

	@objc func selectPreviousUnreadChannel(_: NSEvent?) {
		navigateChannelEntries(false, withNavigationType: .unread)
	}

	@objc func selectNextUnreadChannel(_: NSEvent?) {
		navigateChannelEntries(true, withNavigationType: .unread)
	}

	@objc func selectPreviousActiveChannel(_: NSEvent?) {
		navigateChannelEntries(false, withNavigationType: .active)
	}

	@objc func selectNextActiveChannel(_: NSEvent?) {
		navigateChannelEntries(true, withNavigationType: .active)
	}

	@objc func selectPreviousServer(_: NSEvent?) {
		navigateServerEntries(false, withNavigationType: .all)
	}

	@objc func selectNextServer(_: NSEvent?) {
		navigateServerEntries(true, withNavigationType: .all)
	}

	@objc func selectPreviousActiveServer(_: NSEvent?) {
		navigateServerEntries(false, withNavigationType: .active)
	}

	@objc func selectNextActiveServer(_: NSEvent?) {
		navigateServerEntries(true, withNavigationType: .active)
	}

	@objc func selectPreviousSelection(_: NSEvent?) {
		selectPreviousItem()
	}

	@objc func selectNextWindow(_: NSEvent?) {
		navigateToNextEntry(true)
	}

	@objc func selectPreviousWindow(_: NSEvent?) {
		navigateToNextEntry(false)
	}
}
