/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import os

private let serverListLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "ServerList"
)

public protocol TVCServerListDelegate: NSObjectProtocol {
	func serverListKeyDown(_ event: NSEvent)
}

public final class ServerList: NSOutlineView, AppearanceObserving {
	public weak var keyDelegate: TVCServerListDelegate?

	/** -viewDidMoveToWindow is not guaranteed to alternate between a window and
	 nil, so the bag is emptied first: moving within the same window must not
	 leave a second set of subscriptions behind. The bag holds only ours, which
	 is what a blanket -removeObserver: could not promise — it would also drop
	 the registrations AppKit keeps for the table itself. */
	private let notifications = NotificationSubscriptions()

	override public func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()

		notifications.cancelAll()

		guard let mainWindow else {
			return
		}

		notifications.observe(NSWindow.didBecomeKeyNotification, object: mainWindow) { [weak self] notification in
			self?.windowDidBecomeKey(notification)
		}
		notifications.observe(NSWindow.didResignKeyNotification, object: mainWindow) { [weak self] notification in
			self?.windowDidResignKey(notification)
		}
		notifications.observe(NSWindow.didBecomeMainNotification, object: mainWindow) { [weak self] notification in
			self?.windowMainStateChanged(notification)
		}
		notifications.observe(NSWindow.didResignMainNotification, object: mainWindow) { [weak self] notification in
			self?.windowMainStateChanged(notification)
		}
		notifications.observe(.mainWindowRedrawSubviews, object: mainWindow) { [weak self] notification in
			self?.mainWindowRequiresRedraw(notification)
		}
	}

	// MARK: - Additions / Removal

	public func addItem(toList rowIndex: UInt, inParent parent: Any?) {
		insertItems(
			at: IndexSet(integer: Int(rowIndex)),
			inParent: parent,
			withAnimation: [.effectFade, .slideRight]
		)

		if let parent {
			reloadItem(parent)
		}
	}

	public func removeItem(fromList object: Any) {
		/* Indexes come from the model rather than the view: row(forItem:),
		 parent(forItem:) and items(inContainingGroupOf:) only know about rows
		 that are currently displayed, so removing a channel from a collapsed
		 server used to bail out and leave the view out of step. */
		let parentItem: Any?
		let rowIndex: Int

		if let channel = object as? IRCChannel {
			guard let client = channel.associatedClient,
			      let index = client.channelList.firstIndex(where: { $0 === channel })
			else {
				serverListLogger.error("Object is not a child of its parent item")
				return
			}

			parentItem = client
			rowIndex = index
		} else {
			let index = (groupItems as NSArray).index(of: object)

			guard index != NSNotFound else {
				serverListLogger.error("Object does not exist on outline view")
				return
			}

			parentItem = nil
			rowIndex = index
		}

		removeItems(
			at: IndexSet(integer: rowIndex),
			inParent: parentItem,
			withAnimation: [.effectFade, .slideLeft]
		)

		if let parentItem {
			reloadItem(parentItem)
		}
	}

	// MARK: - Drawing Updates

	public func refreshAllDrawings() {
		refreshAllDrawings(false)
	}

	public func refreshAllDrawings(_ skipOcclusionCheck: Bool) {
		for rowIndex in 0 ..< numberOfRows {
			refreshDrawing(forRow: rowIndex, skipOcclusionCheck: skipOcclusionCheck)
		}
	}

	public func refreshDrawing(forRows rowIndexes: IndexSet) {
		refreshDrawing(forRows: rowIndexes, skipOcclusionCheck: false)
	}

	public func refreshDrawing(forRows rowIndexes: IndexSet, skipOcclusionCheck: Bool) {
		for index in rowIndexes {
			refreshDrawing(forRow: index, skipOcclusionCheck: skipOcclusionCheck)
		}
	}

	public func refreshDrawing(forRow rowIndex: Int) {
		refreshDrawing(forRow: rowIndex, skipOcclusionCheck: false)
	}

	public func refreshDrawing(forRow rowIndex: Int, skipOcclusionCheck: Bool) {
		guard rowIndex >= 0 else {
			return
		}

		if skipOcclusionCheck == false, mainWindow?.ceIsOccluded == true {
			return
		}

		if let rowView = view(atColumn: 0, row: rowIndex, makeIfNecessary: false) {
			rowView.needsDisplay = true
		}

		/* The row view draws the selection, whose emphasis follows the
		 window's key state. */
		rowView(atRow: rowIndex, makeIfNecessary: false)?.needsDisplay = true
	}

	public func refreshDrawing(forItem cellItem: IRCTreeItem) {
		refreshDrawing(forItem: cellItem, skipOcclusionCheck: false)
	}

	public func refreshDrawing(forItem cellItem: IRCTreeItem, skipOcclusionCheck: Bool) {
		let rowIndex = row(forItem: cellItem)
		refreshDrawing(forRow: rowIndex, skipOcclusionCheck: skipOcclusionCheck)
	}

	public func refreshMessageCount(forItem cellItem: IRCTreeItem) {
		refreshMessageCount(forItem: cellItem, skipOcclusionCheck: false)
	}

	public func refreshMessageCount(forItem cellItem: IRCTreeItem, skipOcclusionCheck: Bool) {
		let rowIndex = row(forItem: cellItem)
		refreshMessageCount(forRow: rowIndex, skipOcclusionCheck: skipOcclusionCheck)
	}

	public func refreshAllUnreadMessageCountBadges() {
		refreshAllUnreadMessageCountBadges(false)
	}

	public func refreshAllUnreadMessageCountBadges(_ skipOcclusionCheck: Bool) {
		for rowIndex in 0 ..< numberOfRows {
			refreshMessageCount(forRow: rowIndex, skipOcclusionCheck: skipOcclusionCheck)
		}
	}

	public func refreshMessageCount(forRows rowIndexes: IndexSet) {
		refreshMessageCount(forRows: rowIndexes, skipOcclusionCheck: false)
	}

	public func refreshMessageCount(forRows rowIndexes: IndexSet, skipOcclusionCheck: Bool) {
		for index in rowIndexes {
			refreshMessageCount(forRow: index, skipOcclusionCheck: skipOcclusionCheck)
		}
	}

	public func refreshMessageCount(forRow rowIndex: Int) {
		refreshMessageCount(forRow: rowIndex, skipOcclusionCheck: false)
	}

	public func refreshMessageCount(forRow rowIndex: Int, skipOcclusionCheck: Bool) {
		guard rowIndex >= 0 else {
			return
		}

		if skipOcclusionCheck == false, mainWindow?.ceIsOccluded == true {
			return
		}

		guard let rowView = view(atColumn: 0, row: rowIndex, makeIfNecessary: false) as? ServerListCell else {
			return
		}

		if rowView is ServerListCellChildItem {
			rowView.populateMessageCountBadge()
		}
	}

	override public var allowsVibrancy: Bool {
		true
	}

	public func applicationAppearanceChanged() {
		invalidateSelectionBackground()
		refreshAllDrawings(true)
		needsDisplay = true
	}

	public func systemAppearanceChanged() {
		invalidateSelectionBackground()
		refreshAllDrawings(true)
		needsDisplay = true
	}

	private func windowDidBecomeKey(_ notification: Notification) {
		windowKeyStateChanged(notification)
	}

	private func windowDidResignKey(_ notification: Notification) {
		windowKeyStateChanged(notification)
	}

	private func windowKeyStateChanged(_: Notification) {
		respondToRequiresRedraw()
	}

	private func windowMainStateChanged(_: Notification) {
		/* Row emphasis follows main-window status (see TVCServerListRowCell),
		 which AppKit does not re-evaluate on its own. */
		enumerateAvailableRowViews { rowView, _ in
			if let serverListRow = rowView as? ServerListRowCell {
				serverListRow.refreshEmphasis()
			}
		}

		respondToRequiresRedraw()
	}

	private func mainWindowRequiresRedraw(_: Notification) {
		respondToRequiresRedraw()
	}

	private func respondToRequiresRedraw() {
		refreshAllDrawings(true)
	}

	// MARK: - Events

	override public func menu(for _: NSEvent) -> NSMenu? {
		if let clickedRow = rowBeneathMouse {
			if clickedRow != selectedRow || numberOfSelectedRows > 1 {
				selectItem(at: clickedRow)
			}
		} else {
			return AppController.shared.menuController?.serverListNoSelectionMenu
		}

		return menu
	}

	public var leftMouseIsDownInView: Bool {
		/* Used by the selection delegate to tell a click driven selection
		 change apart from a programmatic one. Derived from the current
		 mouse state instead of tracking -mouseDown:/-mouseUp: which
		 could get out of sync when the up event landed elsewhere. */
		if (NSEvent.pressedMouseButtons & 0x1) == 0 {
			return false
		}

		guard let window else {
			return false
		}

		let mouseLocation = convert(window.mouseLocationOutsideOfEventStream, from: nil)
		return NSMouseInRect(mouseLocation, bounds, isFlipped)
	}

	override public func keyDown(with event: NSEvent) {
		/* With no delegate the list must still respond to the keyboard, so
		 unhandled keys go to super rather than being swallowed. */
		guard let keyDelegate else {
			super.keyDown(with: event)

			return
		}

		switch KeyCode(rawValue: event.keyCode) {
		case .downArrow, .upArrow:
			/* Let the outline view move the selection, as the member list does. */
			super.keyDown(with: event)

		case .leftArrow, .rightArrow, .pageUp, .pageDown:
			break

		default:
			keyDelegate.serverListKeyDown(event)
		}
	}
}
