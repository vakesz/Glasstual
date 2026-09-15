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
	/// The one declaration of the selection notification; an observer that
	/// spells the name itself is watching a name nobody posts.
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

nonisolated enum MainWindowConstants { // nonisolated: value
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

	/// The footer icons' hit target: the smallest square that still reads as a
	/// control at the sidebar's foot.
	static let footerIconSize: CGFloat = 22
	/// The draggable width of the edge between conversation and member list.
	static let memberListHandleWidth: CGFloat = 7
	/// One press of an arrow key on the focused resize handle.
	static let memberListKeyboardResizeStep: CGFloat = 16
	/// The stroke the input capsule draws while it holds the keyboard.
	static let focusRingWidth: CGFloat = 2
	/// The same stroke where the system asks for increased contrast.
	static let focusRingWidthIncreasedContrast: CGFloat = 3
}

@MainActor
@objc(TVCMainWindow)
public final class MainWindow: NSWindow, NSWindowDelegate, NSWindowRestoration, CustomKeyboardEventResponder {
	public private(set) var formattingMenu: TextViewIRCFormattingMenu!
	private(set) var inputContentView: MainWindowTextViewContentView!
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
	/// The application-wide snapshot ``appearanceStorage`` was built from.
	private var appearanceSnapshot: AppearancePropertyCollection?
	public var userInterfaceObjects: MainWindowAppearance {
		guard let appearanceStorage else {
			preconditionFailure("Main-window appearance requested before initialization finished")
		}
		return appearanceStorage
	}

	public internal(set) var selectedItem: TreeItem?
	var previousSelectedItemId: String?
	private var keyEventHandler: KeyEventHandler!
	/** The transcript zoom the View menu last left.

	 Stored beside the column widths rather than held for the session only: the
	 zoom is a reading preference, and it used to be back at 100% on the next
	 launch. Every new transcript view reads it as it loads. */
	public internal(set) var textSizeMultiplier = 1.0 {
		didSet {
			guard textSizeMultiplier != oldValue else { return }
			MainWindowStateStore().saveTextSizeMultiplier(textSizeMultiplier)
		}
	}

	private var hasConfigured = false
	private let notifications = NotificationSubscriptions()

