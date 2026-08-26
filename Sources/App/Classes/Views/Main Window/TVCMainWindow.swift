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

private struct MainWindowShiftSelectionOptions: OptionSet {
	let rawValue: UInt

	static let maintainGrouping = Self(rawValue: 1 << 0)
	static let performDeselect = Self(rawValue: 1 << 1)
	static let performDeselectChildren = Self(rawValue: 1 << 2)
}

private struct MainWindowMouseLocation: OptionSet {
	let rawValue: UInt

	static let outsideWindow: Self = []
	static let insideWindow = Self(rawValue: 1 << 1)
	static let insideWindowTitle = Self(rawValue: 1 << 2)
	static let onTopOfWindowTitleControl = Self(rawValue: 1 << 3)
}

private enum MainWindowConstants {
	static let toggleServerListToolbarItem = NSToolbarItem.Identifier("TVCMainWindowToggleServerList")
	static let toggleMemberListToolbarItem = NSToolbarItem.Identifier("TVCMainWindowToggleMemberList")
	static let treeItemPasteboardType = NSPasteboard.PasteboardType("com.vakesz.glasstual.tree-item")
	static let restorableSelectionKey = "TVCMainWindowSelectedItems"
	static let sidebarFooterHeight: CGFloat = 32
	static let maximumSelectedRows: UInt = 6
}

@inline(__always)
private func nativeLogController(_ controller: TVCLogController) -> LogController {
	unsafeBitCast(controller, to: LogController.self)
}

@inline(__always)
private func legacyChannelUser(_ user: ChannelUser) -> IRCChannelUser {
	unsafeBitCast(user, to: IRCChannelUser.self)
}

@MainActor
@objc(TVCMainWindow)
@objcMembers
public final class MainWindow: NSWindow, NSWindowDelegate, NSWindowRestoration, NSToolbarDelegate,
	NSOutlineViewDataSource, NSOutlineViewDelegate, TVCServerListDelegate
{
	@IBOutlet private var channelView: MainWindowChannelView!
	@IBOutlet public var mainMenuProxy: TXMenuControllerMainWindowProxy!
	@IBOutlet public var formattingMenu: TextViewIRCFormattingMenu!
	@IBOutlet public var inputTextField: MainWindowTextView!
	@IBOutlet private var nibContentSplitView: NSSplitView!
	@IBOutlet public var loadingScreen: TVCMainWindowLoadingScreenView!
	@IBOutlet public var memberList: TVCMemberList!
	@IBOutlet public var serverList: ServerList!

	public private(set) var contentSplitViewController: NSSplitViewController!
	private var serverListSplitItem: NSSplitViewItem!
	private var memberListSplitItem: NSSplitViewItem!
	private var sidebarFooterController: NSSplitViewItemAccessoryViewController?
	private var inputHistory: InputHistory!
	private var nicknameCompletionStatus: NicknameCompletionStatus!
	private var appearanceStorage: MainWindowAppearance?
	public var userInterfaceObjects: MainWindowAppearance {
		guard let appearanceStorage else {
			preconditionFailure("Main-window appearance requested before the nib finished loading")
		}
		return appearanceStorage
	}

	public private(set) var selectedItems: [IRCTreeItem] = []
	public private(set) var selectedItem: IRCTreeItem?
	private var previousSelectedItemsId: [String] = []
	private var previousSelectedItemId: String?
	private var lastKeyWindowStateChange: TimeInterval = 0
	private var lastKeyWindowRedrawFailedBecauseOfOcclusion = false
	private var keyEventHandler: KeyEventHandler!
	private var cachedSwipeOriginPoint: NSPoint?
	public private(set) var textSizeMultiplier = 1.0
	private var isReloadingTheme = false
	private var hasAwakenedFromNib = false
	private var hasInstalledFieldEditorMenu = false

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
		keyEventHandler = KeyEventHandler(target: self)
		nicknameCompletionStatus = NicknameCompletionStatus(window: self)
	}

	override public nonisolated func awakeFromNib() {
		super.awakeFromNib()
		MainActor.assumeIsolated {
			guard hasAwakenedFromNib == false else { return }
			hasAwakenedFromNib = true
			finishAwakeningFromNib()
		}
	}

	private func finishAwakeningFromNib() {
		let controller = NSObject.masterController()
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
		controller.menuController?.perform(NSSelectorFromString("prepareInitialState"))
		registerKeyHandlers()
		controller.world.setupConfiguration()
		setupTrees()
		TVCDockIcon.drawWithoutCount()
		observeNotifications()
		controller.applicationWakeStepTwo()
	}

	private var world: IRCWorld {
		NSObject.masterController().world
	}

	private var menuController: TXMenuController {
		guard let menuController = NSObject.masterController().menuController else {
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
			label = LocalizedKey("TVCMainWindow[tb-sl]")
			action = #selector(toggleServerListVisibility)
			navigational = true
		case MainWindowConstants.toggleMemberListToolbarItem:
			symbolName = "sidebar.right"
			label = LocalizedKey("TVCMainWindow[tb-ml]")
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
			image: NSImage(systemSymbolName: "plus", accessibilityDescription: LocalizedKey("TVCMainWindow[ib-ad]"))!,
			target: self,
			action: #selector(presentSidebarAddMenu(_:))
		)
		configureSidebarButton(addButton, title: LocalizedKey("TVCMainWindow[ib-ad]"))

		let searchButton = sidebarFooterButton(
			symbolName: "magnifyingglass",
			title: LocalizedKey("TVCMainWindow[ib-sf]"),
			action: NSSelectorFromString("showChannelSpotlightWindow:")
		)
		let settingsButton = sidebarFooterButton(
			symbolName: "ellipsis.circle",
			title: LocalizedKey("TVCMainWindow[ib-mo]"),
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
		func item(_ title: String, _ symbol: String, _ action: String, _ tag: Int) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: "")
			item.target = menuController
			item.tag = tag
			item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
			return item
		}
		menu.addItem(item(LocalizedKey("TVCMainWindow[ib-m1]"), "checkmark.circle", "markAllAsRead:", 403))
		menu.addItem(item(LocalizedKey("TVCMainWindow[ib-m2]"), "bell.slash", "toggleMuteOnNotifications:", 200))
		menu.addItem(.separator())
		menu.addItem(item(LocalizedKey("TVCMainWindow[ib-m3]"), "person.crop.circle", "showAddressBook:", 813))
		menu.addItem(item(LocalizedKey("TVCMainWindow[ib-m4]"), "arrow.down.circle", "showFileTransfersWindow:", 817))
		menu.addItem(.separator())
		menu.addItem(item(LocalizedKey("TVCMainWindow[ib-m5]"), "sidebar.right", "toggleMemberListVisibility:", 803))
		menu.addItem(.separator())
		menu.addItem(item(LocalizedKey("TVCMainWindow[ib-st]"), "gear", "showPreferencesWindow:", 102))
		menuController.applySymbols(to: menu)
		menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height), in: anchor)
	}
}

