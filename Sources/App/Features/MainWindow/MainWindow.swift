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
import Foundation
import SwiftUI

public extension Notification.Name {
	static let mainWindowAppearanceChanged = Notification.Name("TVCMainWindowAppearanceChangedNotification")
	static let mainWindowRedrawSubviews = Notification.Name("TVCMainWindowRedrawSubviewsNotification")
	static let mainWindowWillReloadTheme = Notification.Name("TVCMainWindowWillReloadThemeNotification")
	static let mainWindowDidReloadTheme = Notification.Name("TVCMainWindowDidReloadThemeNotification")
	/// The one declaration of the selection notification. It was declared in
	/// four places and written as a bare string in a fifth, so an observer
	/// could quietly watch a name nobody posted.
	static let mainWindowSelectionChanged = Notification.Name("TVCMainWindowSelectionChangedNotification")
}

public enum ServerListNavigationMovement: UInt {
	case all
	case active
	case unread
}

private enum ServerListNavigationSelection {
	case any
	case channel
	case server
}

struct MainWindowMouseLocation: OptionSet {
	let rawValue: UInt

	static let outsideWindow: Self = []
	static let insideWindow = Self(rawValue: 1 << 1)
	static let insideWindowTitle = Self(rawValue: 1 << 2)
	static let onTopOfWindowTitleControl = Self(rawValue: 1 << 3)
}

enum MainWindowConstants {
	static let restorableSelectionKey = "TVCMainWindowSelectedItem"
	static let legacyRestorableSelectionKey = "TVCMainWindowSelectedItems"
	static let legacyFrameKey = "NSWindow Frame -> Internal (v3) -> Main Window"
	static let systemFrameKeyPrefix = "NSWindow Frame "
	static let serverListMinimumWidth: CGFloat = 180
	static let serverListIdealWidth: CGFloat = 220
	static let serverListMaximumWidth: CGFloat = 280
	static let conversationMinimumWidth: CGFloat = 360
	static let memberListMinimumWidth: CGFloat = 160
	static let memberListIdealWidth: CGFloat = 200
	static let memberListMaximumWidth: CGFloat = 260
	static let minimumSplitViewSlack: CGFloat = 60
	static let minimumContentSize = NSSize(
		width: serverListIdealWidth + conversationMinimumWidth + memberListMinimumWidth + minimumSplitViewSlack,
		height: 500
	)
	static let minimumRestoredVisibleSize = NSSize(width: 80, height: 40)
	static let sidebarFooterHeight: CGFloat = 32
}

enum MainWindowMemberListVisibilityPolicy {
	static func isAvailable(isChannel: Bool, isLoggedIn: Bool) -> Bool {
		isChannel && isLoggedIn
	}

	static func shouldExpand(
		isChannel: Bool,
		isLoggedIn: Bool,
		isHiddenByUser: Bool
	) -> Bool {
		isAvailable(isChannel: isChannel, isLoggedIn: isLoggedIn) && isHiddenByUser == false
	}
}

@inline(__always)
func nativeChannel(_ item: IRCTreeItem?) -> IRCChannel? {
	item as? IRCChannel
}

@MainActor
@objc(TVCMainWindow)
public final class MainWindow: NSWindow, NSWindowDelegate, NSWindowRestoration, CustomKeyboardEventResponder {
	public private(set) var mainMenuProxy: MainWindowMenuProxy!
	public private(set) var formattingMenu: TextViewIRCFormattingMenu!
	private var inputContentView: MainWindowTextViewContentView!
	let presentationModel = MainWindowPresentationModel()
	private var hostingController: NSHostingController<MainWindowRootView>?

	/// The input field is built by its content view so it can use TextKit 2.
	public var inputTextField: MainWindowTextView! {
		inputContentView?.textView
	}

	public private(set) var loadingScreen: MainWindowLoadingScreen!
	public private(set) var memberList: MemberList!
	public private(set) var serverList: ServerList!
	var inputHistory: InputHistory!
	var nicknameCompletionStatus: NicknameCompletionStatus!
	/// The views the tree items are drawn into. The window owns them; the items
	/// hold only a weak back-reference the registry installs.
	private(set) lazy var logControllers = LogControllerRegistry(window: self)
	private var appearanceStorage: MainWindowAppearance?
	public var userInterfaceObjects: MainWindowAppearance {
		guard let appearanceStorage else {
			preconditionFailure("Main-window appearance requested before initialization finished")
		}
		return appearanceStorage
	}