	public var ignoreServerListSelectionChanges = false

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
		/* A constant, so it is set once here rather than restated by every
		 title update -- which used to mean on every selection change and every
		 connection-state change. */
		setAccessibilityIdentifier("main-window")
		installUIObjects()
		inputHistory = InputHistory(window: self)
		keyEventHandler = KeyEventHandler()
		nicknameCompletionStatus = NicknameCompletionStatus(window: self)
		updateAppearance()
	}

	private func installUIObjects() {
		formattingMenu = TextViewIRCFormattingMenu()
		formattingMenu.attach(to: self)
		inputContentView = MainWindowTextViewContentView(frame: .zero)
		loadingScreen = MainWindowLoadingScreen()
		memberList = MemberList()
		serverList = ServerList()
		serverList.attach(to: self)
		presentationModel.attach(to: self)
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

		inputContentView.configure()

		delegate = self
		allowsConcurrentViewDrawing = false
		autorecalculatesKeyViewLoop = true
		isRestorable = true
		restorationClass = Self.self
		installWindowChrome()
		installInputFieldMenu()
		updateAppearance()
		reloadLoadingScreen()
		loadWindowState()
		SharedApplication.sharedThemeController().reload()
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

	/// The world the window draws. It is `nil` until the application finishes
	/// waking, which window restoration can precede.
	var world: World? {
		AppController.shared.world
	}

	var menuController: MenuController {
		guard let menuController = AppController.shared.menuController else {
			preconditionFailure("Menu controller is unavailable while the main window is loading")
		}
		return menuController
	}

	private func installWindowChrome() {
		/* `.fullSizeContentView` is what lets the sidebar material run the full
		 height of the window, behind the traffic lights, and the transparent
		 titlebar is what lets the transcript and the member list run up under
		 the toolbar the way Mail's and Notes' content does. What keeps the
		 toolbar legible over them is the scroll edge effect the columns declare
		 in SwiftUI, not an opaque bar: an opaque titlebar draws a hard seam
		 across the window and forces every column to be inset below it by hand
		 instead. `.none` for the separator for the same reason -- the edge
		 effect is the separation. */
		styleMask.insert(.fullSizeContentView)
		titlebarAppearsTransparent = true
		titlebarSeparatorStyle = .none
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

	/** Rebuilds the window's appearance objects, when there is a new appearance
	 to build them from.

	 Each one decodes a property list, and this used to run for every
	 appearance notification and every screen change: dragging the window
	 between displays reparsed two files and bumped `appearanceRevision`, which
	 rebuilds the whole transcript representable. The snapshot the objects are
	 built from is a value, so comparing it answers whether there is anything
	 to rebuild. */
	private func updateAppearance() {
		let properties = ApplicationAppearance.currentApplicationProperties
		guard appearanceStorage == nil || appearanceSnapshot != properties else { return }
		guard let appearance = MainWindowAppearance() else { return }
		appearanceSnapshot = properties
		appearanceStorage = appearance
		self.appearance = appearance.appKitAppearance
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
		textSizeMultiplier = MainWindowStateStore().loadTextSizeMultiplier()
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
		/* The window stays open. AppKit records a window closed at quit as
		 closed, and the next launch then has nothing to restore. */
	}

	public static func restoreWindow(
		withIdentifier _: NSUserInterfaceItemIdentifier,
		state _: NSCoder,
		completionHandler: @escaping (NSWindow?, (any Error)?) -> Void
	) {
		completionHandler(AppController.shared.mainWindow, nil)
	}

	/* The selected item is not encoded into the window's restorable state.
	 `MainWindowStateStore` already persists it -- written at termination, read
	 by `restoreSelectionDuringSetup()` once the world exists, and migrating the
	 legacy array form on the way. AppKit restores the window itself, meaning
	 its frame, whether it was in full screen, and the Space it was on. That
	 happens between `applicationWillFinishLaunching` and
	 `applicationDidFinishLaunching`, so the application builds this window in
	 the first of the two. Built any later, the window did not exist when the
	 restoration class was asked for it, and nothing was restored. */
}

// MARK: - Window delegate

public extension MainWindow {
	/// The dock tile is drawn for the screen the window is on, so a move
	/// between displays redraws it. Nothing else about the window changes.
	private func redrawDockIconForScreenChange() {
		guard AppController.shared.applicationIsTerminating == false else { return }
		DockIcon.resetCachedCount()
		DockIcon.updateDockIcon()
	}

	private func resetSelectedItemState() {
		guard AppController.shared.applicationIsTerminating == false else { return }
		if let selectedItem {
			selectedItem.resetState()
			noteItemWasViewed(selectedItem)
		}
		DockIcon.updateDockIcon()
	}

	func noteItemWasViewed(_ item: TreeItem) {
		guard isKeyWindow, let channel = item.associatedChannel else { return }
		channel.associatedClient.markChannel(asRead: channel)
	}

	func windowDidChangeScreen(_: Notification) {
		redrawDockIconForScreenChange()
	}

	func windowDidBecomeKey(_: Notification) {
		resetSelectedItemState()
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
}

// MARK: - Formatting menu

private extension MainWindow {
	/** The formatter submenu joins the input field's own context menu here,
	 once, and not from `windowWillReturnFieldEditor`: answering that hands the
	 input field to every control in the window as its field editor, and the
	 toolbar's search field then edits through the chat input. */
	func installInputFieldMenu() {
		let editorMenu = inputTextField.menu ?? NSMenu()
		let formatterMenu = formattingMenu.formatterMenu!
		if editorMenu.indexOfItem(withTitle: formatterMenu.title) < 0 {
			editorMenu.addItem(.separator())
			editorMenu.addItem(formatterMenu)
		}
		inputTextField.menu = editorMenu
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

	/** Whether the message field, or anything inside its container, holds the
	 keyboard.

	 `NSApplication` offers the window every key event before the responder
	 chain sees it, so a shortcut registered on the window otherwise fires
	 wherever the keyboard is: typing a filter in the toolbar's search field and
	 pressing Tab completed a nickname into the chat input and moved the
	 keyboard there with it. The container is what is asked about, so the field,
	 its scroll view's clip view and any field editor inside it all count. */
	var inputBarHoldsKeyboardFocus: Bool {
		guard let inputContentView, let responder = firstResponder as? NSView else { return false }
		return responder === inputContentView || responder.isDescendant(of: inputContentView)
	}

	/// A window-level shortcut that only applies to the message field. It is
	/// declined -- and so left to whatever view has the keyboard -- otherwise.
	private func registerForInputBar(
		key: KeyCode,
		modifiers: NSEvent.ModifierFlags = [],
		perform action: @escaping (MainWindow, NSEvent) -> Void
	) {
		keyEventHandler.registerConditional(key: key, modifiers: modifiers) { [weak self] event in
			guard let self, inputBarHoldsKeyboardFocus else { return false }
			action(self, event)
			return true
		}
	}

	/// The character form of `registerForInputBar(key:modifiers:perform:)`.
	private func registerForInputBar(
		character: Character,
		modifiers: NSEvent.ModifierFlags,
		perform action: @escaping (MainWindow, NSEvent) -> Void
	) {
		keyEventHandler.registerConditional(character: character, modifiers: modifiers) { [weak self] event in
			guard let self, inputBarHoldsKeyboardFocus else { return false }
			action(self, event)
			return true
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

	func registerKeyHandlers() {
		/* In the message field, Escape dismisses a spelling suggestion, cancels
		 a reply and closes the completion popup. Anywhere else the window
		 leaves Escape to whatever holds the keyboard. It used to leave full
		 screen instead, so the toolbar's search field and the find bar never
		 got the Escape that clears or closes them. The green button and
		 Control-Command-F leave full screen. */
		registerForInputBar(key: .escape) { $0.inputTextField.keyDown(with: $1) }
		/* Declined, not swallowed, when the preference says Tab does nothing:
		 the field then hands Tab to keyboard navigation instead of holding the
		 keyboard in place. */
		keyEventHandler.registerConditional(key: .tab) { [weak self] event in
			guard let self, inputBarHoldsKeyboardFocus else { return false }
			return tab(event)
		}
		keyEventHandler.registerConditional(key: .tab, modifiers: .shift) { [weak self] event in
			guard let self, inputBarHoldsKeyboardFocus else { return false }
			return shiftTab(event)
		}
		register(key: .tab, modifiers: .option) { $0.selectPreviousSelection($1) }
		/* The two colour commands pop a menu up at the caret, which no menu item
		 can do, so they stay registrations. Bold, italics and underline are
		 Format menu items with key equivalents of their own; registering them
		 here as well gave the window a second, unvalidated copy of each.
		 Registered unconditionally, ⌘B also swallowed the key wherever the
		 reader was -- in the toolbar's search field, in a sheet's field, in the
		 transcript -- and gave nothing back, which is why what is left is
		 scoped to the input bar. */
		registerForInputBar(character: "c", modifiers: [.control, .shift]) { $0.textFormattingForegroundColor($1) }
		registerForInputBar(character: "h", modifiers: [.control, .shift]) { $0.textFormattingBackgroundColor($1) }
		registerForInputBar(character: "p", modifiers: .control) { $0.inputHistoryUp($1) }
		registerForInputBar(character: "n", modifiers: .control) { $0.inputHistoryDown($1) }

		registerInput(key: .enter, modifiers: .control) { $0.sendControlEnterMessageMaybe($1) }
		registerInput(key: .returnKey, modifiers: .command) { $0.sendMessageAsAction($1) }
		registerInput(key: .enter, modifiers: .command) { $0.sendMessageAsAction($1) }
		/* Control+Command+T, beside Control+Command+S for the server list:
		 Option+Command+L is the Window menu's File Transfers, and
		 Option+Command+T is the system's Show/Hide Toolbar. */
		registerInput(character: "t", modifiers: [.control, .command]) { $0.focusTranscript($1) }
		registerInput(key: .upArrow) { $0.inputHistoryUpWithScrollCheck($1) }
		registerInput(key: .upArrow, modifiers: .option) { $0.inputHistoryUpWithScrollCheck($1) }
		registerInput(key: .downArrow) { $0.inputHistoryDownWithScrollCheck($1) }
		registerInput(key: .downArrow, modifiers: .option) { $0.inputHistoryDownWithScrollCheck($1) }
	}
}

// MARK: - Navigation

public extension MainWindow {
	/** Moves the selection to the next row that qualifies.

	 `rows` is rotated so the walk starts one past the current selection and
	 comes back round to it, and the first row that is both of the right kind
	 and in the right state wins. A selection that is not in `rows` -- nothing
	 selected, or a row the filter has taken out of the list -- has nowhere to
	 walk from, so nothing moves. */
	private func navigate(
		_ rows: [TreeItem],
		from startingPoint: Int,
		isMovingDown: Bool,
		navigationType: ServerListNavigationMovement,
		selectionType: ServerListNavigationSelection
	) {
		guard rows.indices.contains(startingPoint) else { return }
		let count = rows.count
		let rotated = (1 ..< count).lazy.map { offset -> TreeItem in
			let position = isMovingDown ? startingPoint + offset : startingPoint - offset + count
			return rows[position % count]
		}
		guard let destination = rotated.first(where: {
			Self.item($0, is: selectionType) && Self.item($0, matches: navigationType)
		}) else { return }
		select(destination)
	}

	private static func item(_ item: TreeItem, is selectionType: ServerListNavigationSelection) -> Bool {
		switch selectionType {
		case .any:
			true
		case .channel:
			item.isChannel || item.isPrivateMessage || item.associatedChannel?.isDirectChat == true
		case .server:
			item.isClient
		}
	}

	private static func item(_ item: TreeItem, matches navigationType: ServerListNavigationMovement) -> Bool {
		switch navigationType {
		case .all:
			true
		case .active:
			item.isActive
		case .unread:
			item.isUnread
		}
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
		let rows = serverList.selectableItems
		navigate(
			rows,
			from: serverList.row(forItem: selectedItem),
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
		navigate(
			rows,
			from: rows.firstIndex { $0 === selectedItem } ?? -1,
			isMovingDown: isMovingDown,
			navigationType: navigationType,
			selectionType: .channel
		)
	}

	func navigateServerEntries(_ isMovingDown: Bool, withNavigationType navigationType: ServerListNavigationMovement) {
		let rows = serverList.groupItems
		navigate(
			rows,
			from: rows.firstIndex { $0 === selectedClient } ?? -1,
			isMovingDown: isMovingDown,
			navigationType: navigationType,
			selectionType: .server
		)
	}

	func navigateToNextEntry(_ isMovingDown: Bool) {
		let rows = serverList.selectableItems
		navigate(
			rows,
			from: serverList.row(forItem: selectedItem),
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