// MARK: - Appearance and lifecycle

extension MainWindow {
	private func observeNotifications() {
		let center = NotificationCenter.default
		center.addObserver(
			self,
			selector: #selector(applicationAppearanceChanged(_:)),
			name: Notification.Name("TXApplicationAppearanceChangedNotification"),
			object: nil
		)
		center.addObserver(
			self,
			selector: #selector(systemAppearanceChanged(_:)),
			name: Notification.Name("TXSystemAppearanceChangedNotification"),
			object: nil
		)
		center.addObserver(
			self,
			selector: #selector(themeVarietyChanged(_:)),
			name: Notification.Name("TPCThemeAppearanceChangedNotification"),
			object: nil
		)
		center.addObserver(
			self,
			selector: #selector(themeVarietyChanged(_:)),
			name: Notification.Name("TPCThemeVarietyChangedNotification"),
			object: nil
		)
	}

	@objc private func themeVarietyChanged(_: Notification) {
		reloadTheme()
	}

	@objc private func applicationAppearanceChanged(_: Notification) {
		updateAppearance()
	}

	@objc private func systemAppearanceChanged(_: Notification) {
		notifySystemAppearanceChanged()
	}

	public var isUsingDarkAppearance: Bool {
		userInterfaceObjects.isDarkAppearance
	}

	private func updateAppearance() {
		guard let appearance = MainWindowAppearance(window: self) else { return }
		appearanceStorage = appearance
		self.appearance = appearance.appKitAppearanceTarget == .window ? appearance.appKitAppearance : nil
		notifyMainWindowAppearanceChanged()
	}

	private func notifyMainWindowAppearanceChanged() {
		contentView?.superview?.notifyApplicationAppearanceChanged()
		for controller in titlebarAccessoryViewControllers {
			controller.view.notifyApplicationAppearanceChanged()
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
		NotificationCenter.default.removeObserver(self)
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
		completionHandler(NSObject.masterController().mainWindow, nil)
	}

	override public func encodeRestorableState(with coder: NSCoder) {
		super.encodeRestorableState(with: coder)
		coder.encode(selectedItems.map(\.uniqueIdentifier), forKey: MainWindowConstants.restorableSelectionKey)
	}

	override public func restoreState(with coder: NSCoder) {
		super.restoreState(with: coder)
		guard let world = NSObject.masterController().world else { return }
		let classes: [AnyClass] = [NSArray.self, NSString.self]
		guard let identifiers = coder
			.decodeObject(of: classes, forKey: MainWindowConstants.restorableSelectionKey) as? [String],
			identifiers.isEmpty == false,
			let selection = world.findItems(withIds: identifiers) as? [IRCTreeItem],
			selection.isEmpty == false
		else { return }
		adjustSelection(with: selection, selectedItem: nil)
	}
}

// MARK: - Window delegate

public extension MainWindow {
	private func reloadMainWindowFrameOnScreenChange() {
		guard NSObject.masterController().applicationIsTerminating == false else { return }
		TVCDockIcon.resetCachedCount()
		TVCDockIcon.update()
		updateAppearance()
	}

	private func resetSelectedItemState() {
		guard NSObject.masterController().applicationIsTerminating == false else { return }
		if let selectedItem {
			selectedItem.resetState()
			noteItemWasViewed(selectedItem)
		}
		TVCDockIcon.update()
	}

