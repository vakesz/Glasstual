// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import SwiftUI

extension Notification.Name {
	static let mainWindowAppearanceChanged = Notification.Name("Glasstual.mainWindowAppearanceChanged")
	/// The one declaration of the selection notification; an observer that
	/// spells the name itself is watching a name nobody posts.
	static let mainWindowSelectionChanged = Notification.Name("Glasstual.mainWindowSelectionChanged")
}

/** The application's one window.

 The explicit Objective-C name is what AppKit writes into the saved application
 state for the restoration class, so it has to be stable across a launch, not
 across a release: changing it costs the full-screen state and the Space the
 window was on once. The frame is not part of that blob — it is stored under the
 `setFrameAutosaveName` key and survives. */
@MainActor
@objc(GlasstualMainWindow)
final class MainWindow: NSWindow, NSWindowDelegate, NSWindowRestoration, CustomKeyboardEventResponder {
	private(set) var formattingMenu: TextFormattingMenu!
	private(set) var inputContentView: InputFieldContentView!
	let columnModel = MainWindowColumnModel()
	let sheetModel = MainWindowSheetModel()
	let chrome = MainWindowChrome()
	private var hostingController: NSHostingController<MainWindowRootView>?

	/// The input field is built by its content view so it can use TextKit 2.
	var inputTextField: InputField! {
		inputContentView?.textView
	}

	private(set) var loadingScreen: MainWindowLoadingScreen!
	private(set) var memberList: MemberList!
	private(set) var sidebar: Sidebar!
	var inputHistory: InputHistory!
	var nicknameCompletionStatus: NicknameCompletion!
	/// The views the sidebar items are drawn into. The window owns them; the items
	/// hold only a weak back-reference the registry installs.
	private(set) lazy var transcriptControllers = TranscriptControllerRegistry(window: self)
	/// The application-wide snapshot ``appearanceStorage`` was built from.
	private var appearanceSnapshot: ResolvedAppearance?
	var selectedItem: ChatItem?
	var previousSelectedItemId: String?
	let keyEventHandler = KeyEventHandler()
	/** The transcript zoom the View menu last left.

	 Stored beside the column widths rather than held for the session only: the
	 zoom is a reading setting, and it used to be back at 100% on the next
	 launch. Every new transcript view reads it as it loads. */
	var textSizeMultiplier = 1.0 {
		didSet {
			guard textSizeMultiplier != oldValue else { return }
			stateStore.saveTextSizeMultiplier(textSizeMultiplier)
		}
	}

	/// The window's own handle on the state it restores from. One handle: a
	/// store built per call builds a defaults-suite handle with it, and the
	/// zoom above writes on every step of the View menu's Increase Font Size.
	let stateStore = MainWindowStateDefaults()

	private var hasConfigured = false
	private let notifications = NotificationSubscriptions()

	var ignoreSidebarSelectionChanges = false

	override init(
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
		nicknameCompletionStatus = NicknameCompletion(window: self)
		updateAppearance()
	}

	private func installUIObjects() {
		formattingMenu = TextFormattingMenu()
		formattingMenu.attach(to: self)
		inputContentView = InputFieldContentView(frame: .zero)
		loadingScreen = MainWindowLoadingScreen()
		memberList = MemberList()
		sidebar = Sidebar()
		sidebar.attach(to: self)
		columnModel.attach(to: self)
	}

	/// Completes the programmatic window graph and starts the application.
	func configure() {
		guard hasConfigured == false else {
			return
		}

		hasConfigured = true
		finishConfiguration()
	}

	private func finishConfiguration() {
		let controller: ApplicationDelegate = AppServices.delegate
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
		AppServices.theme.reload()
		controller.menuController?.prepareInitialState()
		registerKeyHandlers()
		/* Both have to be listening before the stored sessions are restored:
		 that restore is what publishes the rows they draw. */
		controller.installSessionServices()
		controller.chatSession.setupConfiguration()
		setupSidebar()
		DockIcon.drawWithoutCount()
		observeNotifications()
		controller.applicationWakeStepTwo()
	}

	/// The connections the window draws. It is `nil` until the application
	/// finishes waking, which window restoration can precede.
	var chatSession: ChatSession? {
		AppServices.chatSession
	}