	public internal(set) var selectedItem: IRCTreeItem?
	var previousSelectedItemId: String?
	private var lastKeyWindowStateChange: TimeInterval = 0
	private var lastKeyWindowRedrawFailedBecauseOfOcclusion = false
	private var keyEventHandler: KeyEventHandler!
	var cachedSwipeOriginPoint: NSPoint?
	public internal(set) var textSizeMultiplier = 1.0
	var isReloadingTheme = false
	private var hasConfigured = false
	private var hasInstalledFieldEditorMenu = false
	private let notifications = NotificationSubscriptions()

	public var ignoreServerListSelectionChanges = false
	public var ignoreNextServerListSelectionChange = false

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
		installUIObjects()
		inputHistory = InputHistory(window: self)
		keyEventHandler = KeyEventHandler()
		nicknameCompletionStatus = NicknameCompletionStatus(window: self)
		updateAppearance()
	}

	private func installUIObjects() {
		mainMenuProxy = MainWindowMenuProxy()
		formattingMenu = TextViewIRCFormattingMenu()
		inputContentView = MainWindowTextViewContentView(frame: .zero)
		loadingScreen = MainWindowLoadingScreen()
		memberList = MemberList()
		serverList = ServerList()
		serverList.attach(to: self)
		presentationModel.attach(to: self)
		loadingScreen.visibilityDidChange = { [weak self] visible in
			self?.inputTextField.isEditable = !visible
			self?.inputTextField.isSelectable = !visible
		}
	}

	/// Completes the programmatic window graph and starts the application.
	public func configure() {
		guard hasConfigured == false else {
			return
		}

		hasConfigured = true
		finishConfiguration()
	}

	private func finishConfiguration() {
		let controller: ApplicationController = AppController.shared
		controller.applicationWakeStepOne()

		/* Before `delegate = self`: building the input field puts controls in
		 the window, and a control joining a window asks its delegate for a field
		 editor, which is answered with the input field itself. */
		inputContentView.configure()

		delegate = self
		allowsConcurrentViewDrawing = false
		autorecalculatesKeyViewLoop = true
		isRestorable = true
		restorationClass = Self.self
		loadingScreen.configure()
		installWindowChrome()
		formattingMenu.configure()
		installFormattingMenuDecorations()
		updateAppearance()
		_ = reloadLoadingScreen()
		loadWindowState()
		SharedApplication.sharedThemeController().load()
		controller.menuController?.prepareInitialState()
		registerKeyHandlers()
		/* Both have to be listening before the stored clients are restored:
		 that restore is what publishes the tree they draw. */
		controller.installClientServices()
		controller.world.setupConfiguration()
		setupTrees()
		DockIcon.drawWithoutCount()
		observeNotifications()
		controller.applicationWakeStepTwo()
	}

	var world: IRCWorld {
		AppController.shared.world
	}

	var menuController: MenuController {
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
		/* `.fullSizeContentView` is what lets the sidebar material run the full
		 height of the window, behind the traffic lights. The titlebar stays
		 opaque on purpose: the unified toolbar draws the glass, and a
		 transparent titlebar instead leaves the toolbar's items floating over
		 the transcript with the topic header sliding under them. */
		styleMask.insert(.fullSizeContentView)
		titlebarAppearsTransparent = false
		titlebarSeparatorStyle = .automatic
		toolbarStyle = .unified
		titleVisibility = .visible
		installSwiftUIContent()
	}
}

// MARK: - Window chrome

private extension MainWindow {
	func installSwiftUIContent() {
		let rootView = MainWindowRootView(
			model: presentationModel,
			loadingScreen: loadingScreen,
			serverList: serverList,
			memberList: memberList,
			inputContentView: inputContentView
		)
		let hostingController = NSHostingController(rootView: rootView)
		hostingController.sizingOptions = []
		contentViewController = hostingController
		self.hostingController = hostingController
	}
}

// MARK: - Appearance and lifecycle

