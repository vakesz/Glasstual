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
		for controller in logControllersInWorld {
			controller.changeTextSize(bigger)
		}
	}

	/// Actual Size: back to the unscaled text, in as many steps as it took to
	/// leave it. The controllers only know how to step, so the window walks
	/// them back rather than teaching them a second way to be told.
	public func resetTextSize() {
		while textSizeMultiplier > 1.0 {
			let previous = textSizeMultiplier
			changeTextSize(false)
			if textSizeMultiplier == previous || textSizeMultiplier < 1.0 {
				break
			}
		}
		while textSizeMultiplier < 1.0 {
			let previous = textSizeMultiplier
			changeTextSize(true)
			if textSizeMultiplier == previous || textSizeMultiplier > 1.0 {
				break
			}
		}
		textSizeMultiplier = 1.0
	}

	private var logControllersInWorld: [LogController] {
		guard let world else { return [] }
		return world.clientList.flatMap { client in
			[client.logController].compactMap(\.self) + client.channelList.compactMap(\.logController)
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
		for controller in logControllersInWorld {
			controller.reloadTheme()
		}
	}

	public func clearContents(of client: IRCClient) {
		client.resetState()
		client.logController?.clear()
		reloadTreeItem(client)
	}

	public func clearContents(of channel: Channel) {
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

	func textFormattingForegroundColor(_: NSEvent) {
		guard formattingMenu.isSet(.spoiler) == false else { return }
		if formattingMenu.isSet(.foregroundColorSet) {
			formattingMenu.setEffect(.foregroundColorSet, enabled: false)
			return
		}
		popUpColorMenu(formattingMenu.foregroundColorMenu)
	}

	func textFormattingBackgroundColor(_: NSEvent) {
		guard formattingMenu.isSet(.spoiler) == false, formattingMenu.isSet(.foregroundColorSet) else { return }
		if formattingMenu.isSet(.backgroundColorSet) {
			formattingMenu.setEffect(.backgroundColorSet, enabled: false)
			return
		}
		popUpColorMenu(formattingMenu.backgroundColorMenu)
	}

	/// The colour the menu picks applies at the caret, so the menu opens there
	/// — in the field's own coordinates, which is what `popUp` expects.
	private func popUpColorMenu(_ menu: NSMenu) {
		menu.popUp(positioning: nil, at: inputTextField.selectedRect.origin, in: inputTextField)
	}

	func focusTranscript(_: NSEvent) {
		guard attachedSheet == nil, let view = selectedViewController?.backingView else { return }
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
		guard selectedItem != nil else { return }
		selectedClient?.inputText(string, as: command)
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

	/** A gesture that does not qualify still has to clear the origin: the next
	 `endGesture` measures from it, and a stale one is a delta past any
	 threshold -- the channel changing under a gesture nobody made. */
	override func beginGesture(with event: NSEvent) {
		let touches = Array(event.touches(matching: .touching, in: nil))
		guard touches.count == 2, Preferences.Input.swipeMinimumLength.value >= 1 else {
			cachedSwipeOriginPoint = nil
			return
		}
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
	var previouslySelectedItem: TreeItem? {
		guard let previousSelectedItemId else { return nil }
		return world?.findItem(withId: previousSelectedItemId)
	}

	var selectedClient: IRCClient? {
		selectedItem?.associatedClient
	}

	var selectedChannel: Channel? {
		guard let selectedItem, selectedItem.isClient == false else { return nil }
		return selectedItem as? Channel
	}

	var selectedViewController: LogController? {
		if let controller = selectedChannel?.logController {
			return controller
		}
		return selectedClient?.logController
	}

	func isItemVisible(_ item: TreeItem) -> Bool {
		isItemSelected(item)
	}

	func isItemSelected(_ item: TreeItem?) -> Bool {
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

		memberList.assign(to: changedTo.isChannel ? changedTo as? Channel : nil)
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
		MainWindowStateStore().saveLayout(presentationModel.columnState)
	}

	func restoreSavedContentSplitViewState() {
		presentationModel.restoreColumns(MainWindowStateStore().loadLayout())
	}

	/** Moves a column, animated unless the system says not to.

	 A pane sweeping across the window is exactly the motion Reduce Motion asks
	 an interface to drop. The state change itself is the same either way, so
	 the pane simply appears. */
	private func changeColumnVisibility(_ change: () -> Void) {
		withAnimation(ReduceMotion.animation(.default)) {
			change()
		}
	}

	func expandServerList() {
		changeColumnVisibility { presentationModel.isServerListVisible = true }
	}

	func collapseServerList() {
		changeColumnVisibility { presentationModel.isServerListVisible = false }
	}

	@objc func toggleServerListVisibility() {
		changeColumnVisibility { presentationModel.isServerListVisible.toggle() }
	}

	/// The member list belongs beside a channel the connection has joined; the
	/// model derives the column's own visibility from that and from whether the
	/// reader has closed it.
	func updateMemberListVisibilityForSelection() {
		changeColumnVisibility {
			presentationModel.applyMemberListAvailability(
				selectedItem?.isChannel == true && selectedItem?.associatedClient?.isLoggedIn == true
			)
		}
	}

	@objc func toggleMemberListVisibility() {
		changeColumnVisibility { presentationModel.toggleMemberList() }
	}

	var isMemberListVisible: Bool {
		presentationModel.isMemberListVisible
	}

	var isServerListVisible: Bool {
		presentationModel.isServerListVisible
	}

	/** Puts the loading screen into the state the world is in: waiting for the
	 configuration, offering to add the first server, or out of the way.

	 The answer is whether the window is showing conversations, which is what
	 decides whether the application may start connecting. */
	@discardableResult
	func reloadLoadingScreen() -> Bool {
		guard let world else {
			loadingScreen.showProgressView(withReason: MainWindowStrings.Loading.configuration)
			return false
		}
		/* An import is replacing the world underneath: whatever the screen is
		 showing is what it keeps showing until that finishes. */
		guard world.isImportingConfiguration == false else { return false }
		guard AppController.shared.applicationIsLaunched else {
			loadingScreen.showProgressView(withReason: MainWindowStrings.Loading.configuration)
			return false
		}
		guard world.clientCount > 0 else {
			loadingScreen.showNoServersView()
			return false
		}
		loadingScreen.hide()
		return true
	}
}

// MARK: - Window title

public extension MainWindow {
	func updateTitle(for item: TreeItem) {
		/* The topic bar carries the channel's modes as a caption, and the same
		 events that retitle the window are what change them. Nothing in the IRC
		 layer addresses one transcript when a mode lands, so the redraw rides
		 along here. */
		item.logController?.refreshTopicBar()
		if isItemSelected(item) || (item.isClient && selectedClient === item) {
			updateTitle()
		}
	}

	func updateTitle() {
		let content = MainWindowTitleContent(client: selectedClient, channel: selectedChannel)
		title = content.title
		subtitle = content.subtitle
		setAccessibilityTitle([content.title, content.subtitle].filter { $0.isEmpty == false }.joined(separator: ", "))
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

	/// The first connection that comes up on its own, opened at its first
	/// conversation; failing that, whatever the sidebar's first row is.
	private func selectBestChoiceDuringSetup() {
		guard let first = world?.clientList
			.first(where: { $0.config.autoConnect && $0.config.sidebarItemExpanded })
		else {
			serverList.select(serverList.selectableItems.first)
			return
		}
		serverList.select(first.channelList.first ?? first)
	}

	func setupTrees() {
		restoreExpandedClients()
		restoreSelectionDuringSetup()
		serverListSelectionDidChange()
		menuController.actionCoordinator.populateNavigationChannelList()
	}

	func selectedChannel(on client: IRCClient) -> Channel? {
		selectedClient === client ?
			selectedChannel : nil
	}

	/** The sidebar's rows are values derived from the tree, so every one of
	 these is the same instruction: rebuild them. The three names are
	 `ClientOutput` requirements that the IRC layer calls at different
	 granularities; the sidebar has only one. */
	func reloadTreeItem(_: TreeItem) {
		serverList.setNeedsRefresh()
	}

	func reloadTreeGroup(_: TreeItem) {
		serverList.setNeedsRefresh()
	}

	func reloadTree() {
		serverList.setNeedsRefresh()
	}

	func expandClient(_ client: IRCClient) {
		serverList.expandItem(client)
	}

	func adjustSelection() {
		guard let selectedItem, serverList.row(forItem: selectedItem) >= 0 else {
			selectReplacement(excluding: [])
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

	func select(_ item: TreeItem?) {
		guard let item else {
			selectReplacement(excluding: [])
			return
		}
		if item.isClient == false {
			serverList.expandItem(item.associatedClient)
		}
		guard serverList.row(forItem: item) >= 0 else { return }
		serverList.select(item)
		selectionDidChange()
	}

	func deselect(_ item: TreeItem) {
		guard selectedItem === item else { return }
		selectReplacement(excluding: [ObjectIdentifier(item)])
	}

	func deselectGroup(_ item: TreeItem) {
		guard item.isClient, let client = item.associatedClient,
		      selectedItem?.associatedClient === client
		else { return }
		selectReplacement(excluding: Set(([client] as [TreeItem] + client.channelList).map(ObjectIdentifier.init)))
	}

	/** Moves the selection off the rows that are going away.

	 The nearest row at or after the one that was selected, or the last row
	 before it; the rows are compared by identity rather than by index, so a
	 group that is being closed takes its own conversations out of the running
	 without the caller having to turn them into row numbers first. */
	private func selectReplacement(excluding excluded: Set<ObjectIdentifier>) {
		let currentRow = max(serverList.selectedRow, 0)
		let candidates = serverList.selectableItems.enumerated()
			.filter { excluded.contains(ObjectIdentifier($0.element)) == false }
		guard let replacement = candidates.first(where: { $0.offset >= currentRow })?.element
			?? candidates.last?.element
		else {
			storePreviousSelection()
			selectedItem?.logController?.notifyDidBecomeHidden()
			selectedItem = nil
			presentationModel.transcript = nil
			selectionDidChangePostflight()
			return
		}
		serverList.select(replacement)
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
			let policy = MenuServerActionPolicy(client: client)
			if policy.canDisconnect {
				if Preferences.Appearance.disconnectOnDoubleClick.value {
					client.quit()
				}
			} else if policy.canConnect, Preferences.Appearance.connectOnDoubleClick.value {
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
