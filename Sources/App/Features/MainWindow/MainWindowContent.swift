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
import GlasstualPluginKit

// MARK: - View controls and input

extension MainWindow {
	public func changeTextSize(_ bigger: Bool) {
		let next = bigger ? textSizeMultiplier * 1.2 : textSizeMultiplier / 1.2
		guard (0.5 ... 3).contains(next) else { return }
		textSizeMultiplier = next
		for client in world.clientList {
			client.logController?.changeTextSize(bigger)
			for channel in client.channelList {
				channel.logController?.changeTextSize(bigger)
			}
		}
	}

	public func markAllAsRead() {
		markAllAsRead(inGroup: nil)
	}

	public func markAllAsRead(inGroup item: IRCTreeItem?) {
		let markScrollback = Preferences.Messages.autoAddScrollbackMark.value
		for client in world.clientList {
			if markScrollback {
				client.logController?.mark()
			}
			for channel in client.channelList {
				if markScrollback {
					channel.logController?.mark()
				}
				channel.resetState()
			}
		}
		DockIcon.updateDockIcon()
		if let item {
			reloadTreeGroup(item)
		} else {
			reloadTree()
		}
	}

	public func reloadTheme() {
		guard isReloadingTheme == false else { return }
		isReloadingTheme = true
		NotificationCenter.default.post(name: .mainWindowWillReloadTheme, object: self)
		performThemeReload()
	}

	private func performThemeReload() {
		for client in world.clientList {
			client.logController?.reloadTheme()
			for channel in client.channelList {
				channel.logController?.reloadTheme()
			}
		}
		isReloadingTheme = false
		NotificationCenter.default.post(name: .mainWindowDidReloadTheme, object: self)
	}

	public func clearContents(of client: IRCClient) {
		client.resetState()
		client.logController?.clear()
		reloadTreeItem(client)
	}

	public func clearContents(of channel: IRCChannel) {
		channel.resetState()
		channel.logController?.clear()
		reloadTreeItem(channel)
	}

