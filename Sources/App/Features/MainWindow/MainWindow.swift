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

enum MainWindowConstants {
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

/** Whether a shortcut that edits the message field belongs to this key press.

 `NSApplication` offers the window every key event before the responder chain
 sees it, so a shortcut registered on the window fires wherever the keyboard
 is: typing a filter in the toolbar's search field and pressing Tab completed a
 nickname into the chat input and moved the keyboard there with it. These
 shortcuts only apply while the input bar holds the keyboard; anywhere else the
 window declines the event and the responder chain gets it. */
enum MainWindowInputShortcutPolicy {
	/// `inputBar` is the field's container, so the field, its scroll view's
	/// clip view and any field editor inside it all count as the input bar.
	static func shouldHandle(firstResponder: NSResponder?, inputBar: NSView?) -> Bool {
		guard let inputBar, let responderView = firstResponder as? NSView else { return false }
		return responderView === inputBar || responderView.isDescendant(of: inputBar)
	}
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
	public var userInterfaceObjects: MainWindowAppearance {
		guard let appearanceStorage else {
			preconditionFailure("Main-window appearance requested before initialization finished")
		}
		return appearanceStorage
	}

	public internal(set) var selectedItem: IRCTreeItem?
	var previousSelectedItemId: String?
	private var keyEventHandler: KeyEventHandler!
	var cachedSwipeOriginPoint: NSPoint?
	public internal(set) var textSizeMultiplier = 1.0
	private var hasConfigured = false
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
		formattingMenu = TextViewIRCFormattingMenu()
		formattingMenu.attach(to: self)
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

		inputContentView.configure()

		delegate = self
		allowsConcurrentViewDrawing = false
		autorecalculatesKeyViewLoop = true
		isRestorable = true
		restorationClass = Self.self
		installWindowChrome()
		formattingMenu.configure()
		installFormattingMenuDecorations()
		installInputFieldMenu()
		updateAppearance()
		_ = reloadLoadingScreen()
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
	var world: IRCWorld? {
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

	/* The selected item is not encoded into the window's restorable state.
	 `MainWindowStateStore` already persists it -- written at termination, read
	 by `restoreSelectionDuringSetup()` once the world exists, and migrating the
	 legacy array form on the way. The coder pair was a second, weaker copy of
	 that: AppKit restores window state before the application finishes waking,
	 so `world` was usually nil and `restoreState(with:)` returned having done
	 nothing. `isRestorable` and the restoration class stay: the window frame is
	 still AppKit's to restore. */
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

	func windowDidDeminiaturize(_: Notification) {}

	func windowDidChangeScreen(_: Notification) {
		reloadMainWindowFrameOnScreenChange()
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

	func window(_: NSWindow, willUseFullScreenContentSize proposedSize: NSSize) -> NSSize {
		proposedSize
	}

	func window(
		_: NSWindow,
		willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions
	) -> NSApplication.PresentationOptions {
		proposedOptions
	}
}

// MARK: - Formatting menu

private extension MainWindow {
	/** The formatter submenu joins the input field's own context menu here,
	 once. It used to be added from `windowWillReturnFieldEditor`, which also
	 handed the input field to every control in the window as its field editor:
	 the toolbar search field then edited through the chat input, an Escape
	 there was inserted as a literal character, and the sidebar filtered on it. */
	func installInputFieldMenu() {
		let editorMenu = inputTextField.menu ?? NSMenu()
		let formatterMenu = formattingMenu.formatterMenu!
		if editorMenu.indexOfItem(withTitle: formatterMenu.title) < 0 {
			editorMenu.addItem(.separator())
			editorMenu.addItem(formatterMenu)
		}
		inputTextField.menu = editorMenu
	}

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

	/// True while the message field, or anything inside its container, holds
	/// the keyboard.
	var inputBarHoldsKeyboardFocus: Bool {
		MainWindowInputShortcutPolicy.shouldHandle(
			firstResponder: firstResponder,
			inputBar: inputContentView
		)
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

	private func registerKeyHandlers() {
		/* Escape leaves full screen from anywhere; only the fall-through into
		 the message field is the input bar's. */
		keyEventHandler.registerConditional(key: .escape) { [weak self] event in
			guard let self else { return false }
			if ceIsInFullscreenMode {
				toggleFullScreen(nil)
				return true
			}
			guard inputBarHoldsKeyboardFocus else { return false }
			inputTextField.keyDown(with: event)
			return true
		}
		registerForInputBar(key: .tab) { $0.tab($1) }
		registerForInputBar(key: .tab, modifiers: .shift) { $0.shiftTab($1) }
		register(key: .tab, modifiers: .option) { $0.selectPreviousSelection($1) }
		/* Formatting edits the message being written, so it belongs to the input
		 bar the way Tab and ⌃P/⌃N do. Registered unconditionally, ⌘B swallowed
		 the key wherever the reader was -- in the toolbar's search field, in a
		 sheet's field, in the transcript -- and gave nothing back. */
		registerForInputBar(character: "b", modifiers: .command) { $0.textFormattingBold($1) }
		registerForInputBar(character: "u", modifiers: [.control, .shift]) { $0.textFormattingUnderline($1) }
		registerForInputBar(character: "i", modifiers: [.control, .shift]) { $0.textFormattingItalic($1) }
		registerForInputBar(character: "c", modifiers: [.control, .shift]) { $0.textFormattingForegroundColor($1) }
		registerForInputBar(character: "h", modifiers: [.control, .shift]) { $0.textFormattingBackgroundColor($1) }
		register(character: ".", modifiers: .command) { $0.speakPendingNotifications($1) }
		registerForInputBar(character: "p", modifiers: .control) { $0.inputHistoryUp($1) }
		registerForInputBar(character: "n", modifiers: .control) { $0.inputHistoryDown($1) }

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
