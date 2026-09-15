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

	private func completeNickname(_ movingForward: Bool) {
		nicknameCompletionStatus.completeNickname(movingForward)
	}

	/// Answers whether the window acted on Tab; `false` leaves the key to the
	/// message field's own keyboard navigation.
	func tab(_: NSEvent) -> Bool {
		performTabKeyAction(movingForward: true)
	}

	func shiftTab(_: NSEvent) -> Bool {
		performTabKeyAction(movingForward: false)
	}

	private func performTabKeyAction(movingForward: Bool) -> Bool {
		switch MainWindowTabKeyPolicy.outcome(for: Preferences.Input.tabKeyAction.value) {
		case .completeNickname:
			completeNickname(movingForward)
		case .unreadChannel:
			navigateChannelEntries(movingForward, withNavigationType: .unread)
		case .keyboardNavigation:
			return false
		}
		return true
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

	/** Two-finger swipes between conversations, read from scroll events.

	 The window used to read them from `beginGesture` and `endGesture`, which
	 AppKit no longer sends, so the gesture did nothing. A trackpad swipe
	 arrives as a scroll gesture. The transcript's scroll view passes a
	 horizontal one up the responder chain because this window asks for it
	 below. The window then tracks it with the system's fluid swipe, which
	 respects the "Swipe between pages" setting and the application's own
	 switch. */
	override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
		axis == .horizontal && MainWindowSwipePolicy.isEnabled(
			systemAllowsSwipeTracking: NSEvent.isSwipeTrackingFromScrollEventsEnabled,
			swipePreference: Preferences.Input.swipeMinimumLength.value
		)
	}

	override func scrollWheel(with event: NSEvent) {
		guard MainWindowSwipePolicy.beginsSwipe(
			phase: event.phase,
			scrollingDeltaX: event.scrollingDeltaX,
			scrollingDeltaY: event.scrollingDeltaY,
			isEnabled: wantsScrollEventsForSwipeTracking(on: .horizontal)
		) else {
			super.scrollWheel(with: event)
			return
		}

		event.trackSwipeEvent(
			options: [.lockDirection, .clampGestureAmount],
			dampenAmountThresholdMin: -1,
			max: 1
		) { [weak self] gestureAmount, phase, isComplete, _ in
			switch MainWindowSwipePolicy.destination(gestureAmount: gestureAmount, phase: phase, isComplete: isComplete) {
			case .previous:
				self?.selectPreviousWindow(nil)
			case .next:
				self?.selectNextWindow(nil)
			case nil:
				break
			}
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

	/** The frame Reset Window gives back, where the window already is.

	 The appearance's default size is never allowed below the window's own
	 minimum. The bundled default is 474 points tall against a 500-point
	 minimum content height, so Reset Window left the window smaller than a
	 resize could ever make it. */
	var defaultWindowFrame: NSRect {
		let minimumSize = frameRect(forContentRect: NSRect(origin: .zero, size: contentMinSize)).size
		let defaultSize = userInterfaceObjects.defaultWindowSize
		var value = frame
		value.size = NSSize(
			width: max(defaultSize.width, minimumSize.width),
			height: max(defaultSize.height, minimumSize.height)
		)
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
		selectedItem = newItem
		presentationModel.transcript = newItem?.logController?.ensureBackingView()
		newItem?.logController?.notifyDidBecomeVisible()
		selectionDidChangePostflight()
	}

	private func selectionDidChangePostflight() {
		/* The old conversation hears that typing stopped before the field is
		 refilled for the new one, in the same turn. A later notification found
		 the new conversation already recorded as the one being typed in. */
		inputTextField.finishTypingNotice(unlessIn: selectedChannel)
		let changedTo = selectedItem
		let changedFrom = previouslySelectedItem
		guard changedTo !== changedFrom else { return }
		changedFrom?.resetState()
		if let changedTo {
			changedTo.resetState()
			noteItemWasViewed(changedTo)
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

	func toggleServerListVisibility() {
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

	func toggleMemberListVisibility() {
		changeColumnVisibility { presentationModel.toggleMemberList() }
	}

	var isMemberListVisible: Bool {
		presentationModel.isMemberListVisible
	}

	var isServerListVisible: Bool {
		presentationModel.isServerListVisible
	}

	/** Hides the AppKit views under the loading overlay, or shows them again.

	 SwiftUI's `disabled` and `accessibilityHidden` stop at the representables,
	 so the message field and the transcript stayed in the key view loop and in
	 the accessibility tree under an overlay that covered them. A hidden view
	 is in neither. Nothing under the overlay may keep the keyboard either, so
	 a view that holds it gives it back to the window. */
	func setConversationObscured(_ isObscured: Bool) {
		if isObscured, firstResponder is NSView {
			makeFirstResponder(nil)
		}
		inputContentView.isHidden = isObscured
		presentationModel.isConversationObscured = isObscured
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
		guard ignoreServerListSelectionChanges == false else { return }
		selectionDidChange()
	}
}

/// What Tab does in the message field, by preference.
enum MainWindowTabKeyPolicy {
	enum Outcome: Equatable {
		case completeNickname
		case unreadChannel
		/// The window declines the key, and the field moves the keyboard on.
		case keyboardNavigation
	}

	static func outcome(for action: TabKeyAction) -> Outcome {
		switch action {
		case .nicknameComplete: .completeNickname
		case .unreadChannel: .unreadChannel
		case .none: .keyboardNavigation
		}
	}
}

/// When a two-finger horizontal swipe moves between conversations, and which way.
enum MainWindowSwipePolicy {
	enum Destination: Equatable {
		case previous
		case next
	}

	/** Both switches have to be on. One is the system's "Swipe between pages",
	 and the other is the application's own preference, where zero has always
	 meant off. The preference used to be a distance between two touches. The
	 distance a swipe has to cover is now the system's threshold, the same one
	 every other swipe on the Mac uses. */
	static func isEnabled(systemAllowsSwipeTracking: Bool, swipePreference: Double) -> Bool {
		systemAllowsSwipeTracking && swipePreference > 0
	}

	/// A swipe is tracked from the event that starts the scroll gesture, and
	/// only when that gesture leads sideways.
	static func beginsSwipe(
		phase: NSEvent.Phase,
		scrollingDeltaX: CGFloat,
		scrollingDeltaY: CGFloat,
		isEnabled: Bool
	) -> Bool {
		isEnabled && phase == .began && scrollingDeltaX != 0 && abs(scrollingDeltaX) > abs(scrollingDeltaY)
	}

	/** Where a tracked swipe lands, decided once, when the tracking completes.

	 AppKit calls the handler for every update and every animation frame, so
	 only the completing call may move the selection. A swipe carried past the
	 system's threshold completes as `.ended` at a full gesture amount. One
	 that fell short completes as `.cancelled`, back at zero. Fingers moving
	 right go back, as they do between pages, and fingers moving left go on. */
	static func destination(gestureAmount: CGFloat, phase: NSEvent.Phase, isComplete: Bool) -> Destination? {
		guard isComplete, phase == .ended, gestureAmount != 0 else { return nil }
		return gestureAmount > 0 ? .previous : .next
	}
}
