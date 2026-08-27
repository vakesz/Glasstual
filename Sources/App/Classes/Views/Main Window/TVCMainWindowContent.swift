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
import GlasstualPluginKit

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
		let markScrollback = TextualPreferences.autoAddScrollbackMark()
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
		DockIcon.updateDockIcon()
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
			guard let self, NSObject.applicationController().applicationIsTerminating == false else { return }
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
		reloadTreeItem(legacyTreeItem(channel))
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

	func tab(_: NSEvent) {
		switch TextualPreferences.tabKeyAction() {
		case .nicknameComplete: completeNickname(true)
		case .unreadChannel: navigateChannelEntries(true, withNavigationType: .unread)
		default: break
		}
	}

	func shiftTab(_: NSEvent) {
		switch TextualPreferences.tabKeyAction() {
		case .nicknameComplete: completeNickname(false)
		case .unreadChannel: navigateChannelEntries(false, withNavigationType: .unread)
		default: break
		}
	}

	func sendControlEnterMessageMaybe(_ event: NSEvent) {
		if TextualPreferences.controlEnterSendsMessage() {
			textEntered()
		} else {
			inputTextField.keyDownToSuper(event)
		}
	}

	func sendMessageAsAction(_: NSEvent) {
		if TextualPreferences.commandReturnSendsMessageAsAction() {
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
			formattingMenu.removeForegroundColorCharFromTextBox(nil)
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

	func focusWebview(_: NSEvent) {
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
		guard TextualPreferences.swipeMinimumLength() >= 1 else { return }
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
		let minimum = TextualPreferences.swipeMinimumLength()
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

	@objc func preferencesChanged() {
		if TextualPreferences.displayDockBadge() {
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
		return nativeChannel(selectedItem)
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
		let newItems = serverList.selectedItems as? [IRCTreeItem] ?? []
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
			nativeLogController(item.viewController).notifyDidBecomeHidden()
		}
		for item in newItems where previousItems.contains(where: { $0 === item }) == false {
			nativeLogController(item.viewController).notifyDidBecomeVisible()
			if item !== selectedItem {
				nativeLogController(item.viewController).notifySelectionChanged()
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
		if let changedFrom {
			nativeLogController(changedFrom.viewController).notifySelectionChanged()
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
		if TextualPreferences.focusMainTextViewOnSelectionChange(),
		   Accessibility.isVoiceOverEnabled == false
		{
			inputTextField.focus()
		}
		inputHistory.moveFocus(to: changedTo)
		inputTextField.resetSpellingIgnores()
		updateMemberListVisibilityForSelection()
		nativeLogController(changedTo.viewController).notifySelectionChanged()
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

	@objc func setLoadingScreenProgressViewReason(_ reason: String) {
		loadingScreen.setProgressViewReason(reason)
	}

	@objc func reloadLoadingScreen() -> Bool {
		guard let world = NSObject.applicationController().world else {
			loadingScreen.showProgressView(withReason: MainWindowStrings.Loading.configuration)
			return false
		}
		if world.isImportingConfiguration {
			return false
		}
		if NSObject.applicationController().applicationIsLaunched == false {
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
	@objc func updateTitle(for item: IRCTreeItem) {
		if isItemSelected(item) {
			updateTitle()
		}
	}

	@objc func updateTitle() {
		guard let client = selectedClient else {
			title = ApplicationInfo.applicationName()
			subtitle = ""
			return
		}
		let channel = selectedChannel
		let connectionStatus: MainWindowStrings.ConnectionStatus? = {
			if client.isConnected == false,
			   client
			   .isConnecting ==
			   false
			{
				return client.isReconnecting ? .waitingToReconnect : .disconnected
			}
			if client.isConnecting,
			   client
			   .isLoggedIn ==
			   false
			{
				return [.retry, .reconnect].contains(client.connectType) ? .reconnecting : .connecting
			}
			if client.isConnected, client.isLoggedIn == false {
				return .loggingOn
			}
			if client.isQuitting {
				return .disconnecting
			}
			return nil
		}()
		let status = connectionStatus?.title

		var nickname = client.userNickname
		if client.userIsAway, nickname.isEmpty == false {
			nickname += MainWindowStrings.Conversation.awayNicknameSuffix
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
				parts.append(
					MainWindowStrings.Conversation.userCount(
						formattedNumber(Int(channel.numberOfMembers)) as String
					)
				)
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
				parts.append(MainWindowStrings.Conversation.directChat)
			case .utility:
				break
			@unknown default:
				break
			}
		} else {
			title = network.isEmpty ? ApplicationInfo.applicationName() : network
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
		setAccessibilityTitle(AccessibilityStrings.mainWindow)
	}

	@objc func updateDrawingForUserInUserList(_ user: User) {
		guard let selectedChannel, let channelUser = user.userAssociated(with: selectedChannel) else { return }
		memberList.refreshDrawing(for: channelUser)
	}
}

// MARK: - Server list model and selection

public extension MainWindow {
	func saveSelection() {
		MainWindowStateStore().saveSelection(itemIdentifiers: selectedItems.map(\.uniqueIdentifier))
	}

	private func restoreExpandedClients() {
		for client in world.clientList
			where client.config.sidebarItemExpanded
		{
			expandClient(client)
		}
	}

	private func restoreSelectionDuringSetup() {
		let identifiers = MainWindowStateStore().loadSelectionItemIdentifiers()
		guard identifiers.isEmpty == false else {
			selectBestChoiceDuringSetup()
			return
		}
		let selection = world.findItems(withIds: identifiers)
		guard selection.isEmpty == false else {
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
			serverList.selectItem(at: row)
		} else {
			serverList.selectItem(at: 0)
		}
	}

	func setupTrees() {
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
			reloadTreeItem(legacyTreeItem(channel))
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

	func adjustSelection(with items: [IRCTreeItem], selectedItem: IRCTreeItem?) {
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
			serverList.selectRowIndexes(rows as IndexSet, byExtendingSelection: false, scrollingToSelection: true)
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
		selectedClient?.lastSelectedChannel = selectedChannel
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
		if let newItem, newItem.isClient == false, let client = newItem.associatedClient {
			expandClient(client)
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
		if deselectChildren, let oldItem,
		   let children = serverList.indexesOfItems(inGroup: oldItem) as IndexSet?
		{
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
		serverList.selectRowIndexes(nextRows, byExtendingSelection: false, scrollingToSelection: true)
	}
}

// MARK: - Outline view data source and delegate

public extension MainWindow {
	@objc private func outlineViewDoubleClicked(_: Any?) {
		guard let client = selectedClient else { return }
		if let channel = selectedChannel {
			guard client.isLoggedIn else { return }
			if channel.isActive {
				if TextualPreferences.leaveOnDoubleclick() {
					client.part(channel)
				}
			} else if TextualPreferences.joinOnDoubleclick() {
				client.join(channel)
			}
		} else {
			if client.isConnecting || client.isConnected {
				if TextualPreferences.disconnectOnDoubleclick() {
					client.quit()
				}
			} else if client.isQuitting == false, TextualPreferences.connectOnDoubleclick() {
				client.connect()
			}
			expandClient(client)
		}
	}

	func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if let item = item as? IRCTreeItem {
			return Int(item.numberOfChildren)
		}
		return Int(NSObject.applicationController().world?.clientCount ?? 0)
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
		return NSObject.applicationController().world!.clientList[index]
	}

	func outlineView(_: NSOutlineView, objectValueFor _: NSTableColumn?, byItem item: Any?) -> Any? {
		item
	}

	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		guard let serverList = outlineView as? ServerList else {
			assertionFailure("The main-window outline delegate only supports ServerList")
			return nil
		}

		if (item as? IRCTreeItem)?
			.isClient != false
		{
			return ServerListGroupRowCell(serverList: serverList)
		}
		return ServerListChildRowCell(serverList: serverList)
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

	func selectionShouldChange(in outlineView: NSOutlineView) -> Bool {
		guard let serverList = outlineView as? ServerList else { return true }
		if serverList.isInvalidatingSelectionBackground {
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
			maximumCount: MainWindowConstants.maximumSelectedRows
		)
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		serverListSelectionDidChange(for: notification.object as? ServerList)
	}

	private func serverListSelectionDidChange(for changedList: ServerList?) {
		let list = changedList ?? serverList!
		guard list.isInvalidatingSelectionBackground == false else { return }
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