	private func noteItemWasViewed(_ item: IRCTreeItem) {
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
		guard isOccluded == false else { return }
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
		if isOccluded {
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
		isInFullscreenMode == false
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
		if let monospaceItem = formatterMenu.item(withTag: 102) {
			monospaceItem.attributedTitle = NSAttributedString(
				string: monospaceItem.title,
				attributes: [.font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
			)
		}
		if let spoilerItem = formatterMenu.item(withTag: 103) {
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
		if tag == 299 {
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
	@objc public func setKeyHandlerTarget(_ target: Any) {
		keyEventHandler.setKeyHandlerTarget(target)
	}

	private func register(_ selector: Selector, key: UInt, modifiers: NSEvent.ModifierFlags = []) {
		keyEventHandler.register(selector, key: key, modifiers: modifiers.rawValue)
	}

	private func register(_ selector: Selector, character: UInt16, modifiers: NSEvent.ModifierFlags) {
		keyEventHandler.register(selector, character: character, modifiers: modifiers.rawValue)
	}

	private func registerInput(_ selector: Selector, key: UInt, modifiers: NSEvent.ModifierFlags = []) {
		inputTextField.register(selector, key: key, modifiers: modifiers.rawValue)
	}

	private func registerInput(_ selector: Selector, character: UInt16, modifiers: NSEvent.ModifierFlags) {
		inputTextField.register(selector, character: character, modifiers: modifiers.rawValue)
	}

	@objc public func performedCustomKeyboardEvent(_ event: NSEvent) -> Bool {
		keyEventHandler.processKeyEvent(event)
	}

	@objc public func redirectKeyDown(_ event: NSEvent) {
		inputTextField.focus()
		guard event.keyCode != TXKeyEnterCode, event.keyCode != TXKeyReturnCode else { return }
		inputTextField.keyDown(with: event)
	}

	@objc public func memberListKeyDown(_ event: NSEvent) {
		redirectKeyDown(event)
	}

	@objc public func serverListKeyDown(_ event: NSEvent) {
		redirectKeyDown(event)
	}

	private func registerKeyHandlers() {
		inputTextField.setKeyHandlerTarget(self)
		register(#selector(exitFullscreenMode(_:)), key: UInt(TXKeyEscapeCode))
		register(#selector(tab(_:)), key: UInt(TXKeyTabCode))
		register(#selector(shiftTab(_:)), key: UInt(TXKeyTabCode), modifiers: .shift)
		register(#selector(selectPreviousSelection(_:)), key: UInt(TXKeyTabCode), modifiers: .option)
		register(#selector(textFormattingBold(_:)), character: UInt16(Character("b").asciiValue!), modifiers: .command)
		register(
			#selector(textFormattingUnderline(_:)),
			character: UInt16(Character("u").asciiValue!),
			modifiers: [.control, .shift]
		)
		register(
			#selector(textFormattingItalic(_:)),
			character: UInt16(Character("i").asciiValue!),
			modifiers: [.control, .shift]
		)
		register(
			#selector(textFormattingForegroundColor(_:)),
			character: UInt16(Character("c").asciiValue!),
			modifiers: [.control, .shift]
		)
		register(
			#selector(textFormattingBackgroundColor(_:)),
			character: UInt16(Character("h").asciiValue!),
			modifiers: [.control, .shift]
		)
		register(
			#selector(speakPendingNotifications(_:)),
			character: UInt16(Character(".").asciiValue!),
			modifiers: .command
		)
		register(#selector(inputHistoryUp(_:)), character: UInt16(Character("p").asciiValue!), modifiers: .control)
		register(#selector(inputHistoryDown(_:)), character: UInt16(Character("n").asciiValue!), modifiers: .control)

		registerInput(#selector(sendControlEnterMessageMaybe(_:)), key: UInt(TXKeyEnterCode), modifiers: .control)
		registerInput(#selector(sendMessageAsAction(_:)), key: UInt(TXKeyReturnCode), modifiers: .command)
		registerInput(#selector(sendMessageAsAction(_:)), key: UInt(TXKeyEnterCode), modifiers: .command)
		registerInput(
			#selector(focusWebview(_:)),
			character: UInt16(Character("l").asciiValue!),
			modifiers: [.option, .command]
		)
		registerInput(#selector(inputHistoryUpWithScrollCheck(_:)), key: UInt(TXKeyUpArrowCode))
		registerInput(#selector(inputHistoryUpWithScrollCheck(_:)), key: UInt(TXKeyUpArrowCode), modifiers: .option)
		registerInput(#selector(inputHistoryDownWithScrollCheck(_:)), key: UInt(TXKeyDownArrowCode))
		registerInput(#selector(inputHistoryDownWithScrollCheck(_:)), key: UInt(TXKeyDownArrowCode), modifiers: .option)
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
		if TPCPreferences.channelNavigationIsServerSpecific() {
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
		var rows = (serverList.items(fromParentGroup: selectedItem as Any) as? [IRCTreeItem]) ?? []
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

	@objc func selectPreviousChannel(_: NSEvent) {
		navigateChannelEntries(false, withNavigationType: .all)
	}

	@objc func selectNextChannel(_: NSEvent) {
		navigateChannelEntries(true, withNavigationType: .all)
	}

	@objc func selectPreviousUnreadChannel(_: NSEvent) {
		navigateChannelEntries(false, withNavigationType: .unread)
	}

	@objc func selectNextUnreadChannel(_: NSEvent) {
		navigateChannelEntries(true, withNavigationType: .unread)
	}

	@objc func selectPreviousActiveChannel(_: NSEvent) {
		navigateChannelEntries(false, withNavigationType: .active)
	}

	@objc func selectNextActiveChannel(_: NSEvent) {
		navigateChannelEntries(true, withNavigationType: .active)
	}

	@objc func selectPreviousServer(_: NSEvent) {
		navigateServerEntries(false, withNavigationType: .all)
	}

	@objc func selectNextServer(_: NSEvent) {
		navigateServerEntries(true, withNavigationType: .all)
	}

	@objc func selectPreviousActiveServer(_: NSEvent) {
		navigateServerEntries(false, withNavigationType: .active)
	}

	@objc func selectNextActiveServer(_: NSEvent) {
		navigateServerEntries(true, withNavigationType: .active)
	}

	@objc func selectPreviousSelection(_: NSEvent) {
		selectPreviousItem()
	}

	@objc func selectNextWindow(_: NSEvent?) {
		navigateToNextEntry(true)
	}

	@objc func selectPreviousWindow(_: NSEvent?) {
		navigateToNextEntry(false)
	}
}

// MARK: - View controls and input

extension MainWindow {
	@objc public func changeTextSize(_ bigger: Bool) {
		let next = bigger ? textSizeMultiplier * 1.2 : textSizeMultiplier / 1.2
		guard (0.5 ... 3).contains(next) else { return }
		textSizeMultiplier = next
		for client in world.clientList {
			client.viewController.changeTextSize(bigger)
			for channel in client.channelList {
				channel.viewController.changeTextSize(bigger)
			}
		}
	}

	@objc public func markAllAsRead() {
		markAllAsRead(inGroup: nil)
	}

	@objc(markAllAsReadInGroup:)
	public func markAllAsRead(inGroup item: IRCTreeItem?) {
		let markScrollback = TPCPreferences.autoAddScrollbackMark()
		for client in world.clientList {
			if markScrollback {
				client.viewController.mark()
			}
			for channel in client.channelList {
				if markScrollback {
					channel.viewController.mark()
				}
				channel.resetState()
			}
		}
		TVCDockIcon.update()
		if let item {
			reloadTreeGroup(item)
		} else {
			reloadTree()
		}
	}

	@objc public func reloadTheme() {
		guard isReloadingTheme == false else { return }
		isReloadingTheme = true
		NotificationCenter.default.post(name: .mainWindowWillReloadTheme, object: self)
		DispatchQueue.main.async { [weak self] in
			guard let self, NSObject.masterController().applicationIsTerminating == false else { return }
			LogView.emptyCaches()
			performThemeReload()
		}
	}

	private func performThemeReload() {
		for client in world.clientList {
			client.viewController.perform(NSSelectorFromString("reloadTheme"))
			for channel in client.channelList {
				channel.viewController.reloadTheme()
			}
		}
		isReloadingTheme = false
		NotificationCenter.default.post(name: .mainWindowDidReloadTheme, object: self)
	}

	@objc(clearContentsOfClient:)
	public func clearContents(of client: IRCClient) {
		client.resetState()
		client.viewController.clear()
		reloadTreeItem(client)
	}

	@objc(clearContentsOfChannel:)
	public func clearContents(of channel: IRCChannel) {
		channel.resetState()
		channel.viewController.clear()
		reloadTreeItem(channel)
	}

	@objc public func clearAllViews() {
		for client in world.clientList {
			clearContents(of: client)
			for channel in client.channelList {
				clearContents(of: channel)
			}
		}
		markAllAsRead()
	}

	private func completeNickname(_ movingForward: Bool) {
		nicknameCompletionStatus.completeNickname(movingForward)
	}

	@objc private func tab(_: NSEvent) {
		switch TPCPreferences.tabKeyAction() {
		case .nicknameComplete: completeNickname(true)
		case .unreadChannel: navigateChannelEntries(true, withNavigationType: .unread)
		default: break
		}
	}

	@objc private func shiftTab(_: NSEvent) {
		switch TPCPreferences.tabKeyAction() {
		case .nicknameComplete: completeNickname(false)
		case .unreadChannel: navigateChannelEntries(false, withNavigationType: .unread)
		default: break
		}
	}

	@objc private func sendControlEnterMessageMaybe(_ event: NSEvent) {
		if TPCPreferences.controlEnterSendsMessage() {
			textEntered()
		} else {
			inputTextField.keyDownToSuper(event)
		}
	}

	@objc private func sendMessageAsAction(_: NSEvent) {
		if TPCPreferences.commandReturnSendsMessageAsAction() {
			inputTextAsCommand(.privmsgAction)
		} else {
			textEntered()
		}
	}

	private func moveInputHistory(_ movingUp: Bool, checkScroller: Bool, event: NSEvent) {
		if checkScroller {
			let caret = inputTextField.caretLocation
			if caret != .onlyLine {
				let atTop = caret == .firstLine
				let atBottom = caret == .lastLine
				if (atTop && event.keyCode == TXKeyDownArrowCode) || (atBottom && event.keyCode == TXKeyUpArrowCode) ||
					(atTop == false && atBottom == false)
				{
					inputTextField.keyDownToSuper(event)
					return
				}
			}
		}
		let value = inputTextField.attributedStringValue
		guard let newValue = movingUp ? inputHistory.up(value) : inputHistory.down(value) else { return }
		inputTextField.attributedStringValue = newValue
		inputTextField.focus()
		if movingUp == false {
			inputTextField.setSelectedRange(NSRange(location: 0, length: 0))
		}
	}

	@objc private func inputHistoryUp(_ event: NSEvent) {
		moveInputHistory(true, checkScroller: false, event: event)
	}

	@objc private func inputHistoryDown(_ event: NSEvent) {
		moveInputHistory(false, checkScroller: false, event: event)
	}

	@objc private func inputHistoryUpWithScrollCheck(_ event: NSEvent) {
		moveInputHistory(
			true,
			checkScroller: true,
			event: event
		)
	}

	@objc private func inputHistoryDownWithScrollCheck(_ event: NSEvent) {
		moveInputHistory(
			false,
			checkScroller: true,
			event: event
		)
	}

	@objc private func textFormattingBold(_: NSEvent) {
		if formattingMenu.textIsBold {
			formattingMenu.removeBoldCharFromTextBox(nil)
		} else {
			formattingMenu.insertBoldCharIntoTextBox(nil)
		}
	}

	@objc private func textFormattingItalic(_: NSEvent) {
		if formattingMenu.textIsItalicized {
			formattingMenu.removeItalicCharFromTextBox(nil)
		} else {
			formattingMenu.insertItalicCharIntoTextBox(nil)
		}
	}

	@objc private func textFormattingStrikethrough(_: NSEvent) {
		if formattingMenu.textIsStruckthrough {
			formattingMenu.removeStrikethroughCharFromTextBox(nil)
		} else {
			formattingMenu.insertStrikethroughCharIntoTextBox(nil)
		}
	}

	@objc private func textFormattingUnderline(_: NSEvent) {
		if formattingMenu.textIsUnderlined {
			formattingMenu.removeUnderlineCharFromTextBox(nil)
		} else {
			formattingMenu.insertUnderlineCharIntoTextBox(nil)
		}
	}

	@objc private func textFormattingForegroundColor(_: NSEvent) {
		guard formattingMenu.textHasSpoiler == false else { return }
		if formattingMenu.textHasForegroundColor {
			formattingMenu.removeForegroundColorCharFromTextBox(nil)
			return
		}
		var point = inputTextField.frame.origin
		point.y -= 200
		point.x += 100
		let menu: NSMenu = formattingMenu.foregroundColorMenu
		menu.popUp(positioning: nil, at: point, in: inputTextField)
	}

	@objc private func textFormattingBackgroundColor(_: NSEvent) {
		guard formattingMenu.textHasSpoiler == false, formattingMenu.textHasForegroundColor else { return }
		if formattingMenu.textHasBackgroundColor {
			formattingMenu.removeForegroundColorCharFromTextBox(nil)
			return
		}
		var point = inputTextField.frame.origin
		point.y -= 200
		point.x += 100
		let menu: NSMenu = formattingMenu.backgroundColorMenu
		menu.popUp(positioning: nil, at: point, in: inputTextField)
	}

	@objc private func exitFullscreenMode(_ event: NSEvent) {
		if isInFullscreenMode {
			toggleFullScreen(nil)
		} else {
			inputTextField.keyDown(with: event)
		}
	}

	@objc private func speakPendingNotifications(_: NSEvent) {
		SharedApplication.sharedSpeechSynthesizer().stopSpeakingAndMoveForward()
	}

	@objc private func focusWebview(_: NSEvent) {
		guard attachedSheet == nil, let view = selectedViewController?.backingView.webView else { return }
		makeFirstResponder(view)
	}

	@objc public func textEntered() {
		inputTextAsCommand(.privmsg)
	}

	private func inputTextAsCommand(_ command: IRCRemoteCommand) {
		nicknameCompletionStatus.clear()
		let value = inputTextField.attributedStringValue
		guard value.length > 0 else { return }
		inputTextField.attributedStringValue = NSAttributedString(string: "")
		inputHistory.add(value)
		inputTextField.consumeReply(into: selectedClient)
		inputText(value, asCommand: command)
	}

	@objc(inputText:asCommand:)
	public func inputText(_ string: Any, asCommand command: IRCRemoteCommand) {
		guard selectedItem != nil,
		      let value = PluginDispatcher.interceptUserInput(string, command: command)
		else { return }
		selectedClient?.inputText(value, as: command)
	}
}

// MARK: - Gestures and window utilities

public extension MainWindow {
	override func swipe(with event: NSEvent) {
		let x = event.deltaX * (event.isDirectionInvertedFromDevice ? -1 : 1)
		if x > 0 {
			selectNextWindow(nil)
		} else if x < 0 {
			selectPreviousWindow(nil)
		}
	}

	override func beginGesture(with event: NSEvent) {
		guard TPCPreferences.swipeMinimumLength() >= 1 else { return }
		let touches = Array(event.touches(matching: .touching, in: nil))
		guard touches.count == 2 else { return }
		cachedSwipeOriginPoint = point(between: touches[0], and: touches[1])
	}

	private func point(between first: NSTouch, and second: NSTouch) -> NSPoint {
		let size = first.deviceSize
		return NSPoint(
			x: (first.normalizedPosition.x + second.normalizedPosition.x) / 2 * size.width,
			y: (first.normalizedPosition.y + second.normalizedPosition.y) / 2 * size.height
		)
	}

	override func endGesture(with event: NSEvent) {
		let minimum = TPCPreferences.swipeMinimumLength()
		guard minimum >= 1 else { return }
		let touches = Array(event.touches(matching: .any, in: nil))
		guard let origin = cachedSwipeOriginPoint, touches.count == 2 else {
			cachedSwipeOriginPoint = nil
			return
		}
		let destination = point(between: touches[0], and: touches[1])
		cachedSwipeOriginPoint = nil
		let delta = NSPoint(x: origin.x - destination.x, y: origin.y - destination.y)
		guard abs(delta.x) >= abs(delta.y), abs(delta.x) >= minimum else { return }
		let x = delta.x * (event.isDirectionInvertedFromDevice ? -1 : 1)
		if x > 0 {
			selectPreviousWindow(nil)
		} else {
			selectNextWindow(nil)
		}
	}

	@objc func locationOfMouseInWindow() -> UInt {
		locationOfMouseValue(NSEvent.mouseLocation).rawValue
	}

	@objc func locationOfMouse(_ location: NSPoint) -> UInt {
		locationOfMouseValue(location).rawValue
	}

	private func locationOfMouseValue(_ location: NSPoint) -> MainWindowMouseLocation {
		guard frame.contains(location) else { return .outsideWindow }
		let titleFrame = titlebarFrame
		guard titleFrame.contains(location) else { return .insideWindow }
		let titleLocation: MainWindowMouseLocation = [.insideWindow, .insideWindowTitle]
		func contains(_ view: NSView?) -> Bool {
			guard let view else { return false }
			var frame = view.frame
			frame.origin.x += titleFrame.origin.x
			frame.origin.y += titleFrame.origin.y
			return frame.contains(location)
		}
		if contains(standardWindowButton(.closeButton)) || contains(standardWindowButton(.miniaturizeButton)) ||
			contains(standardWindowButton(.zoomButton))
		{
			return [titleLocation, .onTopOfWindowTitleControl]
		}
		if titlebarAccessoryViewControllers.contains(where: { contains($0.view.superview) }) {
			return [titleLocation, .onTopOfWindowTitleControl]
		}
		return titleLocation
	}

	@objc func preferencesChanged() {
		if TPCPreferences.displayDockBadge() {
			TVCDockIcon.resetCachedCount(); TVCDockIcon.update()
		} else {
			TVCDockIcon.drawWithoutCount()
		}
	}

	override func endEditing(for object: Any?) {
		if makeFirstResponder(self) == false {
			super.endEditing(for: object)
		}
	}

	override var canBecomeKey: Bool {
		true
	}

	override var canBecomeMain: Bool {
		true
	}

	var isDisabled: Bool {
		false
	}

	override func makeKeyAndOrderFront(_: Any?) {
		guard isDisabled == false else { return }
		super.makeKeyAndOrderFront(nil)
	}

	override func orderFront(_: Any?) {
		guard isDisabled == false else { return }
		super.orderFront(nil)
	}

	var defaultWindowFrame: NSRect {
		var value = frame
		value.size = userInterfaceObjects.defaultWindowSize
		return value
	}
}

// MARK: - Selection and split view

public extension MainWindow {
	var multipleItemsSelected: Bool {
		selectedItems.count > 1
	}

	var previouslySelectedItem: IRCTreeItem? {
		guard let previousSelectedItemId else { return nil }
		return world.findItem(withId: previousSelectedItemId)
	}

	var selectedClient: IRCClient? {
		selectedItem?.associatedClient
	}

	var selectedChannel: IRCChannel? {
		guard let selectedItem, selectedItem.isClient == false else { return nil }
		return selectedItem as? IRCChannel
	}

	var selectedViewController: LogController? {
		if let controller = selectedChannel?.viewController {
			return controller
		}
		guard let controller = selectedClient?.viewController else { return nil }
		return nativeLogController(controller)
	}

	@objc func channelViewSelectionChange(to item: IRCTreeItem) {
		selectItemInSelectedItems(
			item,
			refreshChannelView: false
		)
	}

	@objc func updateChannelViewArrangement() {
		channelView.updateArrangement()
	}

	@objc func updateChannelViewBoxContentViewSelection() {
		channelView.populateSubviews()
	}

	@objc func isItemVisible(_ item: IRCTreeItem) -> Bool {
		isItemSelected(item) || isItemInSelectedGroup(item)
	}

	@objc func isItemSelected(_ item: IRCTreeItem?) -> Bool {
		item != nil && selectedItem === item
	}

	@objc func isItemInSelectedGroup(_ item: IRCTreeItem) -> Bool {
		selectedItems.contains(where: { $0 === item })
	}

	private func selectionDidChange(toRows _: IndexSet, selectedItem requestedItem: IRCTreeItem? = nil) {
		let newItems = serverList.selectedObjects as? [IRCTreeItem] ?? []
		if selectedItems.elementsEqual(newItems, by: { $0 === $1 }) {
			if let requestedItem {
				selectItemInSelectedItems(requestedItem)
			}
			return
		}

		storePreviousSelection()
		let previousItems = selectedItems
		if newItems.isEmpty {
			selectedItems = []
			selectedItem = nil
		} else {
			selectedItems = newItems
			let candidate = requestedItem ?? selectedItem
			selectedItem = candidate.map(isItemInSelectedGroup) == true ? candidate : newItems.last
		}

		updateChannelViewBoxContentViewSelection()
		for item in previousItems where newItems.contains(where: { $0 === item }) == false {
			item.viewController.notifyDidBecomeHidden()
		}
		for item in newItems where previousItems.contains(where: { $0 === item }) == false {
			item.viewController.notifyDidBecomeVisible()
			if item !== selectedItem {
				item.viewController.notifySelectionChanged()
			}
		}
		selectionDidChangePostflight()
	}

	private func selectionDidChangePostflight() {
		invalidateRestorableState()
		let changedTo = selectedItem
		let changedFrom = previouslySelectedItem
		guard changedTo !== changedFrom else { return }
		changedFrom?.resetState()
		if let changedTo {
			if multipleItemsSelected {
				serverList.refreshMessageCount(forItem: changedTo)
			}
			changedTo.resetState()
			noteItemWasViewed(changedTo)
		}
		changedFrom?.viewController.notifySelectionChanged()

		guard let changedTo else {
			memberList.assign(to: nil)
			serverList.menu = nil
			updateTitle()
			return
		}

		if changedTo.isClient {
			serverList.menu = menuController.mainMenuServerMenuItem?.submenu
		} else if changedTo.isChannel {
			serverList.menu = menuController.mainMenuChannelMenu
		} else {
			serverList.menu = menuController.mainMenuQueryMenu
		}

		memberList.assign(to: changedTo.isChannel ? changedTo as? IRCChannel : nil)
		if TPCPreferences.focusMainTextViewOnSelectionChange(),
		   XRAccessibility.isVoiceOverEnabled() == false
		{
			inputTextField.focus()
		}
		inputHistory.moveFocus(to: changedTo)
		inputTextField.resetSpellingIgnores()
		if changedTo.isChannel, memberList.isHiddenByUser == false {
			expandMemberList()
		} else {
			collapseMemberList()
		}
		changedTo.viewController.notifySelectionChanged()
		storeLastSelectedChannel()
		NotificationCenter.default.post(name: .mainWindowSelectionChanged, object: self)
		TVCDockIcon.update()
		updateTitle()
	}

	private func saveContentSplitViewState() {
		UserDefaults.standard.set(isServerListVisible, forKey: "Window -> Main Window -> Server List is Visible")
		UserDefaults.standard.set(
			memberList.isHiddenByUser == false,
			forKey: "Window -> Main Window -> Member List is Visible"
		)
	}

	private func restoreSavedContentSplitViewState() {
		let defaults = UserDefaults.standard
		let memberVisible = (defaults.object(forKey: "Window -> Main Window -> Member List is Visible") as? NSNumber)?
			.boolValue ?? true
		memberList.isHiddenByUser = !memberVisible
		memberListSplitItem.isCollapsed = !memberVisible
		let serverVisible = (defaults.object(forKey: "Window -> Main Window -> Server List is Visible") as? NSNumber)?
			.boolValue ?? true
		serverListSplitItem.isCollapsed = !serverVisible
	}

	@objc func expandServerList() {
		serverListSplitItem.animator().isCollapsed = false
	}

	@objc func collapseServerList() {
		serverListSplitItem.animator().isCollapsed = true
	}

	@objc func toggleServerListVisibility() {
		serverListSplitItem.animator().isCollapsed = !serverListSplitItem.isCollapsed
	}

	@objc func expandMemberList() {
		memberListSplitItem.animator().isCollapsed = false
	}

	@objc func collapseMemberList() {
		memberListSplitItem.animator().isCollapsed = true
	}

	@objc func toggleMemberListVisibility() {
		memberListSplitItem.animator().isCollapsed = !memberListSplitItem.isCollapsed
	}

	var isMemberListVisible: Bool {
		memberListSplitItem?.isCollapsed == false
	}

	var isServerListVisible: Bool {
		serverListSplitItem?.isCollapsed == false
	}

	@objc func setLoadingScreenProgressViewReason(_ reason: String) {
		loadingScreen.setProgressViewReason(reason)
	}

	@objc func reloadLoadingScreen() -> Bool {
		guard let world = NSObject.masterController().world else {
			loadingScreen.showProgressView(withReason: LocalizedKey("TVCMainWindow[iph-a9]"))
			return false
		}
		if world.isImportingConfiguration {
			return false
		}
		if NSObject.masterController().applicationIsLaunched == false {
			loadingScreen.showProgressView(withReason: LocalizedKey("TVCMainWindow[iph-a9]"))
			return false
		}
		if world.clientCount <= 0 {
			loadingScreen.showWelcomeAddServerView()
			return false
		}
		loadingScreen.hideAnimated()
		return true
	}
}

// MARK: - Window title

public extension MainWindow {
	@objc func updateTitle(for item: IRCTreeItem) {
		if isItemSelected(item) {
			updateTitle()
		}
	}

	@objc func updateTitle() {
		guard let client = selectedClient else {
			title = TPCApplicationInfo.applicationName()
			subtitle = ""
			return
		}
		let channel = selectedChannel
		let status: String? = {
			if client.isConnected == false,
			   client
			   .isConnecting ==
			   false
			{
				return client
					.isReconnecting ? LocalizedKey("TVCMainWindow[st-wr]") : LocalizedKey("TVCMainWindow[st-dc]")
			}
			if client.isConnecting,
			   client
			   .isLoggedIn ==
			   false
			{
				return [.retry, .reconnect]
					.contains(client.connectType) ? LocalizedKey("TVCMainWindow[st-rc]") :
					LocalizedKey("TVCMainWindow[st-cn]")
			}
			if client.isConnected, client.isLoggedIn == false {
				return LocalizedKey("TVCMainWindow[st-lo]")
			}
			if client.isQuitting {
				return LocalizedKey("TVCMainWindow[st-dq]")
			}
			return nil
		}()

		var nickname = client.userNickname
		if client.userIsAway, nickname.isEmpty == false {
			nickname += LocalizedKey("TVCMainWindow[nxz-l9]")
		}
		let network = client.networkNameAlt
		var parts = [String]()
		if let channel {
			title = channel.name
			if let status, status.isEmpty == false {
				parts.append(status)
			}
			if network.isEmpty == false {
				parts.append(network)
			}
			if nickname.isEmpty == false {
				parts.append(nickname)
			}
			switch channel.type {
			case .channel:
				parts.append(LocalizedKey("TVCMainWindow[st-uc]", formattedNumber(Int(channel.numberOfMembers))))
				if let modes = channel.modeInfo?.stringWithMaskedPassword, modes.count > 1 {
					parts.append(modes)
				}
			case .privateMessage:
				if let hostmask = client.findUser(channel.name)?.hostmaskFragment,
				   hostmask.isEmpty == false
				{
					parts.append(hostmask)
				}
			case .directChat:
				parts.append(LocalizedKey("TVCMainWindow[dcc-ch]"))
			case .utility:
				break
			@unknown default:
				break
			}
		} else {
			title = network.isEmpty ? TPCApplicationInfo.applicationName() : network
			if let status, status.isEmpty == false {
				parts.append(status)
			}
			if nickname.isEmpty == false {
				parts.append(nickname)
			}
			if let serverAddress = client.serverAddress, serverAddress.isEmpty == false {
				parts.append(serverAddress)
			}
		}
		subtitle = parts.joined(separator: " · ")
		setAccessibilityTitle(LocalizedKey("Accessibility[k79-1a]"))
	}

	@objc func updateDrawingForUserInUserList(_ user: User) {
		guard let selectedChannel, let channelUser = user.userAssociated(with: selectedChannel) else { return }
		memberList.refreshDrawing(forMember: legacyChannelUser(channelUser))
	}
}

// MARK: - Server list model and selection

public extension MainWindow {
	private func saveSelection() {
		UserDefaults.standard.set(
			selectedItems.map(\.uniqueIdentifier),
			forKey: "Window -> Main Window -> Server List Selection"
		)
	}

	private func restoreExpandedClients() {
		for client in world.clientList
			where client.config.sidebarItemExpanded
		{
			expandClient(client)
		}
	}

	private func restoreSelectionDuringSetup() {
		guard let identifiers = UserDefaults.standard
			.array(forKey: "Window -> Main Window -> Server List Selection") as? [String],
			identifiers.isEmpty == false,
			let selection = world.findItems(withIds: identifiers) as? [IRCTreeItem],
			selection.isEmpty == false
		else {
			selectBestChoiceDuringSetup()
			return
		}
		adjustSelection(with: selection, selectedItem: nil)
	}

	private func selectBestChoiceDuringSetup() {
		let first = world.clientList.first(where: { $0.config.autoConnect && $0.config.sidebarItemExpanded })
		if let first {
			var row = serverList.row(forItem: first)
			if first.channelCount > 0 {
				row += 1
			}
			serverList.selectItem(at: UInt(row))
		} else {
			serverList.selectItem(at: 0)
		}
	}

	private func setupTrees() {
		memberList.keyDelegate = self
		memberList.target = menuController
		memberList.doubleAction = NSSelectorFromString("memberInMemberListDoubleClicked:")
		serverList.keyDelegate = self
		serverList.delegate = self
		serverList.dataSource = self
		serverList.target = self
		serverList.doubleAction = #selector(outlineViewDoubleClicked(_:))
		serverList.registerForDraggedTypes([MainWindowConstants.treeItemPasteboardType])
		restoreExpandedClients()
		restoreSelectionDuringSetup()
		serverListSelectionDidChange(for: nil)
		menuController.populateNavigationChannelList()
	}

	@objc func selectedChannel(on client: IRCClient) -> IRCChannel? {
		selectedClient === client ?
			selectedChannel : nil
	}

	@objc func reloadTreeItem(_ item: IRCTreeItem) {
		serverList.refreshDrawing(forItem: item)
	}

	@objc func reloadTreeGroup(_ item: IRCTreeItem) {
		guard item.isClient, let client = item.associatedClient else { return }
		reloadTreeItem(client)
		for channel in client.channelList {
			reloadTreeItem(channel)
		}
	}

	@objc func reloadTree() {
		serverList.refreshAllDrawings()
	}

	@objc func expandClient(_ client: IRCClient) {
		serverList.animator().expandItem(client)
	}

	@objc func adjustSelection() {
		adjustSelection(with: selectedItems, selectedItem: selectedItem)
	}

	private func adjustSelection(with items: [IRCTreeItem], selectedItem: IRCTreeItem?) {
		let rows = NSMutableIndexSet()
		for item in items {
			if item.isClient == false {
				serverList.expandItem(item.associatedClient)
			}
			let row = serverList.row(forItem: item)
			if row >= 0 {
				rows.add(row)
			}
		}
		if serverList.selectedRowIndexes != rows as IndexSet {
			ignoreNextOutlineViewSelectionChange = true
			serverList.selectRowIndexes(rows as IndexSet, byExtendingSelection: false, scrollToSelection: true)
		}
		selectionDidChange(toRows: rows as IndexSet, selectedItem: selectedItem)
	}

	private func storePreviousSelection() {
		previousSelectedItemId = selectedItem?.uniqueIdentifier
		storePreviousSelections()
	}

	private func storePreviousSelections() {
		previousSelectedItemsId = selectedItems.map(\.uniqueIdentifier)
	}

	private func storeLastSelectedChannel() {
		selectedClient?.perform(NSSelectorFromString("setLastSelectedChannel:"), with: selectedChannel)
	}

	@objc func selectPreviousItem() {
		guard let previous = previouslySelectedItem else { return }
		let previousItems = previousSelectedItemsId.compactMap { world.findItem(withId: $0) }
		adjustSelection(with: previousItems, selectedItem: previous)
	}

	private func selectItemInSelectedItems(_ item: IRCTreeItem, refreshChannelView: Bool = true) {
		guard isItemSelected(item) == false, isItemInSelectedGroup(item) else { return }
		storePreviousSelection()
		selectedItem = item
		if refreshChannelView {
			updateChannelViewBoxContentViewSelection()
		}
		selectionDidChangePostflight()
	}

	@objc(select:)
	func select(_ item: IRCTreeItem?) {
		shiftSelection(from: selectedItem, to: item, options: [.maintainGrouping, .performDeselect])
	}

	@objc(deselect:)
	func deselect(_ item: IRCTreeItem) {
		shiftSelection(from: item, to: nil, options: .performDeselect)
	}

	@objc(deselectGroup:)
	func deselectGroup(_ item: IRCTreeItem) {
		guard item.isClient else { return }
		shiftSelection(from: item, to: nil, options: [.performDeselect, .performDeselectChildren])
	}

	private func shiftSelection(
		from oldItem: IRCTreeItem?,
		to newItem: IRCTreeItem?,
		options: MainWindowShiftSelectionOptions
	) {
		guard oldItem !== newItem else { return }
		if let newItem, newItem.isClient == false {
			expandClient(newItem.associatedClient)
		}
		let maintainGrouping = options.contains(.maintainGrouping)
		let deselectOld = options.contains(.performDeselect)
		let deselectChildren = options.contains(.performDeselectChildren)
		let performDeselect = deselectOld || deselectChildren
		let oldIndex = serverList.row(forItem: oldItem)
		let newIndex = serverList.row(forItem: newItem)
		let selectedRows = serverList.selectedRowIndexes
		if performDeselect, oldIndex >= 0, selectedRows.contains(oldIndex) == false {
			return
		}
		if maintainGrouping, oldIndex >= 0, selectedRows.contains(oldIndex), newIndex >= 0,
		   selectedRows.contains(newIndex), let newItem
		{
			selectItemInSelectedItems(newItem)
			return
		}

		var nextRows = selectedRows
		var forbiddenRows: IndexSet?
		if deselectOld {
			nextRows.removeAll()
		}
		if deselectChildren, let oldItem, let children = serverList.indexesOfItems(inGroup: oldItem) as IndexSet? {
			nextRows.subtract(children)
			forbiddenRows = children
		}
		if newItem != nil {
			guard newIndex >= 0 else { return }
			nextRows.insert(newIndex)
		} else if nextRows.isEmpty {
			var next = oldIndex + 1
			if forbiddenRows?.contains(next) == true, let last = forbiddenRows?.last {
				next = last + 1
			}
			if next >= serverList.numberOfRows {
				next = oldIndex - 1
			}
			if forbiddenRows?.contains(next) == true, let first = forbiddenRows?.first {
				next = first - 1
			}
			if next >= 0 {
				nextRows.insert(next)
			}
		}

		if nextRows.isEmpty {
			storePreviousSelection()
			selectedItem = nil
			selectedItems = []
			selectionDidChangePostflight()
			return
		}
		serverList.selectRowIndexes(nextRows, byExtendingSelection: false, scrollToSelection: true)
	}
}

// MARK: - Outline view data source and delegate

public extension MainWindow {
	@objc private func outlineViewDoubleClicked(_: Any?) {
		guard let client = selectedClient else { return }
		if let channel = selectedChannel {
			guard client.isLoggedIn else { return }
			if channel.isActive {
				if TPCPreferences.leaveOnDoubleclick() {
					client.part(channel)
				}
			} else if TPCPreferences.joinOnDoubleclick() {
				client.join(channel)
			}
		} else {
			if client.isConnecting || client.isConnected {
				if TPCPreferences.disconnectOnDoubleclick() {
					client.quit()
				}
			} else if client.isQuitting == false, TPCPreferences.connectOnDoubleclick() {
				client.connect()
			}
			expandClient(client)
		}
	}

	func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if let item = item as? IRCTreeItem {
			return Int(item.numberOfChildren)
		}
		return Int(NSObject.masterController().world?.clientCount ?? 0)
	}

	func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
		(item as? IRCTreeItem)?.numberOfChildren ?? 0 > 0
	}

	func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if let item = item as? IRCTreeItem {
			guard let child = item.child(at: UInt(index)) else {
				preconditionFailure("Server-list item reported a child count that it cannot satisfy")
			}
			return child
		}
		return NSObject.masterController().world!.clientList[index]
	}

	func outlineView(_: NSOutlineView, objectValueFor _: NSTableColumn?, byItem item: Any?) -> Any? {
		item
	}

	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		if (item as? IRCTreeItem)?
			.isClient != false
		{
			return ServerListGroupRowCell(serverList: outlineView as! ServerList)
		}
		return ServerListChildRowCell(serverList: outlineView as! ServerList)
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor _: NSTableColumn?, item: Any) -> NSView? {
		let identifier = NSUserInterfaceItemIdentifier((item as? IRCTreeItem)?
			.isClient != false ? "GroupView" : "ChildView")
		return outlineView.makeView(withIdentifier: identifier, owner: self)
	}

	func outlineView(_: NSOutlineView, didAdd _: NSTableRowView, forRow row: Int) {
		serverList.refreshDrawing(forRow: row)
	}

	func outlineViewItemDidCollapse(_ notification: Notification) {
		(notification.userInfo?["NSObject"] as? IRCTreeItem)?.associatedClient.sidebarItemIsExpanded = false
	}

	func outlineViewItemDidExpand(_ notification: Notification) {
		(notification.userInfo?["NSObject"] as? IRCTreeItem)?.associatedClient.sidebarItemIsExpanded = true
	}

	func outlineView(_: NSOutlineView, shouldExpandItem _: Any) -> Bool {
		true
	}

	func outlineView(_: NSOutlineView, shouldCollapseItem _: Any) -> Bool {
		true
	}

	func outlineViewItemWillCollapse(_: Notification) {}

	func selectionShouldChange(in outlineView: NSOutlineView) -> Bool {
		guard let serverList = outlineView as? ServerList else { return true }
		if serverList.invalidatingBackgroundForSelection {
			return true
		}
		if isKeyWindow == false {
			return false
		}
		if serverList.leftMouseIsDownInView == false {
			return true
		}
		let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
		if modifiers.contains(.command) || modifiers.contains(.shift) {
			return true
		}
		let row = outlineView.rowBeneathMouse
		guard row >= 0, outlineView.isRowSelected(row),
		      let item = outlineView.item(atRow: row) as? IRCTreeItem else { return true }
		selectItemInSelectedItems(item)
		return false
	}

	func outlineView(
		_ outlineView: NSOutlineView,
		selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet
	) -> IndexSet {
		outlineView.selectionIndexes(
			forProposedSelection: proposedSelectionIndexes,
			maximumNumberOfSelections: MainWindowConstants.maximumSelectedRows
		)
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		serverListSelectionDidChange(for: notification.object as? ServerList)
	}

	private func serverListSelectionDidChange(for changedList: ServerList?) {
		let list = changedList ?? serverList!
		guard list.invalidatingBackgroundForSelection == false else { return }
		if ignoreNextOutlineViewSelectionChange {
			ignoreNextOutlineViewSelectionChange = false; return
		}
		guard ignoreOutlineViewSelectionChanges == false else { return }
		let rows = list.selectedRowIndexes
		var focusedItem: IRCTreeItem?
		if NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
			let row = list.rowBeneathMouse
			if row >= 0, rows.contains(row) {
				focusedItem = list.item(atRow: row) as? IRCTreeItem
			}
		}
		selectionDidChange(toRows: rows, selectedItem: focusedItem)
	}

	func outlineView(_: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
		guard let item = item as? IRCTreeItem else { return nil }
		let value = NSPasteboardItem()
		value.setString(
			world.pasteboardString(for: item),
			forType: MainWindowConstants.treeItemPasteboardType
		)
		return value
	}

	func outlineView(
		_: NSOutlineView,
		validateDrop info: any NSDraggingInfo,
		proposedItem item: Any?,
		proposedChildIndex index: Int
	) -> NSDragOperation {
		guard index >= 0, let draggedItem = draggedItem(from: info) else { return [] }
		if draggedItem.isClient {
			return item == nil ? .generic : []
		}
		guard let client = item as? IRCClient, draggedItem.associatedClient === client else { return [] }
		let channels = client.channelList
		let previous = index > 0 && index - 1 < channels.count ? channels[index - 1] : nil
		let next = index < channels.count ? channels[index] : nil
		if draggedItem.isChannel, previous?.isChannel == false, previous != nil {
			return []
		}
		if draggedItem.isChannel == false, next?.isChannel == true {
			return []
		}
		return .generic
	}

	func outlineView(
		_ outlineView: NSOutlineView,
		acceptDrop info: any NSDraggingInfo,
		item: Any?,
		childIndex index: Int
	) -> Bool {
		guard index >= 0, let draggedItem = draggedItem(from: info),
		      let list = outlineView as? ServerList else { return false }
		if draggedItem.isClient {
			var clients = world.clientList
			guard let original = clients.firstIndex(where: { $0 === draggedItem }) else { return false }
			let moved = clients.remove(at: original)
			clients.insert(moved, at: min(index, clients.count))
			world.clientList = clients
			list.moveItem(at: original, inParent: nil, to: index, inParent: nil)
		} else {
			guard let client = item as? IRCClient, draggedItem.associatedClient === client else { return false }
			var channels = client.channelList
			guard let original = channels.firstIndex(where: { $0 === draggedItem }) else { return false }
			let moved = channels.remove(at: original)
			channels.insert(moved, at: min(index, channels.count))
			client.channelList = channels
			list.moveItem(at: original, inParent: client, to: index, inParent: client)
		}
		menuController.populateNavigationChannelList()
		return true
	}

	private func draggedItem(from info: any NSDraggingInfo) -> IRCTreeItem? {
		let pasteboard = info.draggingPasteboard
		guard pasteboard.availableType(from: [MainWindowConstants.treeItemPasteboardType]) != nil,
		      let token = pasteboard.string(forType: MainWindowConstants.treeItemPasteboardType)
		else { return nil }
		return world.findItem(withPasteboardString: token)
	}
}