	var menuController: MenuActionController {
		guard let menuController = AppServices.delegate.menuController else {
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
			columns: columnModel,
			sheets: sheetModel,
			chrome: chrome,
			loadingScreen: loadingScreen,
			sidebar: sidebar,
			memberList: memberList,
			inputContentView: inputContentView,
			commands: AppServices.delegate.menuController
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
		notifications.observe(.themeAppearanceChanged) { [weak self] _ in
			self?.reloadTheme()
		}
		notifications.observe(.themeWasModified) { [weak self] _ in
			self?.reloadTheme()
		}
		/* Synchronously, so that a settings sheet's write and the redraw it asks
		 for happen in the same turn. */
		notifications.observeSynchronously(SettingsReloadRequest.self) { [weak self] request in
			self?.settingsChanged(request.action)
		}
	}

	/** Adopts a new application appearance, when there is a new one to adopt.

	 This runs for every appearance notification and every screen change, and
	 it bumps `appearanceRevision`, which rebuilds the whole transcript
	 representable. The application's appearance snapshot is a value, so
	 comparing it answers whether there is anything to rebuild. */
	private func updateAppearance() {
		let properties = AppServices.appearance.properties
		guard appearanceSnapshot != properties else { return }
		appearanceSnapshot = properties
		appearance = properties.appKitAppearance
		notifyMainWindowAppearanceChanged()
	}

	private func notifyMainWindowAppearanceChanged() {
		columnModel.appearanceRevision &+= 1
		NotificationCenter.default.post(name: .mainWindowAppearanceChanged, object: self)
	}

	private func loadWindowState() {
		repairRestoredWindowFrame()
		restoreSavedContentSplitViewState()
		textSizeMultiplier = stateStore.loadTextSizeMultiplier()
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

	func prepareForApplicationTermination() {
		notifications.cancelAll()
		saveContentSplitViewState()
		saveSelection()
		memberList.assign(to: nil)
		delegate = nil
		selectedItem = nil
		/* The window stays open. AppKit records a window closed at quit as
		 closed, and the next launch then has nothing to restore. */
	}

	static func restoreWindow(
		withIdentifier _: NSUserInterfaceItemIdentifier,
		state _: NSCoder,
		completionHandler: @escaping (NSWindow?, (any Error)?) -> Void
	) {
		completionHandler(AppServices.delegate.mainWindow, nil)
	}

	/* The selected item is not encoded into the window's restorable state.
	 `MainWindowStateDefaults` already persists it -- written at termination, read
	 by `restoreSelectionDuringSetup()` once the chat session exists. AppKit
	 restores the window itself, meaning
	 its frame, whether it was in full screen, and the Space it was on. That
	 happens between `applicationWillFinishLaunching` and
	 `applicationDidFinishLaunching`, so the application builds this window in
	 the first of the two. Built any later, the window did not exist when the
	 restoration class was asked for it, and nothing was restored. */
}

// MARK: - Settings reload

/** What a setting change makes the main window redo.

 The window builds and holds the two sidebars, the input field and its history,
 so it answers the obligations about them itself. Nothing in the settings
 layer knows they exist; it announces what changed and this is the owner that
 reads the announcement.

 Every step is idempotent and derives its result from the store rather than from
 the change, so an obligation that arrives twice costs a redraw and nothing
 else. */
extension MainWindow {
	func settingsChanged(_ action: SettingsReloadAction) {
		/* Also on the coarse change: the badge counts what the connections hold,
		 and the connections drop the public-message half of them when that
		 setting goes off. */
		if action.isDisjoint(with: [.dockIconBadges, .settingsChanged]) == false {
			reloadDockIconBadge()
		}

		if action.isDisjoint(with: [.memberList, .memberListUserBadges]) == false {
			memberList?.invalidatePresentation()
		}

		if action.contains(.sidebar) {
			/* A changed session list is a different list: the rows are rebuilt at
			 once rather than coalesced with the next inbound burst. */
			sidebar?.applicationAppearanceChanged()
		} else if action.contains(.sidebarUnreadBadges) {
			sidebar?.setNeedsRefresh()
		}

		if action.contains(.textDirection) {
			inputTextField?.updateTextDirection()
		}

		if action.contains(.textFieldFontSize) {
			inputTextField?.updateTextBasedOnPreferredFontSize()
		}

		if action.contains(.inputHistoryScope) {
			inputHistory?.noteInputHistoryObjectScopeDidChange()
		}

		/* Both change how a line is laid out. The theme controller has already
		 republished its snapshot by the time this runs, so the transcripts are
		 asked once, here, rather than once per owner. */
		if action.isDisjoint(with: [.style, .textDirection]) == false {
			reloadTheme()
		}
	}

	/// The badge is drawn for the screen the window is on, which is why the dock
	/// tile is the window's to redraw and not the notification layer's.
	private func reloadDockIconBadge() {
		if SettingsKeys.Notifications.displayDockBadge.value {
			DockIcon.resetCachedCount()
			DockIcon.updateDockIcon()
		} else {
			DockIcon.drawWithoutCount()
		}
	}
}

// MARK: - Window delegate

extension MainWindow {
	/// The dock tile is drawn for the screen the window is on, so a move
	/// between displays redraws it. Nothing else about the window changes.
	private func redrawDockIconForScreenChange() {
		guard AppServices.delegate.applicationIsTerminating == false else { return }
		DockIcon.resetCachedCount()
		DockIcon.updateDockIcon()
	}

	private func resetSelectedItemState() {
		guard AppServices.delegate.applicationIsTerminating == false else { return }
		if let selectedItem {
			selectedItem.resetState()
			noteItemWasViewed(selectedItem)
		}
		DockIcon.updateDockIcon()
	}

	func noteItemWasViewed(_ item: ChatItem) {
		guard isKeyWindow, let conversation = item.associatedConversation else { return }
		conversation.associatedSession?.markConversation(asRead: conversation)
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
		styleMask.contains(.fullScreen) == false
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

// MARK: - Restored frame

enum MainWindowFrameRestorationPolicy {
	static func repairedFrame(
		_ frame: CGRect,
		minimumSize: CGSize,
		minimumVisibleSize: CGSize,
		visibleScreenFrames: [CGRect]
	) -> CGRect {
		let frameIsFinite = [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
		var candidate = frameIsFinite ? frame.standardized : CGRect(origin: .zero, size: minimumSize)
		let intersections = visibleScreenFrames.map { screenFrame in
			(screenFrame, intersectionArea(of: candidate, with: screenFrame))
		}
		let bestScreenOverlap = intersections.max { $0.1 < $1.1 }
		let visibleIntersection = bestScreenOverlap?.0.intersection(candidate) ?? .null
		let hasUsableVisibleArea = visibleIntersection.isNull == false
			&& visibleIntersection.width >= min(minimumVisibleSize.width, candidate.width)
			&& visibleIntersection.height >= min(minimumVisibleSize.height, candidate.height)
		let isUndersized = candidate.width < minimumSize.width || candidate.height < minimumSize.height

		guard frameIsFinite == false || isUndersized || hasUsableVisibleArea == false else {
			return frame
		}

		candidate.size.width = max(candidate.width, minimumSize.width)
		candidate.size.height = max(candidate.height, minimumSize.height)
		let targetScreen = if let bestScreenOverlap, bestScreenOverlap.1 > 0 {
			bestScreenOverlap.0
		} else {
			visibleScreenFrames.first
		}
		guard let targetScreen else {
			return candidate
		}

		candidate.size.width = min(candidate.width, targetScreen.width)
		candidate.size.height = min(candidate.height, targetScreen.height)

		if bestScreenOverlap?.1 ?? 0 > 0 {
			candidate.origin.x = min(max(candidate.minX, targetScreen.minX), targetScreen.maxX - candidate.width)
			candidate.origin.y = min(max(candidate.minY, targetScreen.minY), targetScreen.maxY - candidate.height)
		} else {
			candidate.origin.x = targetScreen.midX - candidate.width / 2
			candidate.origin.y = targetScreen.midY - candidate.height / 2
		}

		return candidate
	}

	private static func intersectionArea(of frame: CGRect, with screenFrame: CGRect) -> CGFloat {
		let intersection = frame.intersection(screenFrame)
		return intersection.isNull ? 0 : intersection.width * intersection.height
	}
}