	public func clearAllViews() {
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

	func tab(_: NSEvent) {
		switch Preferences.Input.tabKeyAction.value {
		case .nicknameComplete: completeNickname(true)
		case .unreadChannel: navigateChannelEntries(true, withNavigationType: .unread)
		default: break
		}
	}

	func shiftTab(_: NSEvent) {
		switch Preferences.Input.tabKeyAction.value {
		case .nicknameComplete: completeNickname(false)
		case .unreadChannel: navigateChannelEntries(false, withNavigationType: .unread)
		default: break
		}
	}

	func sendControlEnterMessageMaybe(_ event: NSEvent) {
		if Preferences.Input.controlEnterSendsMessage.value {
			textEntered()
		} else {
			inputTextField.keyDownToSuper(event)
		}
	}

	func sendMessageAsAction(_: NSEvent) {
		if Preferences.Input.commandReturnSendsAction.value {
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
				if (atTop && event.keyCode == KeyCode.downArrow.rawValue) ||
					(atBottom && event.keyCode == KeyCode.upArrow.rawValue) ||
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

	func inputHistoryUp(_ event: NSEvent) {
		moveInputHistory(true, checkScroller: false, event: event)
	}

	func inputHistoryDown(_ event: NSEvent) {
		moveInputHistory(false, checkScroller: false, event: event)
	}

	func inputHistoryUpWithScrollCheck(_ event: NSEvent) {
		moveInputHistory(
			true,
			checkScroller: true,
			event: event
		)
	}

	func inputHistoryDownWithScrollCheck(_ event: NSEvent) {
		moveInputHistory(
			false,
			checkScroller: true,
			event: event
		)
	}

	func textFormattingBold(_: NSEvent) {
		if formattingMenu.textIsBold {
			formattingMenu.removeBoldCharFromTextBox(nil)
		} else {
			formattingMenu.insertBoldCharIntoTextBox(nil)
		}
	}

	func textFormattingItalic(_: NSEvent) {
		if formattingMenu.textIsItalicized {
			formattingMenu.removeItalicCharFromTextBox(nil)
		} else {
			formattingMenu.insertItalicCharIntoTextBox(nil)
		}
	}

	func textFormattingUnderline(_: NSEvent) {
		if formattingMenu.textIsUnderlined {
			formattingMenu.removeUnderlineCharFromTextBox(nil)
		} else {
			formattingMenu.insertUnderlineCharIntoTextBox(nil)
		}
	}

	func textFormattingForegroundColor(_: NSEvent) {
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

	func textFormattingBackgroundColor(_: NSEvent) {
		guard formattingMenu.textHasSpoiler == false, formattingMenu.textHasForegroundColor else { return }
		if formattingMenu.textHasBackgroundColor {
			formattingMenu.removeBackgroundColorCharFromTextBox(nil)
			return
		}
		var point = inputTextField.frame.origin
		point.y -= 200
		point.x += 100
		let menu: NSMenu = formattingMenu.backgroundColorMenu
		menu.popUp(positioning: nil, at: point, in: inputTextField)
	}

	func exitFullscreenMode(_ event: NSEvent) {
		if ceIsInFullscreenMode {
			toggleFullScreen(nil)
		} else {
			inputTextField.keyDown(with: event)
		}
	}

	func speakPendingNotifications(_: NSEvent) {
		SharedApplication.sharedSpeechSynthesizer().stopSpeakingAndMoveForward()
	}

	func focusTranscript(_: NSEvent) {
		guard attachedSheet == nil, let view = selectedViewController?.backingView?.view else { return }
		makeFirstResponder(view)
	}

	public func textEntered() {
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
		guard Preferences.Input.swipeMinimumLength.value >= 1 else { return }
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
		let minimum = Preferences.Input.swipeMinimumLength.value
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

	func locationOfMouseInWindow() -> UInt {
		locationOfMouseValue(NSEvent.mouseLocation).rawValue
	}

	func locationOfMouse(_ location: NSPoint) -> UInt {
		locationOfMouseValue(location).rawValue
	}

	private func locationOfMouseValue(_ location: NSPoint) -> MainWindowMouseLocation {
		guard frame.contains(location) else { return .outsideWindow }
		let titleFrame = ceTitlebarFrame
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

	func preferencesChanged() {
		if Preferences.Notifications.displayDockBadge.value {
			DockIcon.resetCachedCount(); DockIcon.updateDockIcon()
		} else {
			DockIcon.drawWithoutCount()
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

// MARK: - Selection and transcript view

public extension MainWindow {
	var previouslySelectedItem: IRCTreeItem? {
		guard let previousSelectedItemId else { return nil }
		return world.findItem(withId: previousSelectedItemId)
	}

	var selectedClient: IRCClient? {
		selectedItem?.associatedClient
	}

	var selectedChannel: IRCChannel? {
		guard let selectedItem, selectedItem.isClient == false else { return nil }
		return nativeChannel(selectedItem)
	}

	var selectedViewController: LogController? {
		if let controller = selectedChannel?.logController {
			return controller
		}
		return selectedClient?.logController
	}

	func isItemVisible(_ item: IRCTreeItem) -> Bool {
		isItemSelected(item)
	}

	func isItemSelected(_ item: IRCTreeItem?) -> Bool {
		item != nil && selectedItem === item
	}

	private func selectionDidChange() {
		let newItem = serverList.selectedRow >= 0
			? serverList.item(atRow: serverList.selectedRow) as? IRCTreeItem
			: nil
		guard selectedItem !== newItem else { return }
		storePreviousSelection()
		let previousItem = selectedItem
		selectedItem = newItem
		channelView.show(newItem?.logController?.ensureBackingView())
		previousItem?.logController?.notifyDidBecomeHidden()
		newItem?.logController?.notifyDidBecomeVisible()
		selectionDidChangePostflight()
	}

	private func selectionDidChangePostflight() {
		invalidateRestorableState()
		let changedTo = selectedItem
		let changedFrom = previouslySelectedItem
		guard changedTo !== changedFrom else { return }
		changedFrom?.resetState()
		if let changedTo {
			changedTo.resetState()
			noteItemWasViewed(changedTo)
		}
		if let changedFrom {
			changedFrom.logController?.notifySelectionChanged()
		}

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

		memberList.assign(to: changedTo.isChannel ? nativeChannel(changedTo) : nil)
		if Preferences.Input.focusTextViewOnSelectionChange.value,
		   Accessibility.isVoiceOverEnabled == false
		{
			inputTextField.focus()
		}
		inputHistory.moveFocus(to: changedTo)
		inputTextField.resetSpellingIgnores()
		updateMemberListVisibilityForSelection()
		changedTo.logController?.notifySelectionChanged()
		storeLastSelectedChannel()
		NotificationCenter.default.post(name: .mainWindowSelectionChanged, object: self)
		DockIcon.updateDockIcon()
		updateTitle()
	}

	func saveContentSplitViewState() {
		MainWindowStateStore().saveLayout(
			MainWindowLayoutState(
				isServerListVisible: isServerListVisible,
				isMemberListVisible: memberList.isHiddenByUser == false
			)
		)
	}

	func restoreSavedContentSplitViewState() {
		let state = MainWindowStateStore().loadLayout()
		memberList.isHiddenByUser = !state.isMemberListVisible
		memberListSplitItem.isCollapsed = !state.isMemberListVisible
		serverListSplitItem.isCollapsed = !state.isServerListVisible
	}

	func expandServerList() {
		serverListSplitItem.animator().isCollapsed = false
	}

	func collapseServerList() {
		serverListSplitItem.animator().isCollapsed = true
	}

	@objc func toggleServerListVisibility() {
		serverListSplitItem.animator().isCollapsed = !serverListSplitItem.isCollapsed
	}

	func expandMemberList() {
		memberListSplitItem.animator().isCollapsed = false
	}

	func collapseMemberList() {
		memberListSplitItem.animator().isCollapsed = true
	}

	func updateMemberListVisibilityForSelection() {
		let shouldExpand = MainWindowMemberListVisibilityPolicy.shouldExpand(
			isChannel: selectedItem?.isChannel == true,
			isLoggedIn: selectedItem?.associatedClient?.isLoggedIn == true,
			isHiddenByUser: memberList.isHiddenByUser
		)

		if shouldExpand {
			expandMemberList()
		} else {
			collapseMemberList()
		}
	}

	@objc func toggleMemberListVisibility() {
		if memberListSplitItem.isCollapsed {
			guard MainWindowMemberListVisibilityPolicy.shouldExpand(
				isChannel: selectedItem?.isChannel == true,
				isLoggedIn: selectedItem?.associatedClient?.isLoggedIn == true,
				isHiddenByUser: false
			) else {
				memberList.isHiddenByUser = true
				return
			}

			memberList.isHiddenByUser = false
			expandMemberList()
		} else {
			memberList.isHiddenByUser = true
			collapseMemberList()
		}
	}

	var isMemberListVisible: Bool {
		memberListSplitItem?.isCollapsed == false
	}

	var isServerListVisible: Bool {
		serverListSplitItem?.isCollapsed == false
	}

	func setLoadingScreenProgressViewReason(_ reason: String) {
		loadingScreen.setProgressViewReason(reason)
	}

	func reloadLoadingScreen() -> Bool {
		guard let world = AppController.shared.world else {
			loadingScreen.showProgressView(withReason: MainWindowStrings.Loading.configuration)
			return false
		}
		if world.isImportingConfiguration {
			return false
		}
		if AppController.shared.applicationIsLaunched == false {
			loadingScreen.showProgressView(withReason: MainWindowStrings.Loading.configuration)
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
	func updateTitle(for item: IRCTreeItem) {
		if isItemSelected(item) {
			updateTitle()
		}
	}

	func updateTitle() {
		let content = MainWindowTitleContent(client: selectedClient, channel: selectedChannel)
		title = content.title
		subtitle = content.subtitle

		guard selectedClient != nil else {
			return
		}
		setAccessibilityTitle(AccessibilityStrings.mainWindow)
	}

	func updateDrawingForUserInUserList(_ user: User) {
		guard let channelUser = selectedChannel?.findMember(user.nickname) else { return }
		memberList.refreshDrawing(for: channelUser)
	}
}

// MARK: - Server list model and selection

public extension MainWindow {
	func saveSelection() {
		MainWindowStateStore().saveSelection(itemIdentifier: selectedItem?.uniqueIdentifier)
	}

	private func restoreExpandedClients() {
		for client in world.clientList
			where client.config.sidebarItemExpanded
		{
			expandClient(client)
		}
	}

	private func restoreSelectionDuringSetup() {
		guard let identifier = MainWindowStateStore().loadSelectionItemIdentifier(),
		      let item = world.findItem(withId: identifier)
		else {
			selectBestChoiceDuringSetup()
			return
		}
		select(item)
	}

	private func selectBestChoiceDuringSetup() {
		let first = world.clientList.first(where: { $0.config.autoConnect && $0.config.sidebarItemExpanded })
		if let first {
			var row = serverList.row(forItem: first)
			if first.channelCount > 0 {
				row += 1
			}
			serverList.selectItem(at: row)
		} else {
			serverList.selectItem(at: 0)
		}
	}

	func setupTrees() {
		memberList.keyDelegate = self
		memberList.target = menuController
		memberList.doubleAction = #selector(TXMenuController.memberInMemberListDoubleClicked(_:))
		serverList.keyDelegate = self
		serverList.delegate = self
		serverList.dataSource = self
		serverList.allowsEmptySelection = false
		serverList.allowsMultipleSelection = false
		serverList.target = self
		serverList.doubleAction = #selector(outlineViewDoubleClicked(_:))
		serverList.registerForDraggedTypes([MainWindowConstants.treeItemPasteboardType])
		restoreExpandedClients()
		restoreSelectionDuringSetup()
		serverListSelectionDidChange()
		menuController.populateNavigationChannelList()
	}

	func selectedChannel(on client: IRCClient) -> IRCChannel? {
		selectedClient === client ?
			selectedChannel : nil
	}

	func reloadTreeItem(_ item: IRCTreeItem) {
		serverList.refreshDrawing(forItem: item)
	}

	func reloadTreeGroup(_ item: IRCTreeItem) {
		guard item.isClient, let client = item.associatedClient else { return }
		reloadTreeItem(client)
		for channel in client.channelList {
			reloadTreeItem(channel)
		}
	}

	func reloadTree() {
		serverList.refreshAllDrawings()
	}

	func expandClient(_ client: IRCClient) {
		serverList.animator().expandItem(client)
	}

	func adjustSelection() {
		guard let selectedItem, serverList.row(forItem: selectedItem) >= 0 else {
			selectReplacement(excluding: nil)
			return
		}
		select(selectedItem)
	}

	private func storePreviousSelection() {
		previousSelectedItemId = selectedItem?.uniqueIdentifier
	}

	private func storeLastSelectedChannel() {
		selectedClient?.lastSelectedChannel = selectedChannel
	}

	func selectPreviousItem() {
		guard let previous = previouslySelectedItem else { return }
		select(previous)
	}

	func select(_ item: IRCTreeItem?) {
		guard let item else {
			selectReplacement(excluding: nil)
			return
		}
		if item.isClient == false {
			serverList.expandItem(item.associatedClient)
		}
		let row = serverList.row(forItem: item)
		guard row >= 0 else { return }
		serverList.selectItem(at: row)
		selectionDidChange()
	}

	func deselect(_ item: IRCTreeItem) {
		guard selectedItem === item else { return }
		let row = serverList.row(forItem: item)
		selectReplacement(excluding: row >= 0 ? IndexSet(integer: row) : nil)
	}

	func deselectGroup(_ item: IRCTreeItem) {
		guard item.isClient, selectedItem?.associatedClient === item.associatedClient else { return }
		var excluded = serverList.indexesOfItems(inGroup: item) ?? []
		let row = serverList.row(forItem: item)
		if row >= 0 {
			excluded.insert(row)
		}
		selectReplacement(excluding: excluded)
	}

	private func selectReplacement(excluding excludedRows: IndexSet?) {
		let currentRow = max(serverList.selectedRow, 0)
		let candidates = (0 ..< serverList.numberOfRows).filter { excludedRows?.contains($0) != true }
		guard let row = candidates.first(where: { $0 >= currentRow }) ?? candidates.last else {
			storePreviousSelection()
			selectedItem?.logController?.notifyDidBecomeHidden()
			selectedItem = nil
			channelView.show(nil)
			selectionDidChangePostflight()
			return
		}
		serverList.selectItem(at: row)
		selectionDidChange()
	}
}

// MARK: - Outline view data source and delegate

public extension MainWindow {
	@objc private func outlineViewDoubleClicked(_: Any?) {
		guard let client = selectedClient else { return }
		if let channel = selectedChannel {
			guard client.isLoggedIn else { return }
			if channel.isActive {
				if Preferences.Appearance.leaveOnDoubleClick.value {
					client.part(channel)
				}
			} else if Preferences.Appearance.joinOnDoubleClick.value {
				client.join(channel)
			}
		} else {
			if client.isConnecting || client.isConnected {
				if Preferences.Appearance.disconnectOnDoubleClick.value {
					client.quit()
				}
			} else if client.isQuitting == false, Preferences.Appearance.connectOnDoubleClick.value {
				client.connect()
			}
			expandClient(client)
		}
	}

	func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if let item = item as? IRCTreeItem {
			return Int(item.numberOfChildren)
		}
		return Int(AppController.shared.world?.clientCount ?? 0)
	}

	func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
		(item as? IRCTreeItem)?.numberOfChildren ?? 0 > 0
	}

	func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if let item = item as? IRCTreeItem {
			guard let child = item.child(at: index) else {
				preconditionFailure("Server-list item reported a child count that it cannot satisfy")
			}
			return child
		}
		return AppController.shared.world!.clientList[index]
	}

	func outlineView(_: NSOutlineView, objectValueFor _: NSTableColumn?, byItem item: Any?) -> Any? {
		item
	}

	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		guard let serverList = outlineView as? ServerList else {
			assertionFailure("The main-window outline delegate only supports ServerList")
			return nil
		}

		/* A row is a child row only for an item that is a channel. Anything the
		 outline view hands back that is not a tree item at all is drawn as a
		 group row, which is what the outline's root rows are. */
		guard let treeItem = item as? IRCTreeItem, treeItem.isClient == false else {
			return ServerListGroupRowCell(serverList: serverList)
		}
		return ServerListChildRowCell(serverList: serverList)
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor _: NSTableColumn?, item: Any) -> NSView? {
		let isChildRow = (item as? IRCTreeItem)?.isClient == false
		let identifier = NSUserInterfaceItemIdentifier(isChildRow ? "ChildView" : "GroupView")
		if let reusable = outlineView.makeView(withIdentifier: identifier, owner: self) {
			return reusable
		}

		let cell: ServerListCell = isChildRow
			? ServerListCellChildItem(frame: .zero)
			: ServerListCellGroupItem(frame: .zero)
		cell.identifier = identifier
		return cell
	}

	func outlineView(_: NSOutlineView, didAdd _: NSTableRowView, forRow row: Int) {
		serverList.refreshDrawing(forRow: row)
	}

	func outlineViewItemDidCollapse(_ notification: Notification) {
		(notification.userInfo?["NSObject"] as? IRCTreeItem)?.associatedClient?.sidebarItemIsExpanded = false
	}

	func outlineViewItemDidExpand(_ notification: Notification) {
		(notification.userInfo?["NSObject"] as? IRCTreeItem)?.associatedClient?.sidebarItemIsExpanded = true
	}

	func outlineView(_: NSOutlineView, shouldExpandItem _: Any) -> Bool {
		true
	}

	func outlineView(_: NSOutlineView, shouldCollapseItem _: Any) -> Bool {
		true
	}

	func outlineViewItemWillCollapse(_: Notification) {}

	func selectionShouldChange(in _: NSOutlineView) -> Bool {
		isKeyWindow
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		guard notification.object as? ServerList === serverList else {
			return
		}
		serverListSelectionDidChange()
	}

	private func serverListSelectionDidChange() {
		if ignoreNextOutlineViewSelectionChange {
			ignoreNextOutlineViewSelectionChange = false; return
		}
		guard ignoreOutlineViewSelectionChanges == false else { return }
		selectionDidChange()
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
		if draggedItem.isChannel, previous?.isChannel == false {
			return []
		}
		if draggedItem.isChannel == false, next?.isChannel == true {
			return []
		}
		return .generic
	}

	func outlineView(
		_: NSOutlineView,
		acceptDrop info: any NSDraggingInfo,
		item: Any?,
		childIndex index: Int
	) -> Bool {
		guard index >= 0, let draggedItem = draggedItem(from: info) else { return false }
		/* The world performs the move and tells its observers — this window
		 among them — to follow, rather than the drop rewriting both. */
		if draggedItem.isClient {
			guard let original = world.clientList.firstIndex(where: { $0 === draggedItem }) else { return false }
			world.moveClient(from: original, to: destinationIndex(proposed: index, movingFrom: original))
		} else {
			guard let client = item as? IRCClient, draggedItem.associatedClient === client else { return false }
			guard let original = client.channelList.firstIndex(where: { $0 === draggedItem }) else { return false }
			world.moveChannel(
				on: client,
				from: original,
				to: destinationIndex(proposed: index, movingFrom: original)
			)
		}
		return true
	}

	/// `childIndex` from `acceptDrop` counts the dragged item itself, but both
	/// the model array and `NSOutlineView.moveItem(at:inParent:to:inParent:)`
	/// want the index the item lands on once it has been removed. Moving
	/// downward therefore shifts by one; moving upward does not.
	private func destinationIndex(proposed index: Int, movingFrom original: Int) -> Int {
		index > original ? index - 1 : index
	}

	private func draggedItem(from info: any NSDraggingInfo) -> IRCTreeItem? {
		let pasteboard = info.draggingPasteboard
		guard pasteboard.availableType(from: [MainWindowConstants.treeItemPasteboardType]) != nil,
		      let token = pasteboard.string(forType: MainWindowConstants.treeItemPasteboardType)
		else { return nil }
		return world.findItem(withPasteboardString: token)
	}
}