extension MainWindow {
	private func observeNotifications() {
		notifications.observe(.applicationAppearanceChanged) { [weak self] _ in
			self?.updateAppearance()
		}
		notifications.observe(.systemAppearanceChanged) { [weak self] _ in
			self?.notifySystemAppearanceChanged()
		}
		notifications.observe(.themeAppearanceChanged) { [weak self] _ in
			self?.reloadTheme()
		}
		notifications.observe(.themeWasModified) { [weak self] _ in
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
		presentationModel.appearanceRevision &+= 1
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
		repairRestoredWindowFrame()
		restoreSavedContentSplitViewState()
	}

	private func repairRestoredWindowFrame() {
		let repairedFrame = MainWindowFrameRestorationPolicy.repairedFrame(
			frame,
			minimumSize: minSize,
			minimumVisibleSize: MainWindowConstants.minimumRestoredVisibleSize,
			visibleScreenFrames: NSScreen.screens.map(\.visibleFrame)
		)
		guard repairedFrame != frame else { return }
		setFrame(repairedFrame, display: false)
		if frameAutosaveName.isEmpty == false {
			saveFrame(usingName: frameAutosaveName)
		}
	}

	private func migrateLegacyWindowFrame() {
		let defaults = UserDefaults.standard
		guard let legacyFrame = defaults.string(forKey: MainWindowConstants.legacyFrameKey) else { return }
		let autosaveName = frameAutosaveName
		let systemFrameKey = MainWindowConstants.systemFrameKeyPrefix + autosaveName
		if autosaveName.isEmpty == false, defaults.string(forKey: systemFrameKey) == nil {
			setFrame(from: legacyFrame)
			saveFrame(usingName: autosaveName)
		}
		defaults.removeObject(forKey: MainWindowConstants.legacyFrameKey)
	}

	public func prepareForApplicationTermination() {
		notifications.cancelAll()
		saveContentSplitViewState()
		saveSelection()
		memberList.assign(to: nil)
		delegate = nil
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
		coder.encode(selectedItem?.uniqueIdentifier, forKey: MainWindowConstants.restorableSelectionKey)
	}

	override public func restoreState(with coder: NSCoder) {
		super.restoreState(with: coder)
		guard let world = AppController.shared.world else { return }
		let identifier = coder.decodeObject(
			of: NSString.self,
			forKey: MainWindowConstants.restorableSelectionKey
		) as? String ?? (coder.decodeObject(
			of: [NSArray.self, NSString.self],
			forKey: MainWindowConstants.legacyRestorableSelectionKey
		) as? [String])?.last
		guard let identifier, let item = world.findItem(withId: identifier) else { return }
		select(item)
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

	public func redirectKeyDown(_ event: NSEvent) {
		inputTextField.focus()
		guard event.keyCode != KeyCode.enter.rawValue, event.keyCode != KeyCode.returnKey.rawValue else { return }
		inputTextField.keyDown(with: event)
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
		registerInput(character: "l", modifiers: [.option, .command]) { $0.focusTranscript($1) }
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

	func navigateChannelEntries(_ isMovingDown: Bool, withNavigationType navigationType: ServerListNavigationMovement) {
		if Preferences.Appearance.channelNavigationIsServerSpecific.value {
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
		var rows = serverList.items(inContainingGroupOf: selectedItem as Any) ?? []
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

	func navigateServerEntries(_ isMovingDown: Bool, withNavigationType navigationType: ServerListNavigationMovement) {
		let rows = serverList.groupItems
		navigateServerListEntries(
			rows,
			entryCount: rows.count,
			startingPoint: rows.firstIndex(where: { $0 === selectedClient }) ?? -1,
			isMovingDown: isMovingDown,
			navigationType: navigationType,
			selectionType: .server
		)
	}

	func navigateToNextEntry(_ isMovingDown: Bool) {
		navigateServerListEntries(
			nil,
			entryCount: serverList.numberOfRows,
			startingPoint: serverList.row(forItem: selectedItem),
			isMovingDown: isMovingDown,
			navigationType: .all,
			selectionType: .any
		)
	}

	func selectPreviousChannel(_: NSEvent?) {
		navigateChannelEntries(false, withNavigationType: .all)
	}

	func selectNextChannel(_: NSEvent?) {
		navigateChannelEntries(true, withNavigationType: .all)
	}

	func selectPreviousUnreadChannel(_: NSEvent?) {
		navigateChannelEntries(false, withNavigationType: .unread)
	}

	func selectNextUnreadChannel(_: NSEvent?) {
		navigateChannelEntries(true, withNavigationType: .unread)
	}

	func selectPreviousActiveChannel(_: NSEvent?) {
		navigateChannelEntries(false, withNavigationType: .active)
	}

	func selectNextActiveChannel(_: NSEvent?) {
		navigateChannelEntries(true, withNavigationType: .active)
	}

	func selectPreviousServer(_: NSEvent?) {
		navigateServerEntries(false, withNavigationType: .all)
	}

	func selectNextServer(_: NSEvent?) {
		navigateServerEntries(true, withNavigationType: .all)
	}

	func selectPreviousActiveServer(_: NSEvent?) {
		navigateServerEntries(false, withNavigationType: .active)
	}

	func selectNextActiveServer(_: NSEvent?) {
		navigateServerEntries(true, withNavigationType: .active)
	}

	func selectPreviousSelection(_: NSEvent?) {
		selectPreviousItem()
	}

	func selectNextWindow(_: NSEvent?) {
		navigateToNextEntry(true)
	}

	func selectPreviousWindow(_: NSEvent?) {
		navigateToNextEntry(false)
	}
}
