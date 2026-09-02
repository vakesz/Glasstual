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
import SwiftUI

// MARK: - View controls and input

extension MainWindow {
	private enum TextZoomPolicy {
		static let step = 1.2
		static let allowedRange = 0.5 ... 3.0
	}

	public func changeTextSize(_ bigger: Bool) {
		let next = bigger ? textSizeMultiplier * TextZoomPolicy.step : textSizeMultiplier / TextZoomPolicy.step
		guard TextZoomPolicy.allowedRange.contains(next) else { return }
		textSizeMultiplier = next
		guard let world else { return }
		for client in world.clientList {
			client.logController?.changeTextSize(bigger)
			for channel in client.channelList {
				channel.logController?.changeTextSize(bigger)
			}
		}
	}

	public func markAllAsRead() {
		guard let world else { return }
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
		reloadTree()
	}

	public func reloadTheme() {
		guard let world else { return }
		for client in world.clientList {
			client.logController?.reloadTheme()
			for channel in client.channelList {
				channel.logController?.reloadTheme()
			}
		}
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
		guard let world else { return }
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
		popUpColorMenu(formattingMenu.foregroundColorMenu)
	}

	func textFormattingBackgroundColor(_: NSEvent) {
		guard formattingMenu.textHasSpoiler == false, formattingMenu.textHasForegroundColor else { return }
		if formattingMenu.textHasBackgroundColor {
			formattingMenu.removeBackgroundColorCharFromTextBox(nil)
			return
		}
		popUpColorMenu(formattingMenu.backgroundColorMenu)
	}

	/// The colour the menu picks applies at the caret, so the menu opens there
	/// — in the field's own coordinates, which is what `popUp` expects.
	private func popUpColorMenu(_ menu: NSMenu) {
		menu.popUp(positioning: nil, at: inputTextField.selectedRect.origin, in: inputTextField)
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
		return world?.findItem(withId: previousSelectedItemId)
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
		let newItem = serverList.selectedItem
		guard selectedItem !== newItem else { return }
		storePreviousSelection()
		let previousItem = selectedItem
		selectedItem = newItem
		presentationModel.transcript = newItem?.logController?.ensureBackingView()
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
			updateMemberListVisibilityForSelection()
			updateTitle()
			return
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
		presentationModel.isMemberListVisible = state.isMemberListVisible
		presentationModel.isServerListVisible = state.isServerListVisible
	}

	func expandServerList() {
		withAnimation {
			presentationModel.isServerListVisible = true
		}
	}

	func collapseServerList() {
		withAnimation {
			presentationModel.isServerListVisible = false
		}
	}

	@objc func toggleServerListVisibility() {
		withAnimation {
			presentationModel.isServerListVisible.toggle()
		}
	}

	func expandMemberList() {
		withAnimation {
			presentationModel.isMemberListVisible = true
		}
	}

	func collapseMemberList() {
		withAnimation {
			presentationModel.isMemberListVisible = false
		}
	}

	func updateMemberListVisibilityForSelection() {
		let isAvailable = MainWindowMemberListVisibilityPolicy.isAvailable(
			isChannel: selectedItem?.isChannel == true,
			isLoggedIn: selectedItem?.associatedClient?.isLoggedIn == true
		)
		presentationModel.isMemberListAvailable = isAvailable

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
		if presentationModel.isMemberListVisible == false {
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
		presentationModel.isMemberListVisible
	}

	var isServerListVisible: Bool {
		presentationModel.isServerListVisible
	}

	func setLoadingScreenProgressViewReason(_ reason: String) {
		loadingScreen.setProgressViewReason(reason)
	}

	func reloadLoadingScreen() -> Bool {
		guard let world else {
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
		guard selectedChannel?.findMember(user.nickname) != nil else { return }
		memberList.invalidatePresentation()
	}
}

// MARK: - Server list model and selection

public extension MainWindow {
	func saveSelection() {
		MainWindowStateStore().saveSelection(itemIdentifier: selectedItem?.uniqueIdentifier)
	}

	private func restoreExpandedClients() {
		for client in world?.clientList ?? []
			where client.config.sidebarItemExpanded
		{
			expandClient(client)
		}
	}

	private func restoreSelectionDuringSetup() {
		guard let identifier = MainWindowStateStore().loadSelectionItemIdentifier(),
		      let item = world?.findItem(withId: identifier)
		else {
			selectBestChoiceDuringSetup()
			return
		}
		select(item)
	}

	private func selectBestChoiceDuringSetup() {
		let first = world?.clientList.first(where: { $0.config.autoConnect && $0.config.sidebarItemExpanded })
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
		serverList.expandItem(client)
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
			presentationModel.transcript = nil
			selectionDidChangePostflight()
			return
		}
		serverList.selectItem(at: row)
		selectionDidChange()
	}
}

// MARK: - Outline view data source and delegate

public extension MainWindow {
	func serverListItemDoubleClicked() {
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

	func serverListSelectionDidChangeFromSwiftUI() {
		serverListSelectionDidChange()
	}

	private func serverListSelectionDidChange() {
		if ignoreNextServerListSelectionChange {
			ignoreNextServerListSelectionChange = false; return
		}
		guard ignoreServerListSelectionChanges == false else { return }
		selectionDidChange()
	}
}
