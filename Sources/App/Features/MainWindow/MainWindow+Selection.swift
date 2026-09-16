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

// MARK: - Selection and transcript view

extension MainWindow {
	var previouslySelectedItem: ChatItem? {
		guard let previousSelectedItemId else { return nil }
		return clientDirectory?.findItem(withId: previousSelectedItemId)
	}

	var selectedClient: Client? {
		selectedItem?.associatedClient
	}

	var selectedChannel: Channel? {
		guard let selectedItem, selectedItem.isClient == false else { return nil }
		return selectedItem as? Channel
	}

	var selectedViewController: TranscriptController? {
		if let controller = selectedChannel?.transcriptController {
			return controller
		}
		return selectedClient?.transcriptController
	}

	func isItemVisible(_ item: ChatItem) -> Bool {
		isItemSelected(item)
	}

	func isItemSelected(_ item: ChatItem?) -> Bool {
		item != nil && selectedItem === item
	}

	/// Remembers the row the next selection comes back to.
	func storePreviousSelection() {
		previousSelectedItemId = selectedItem?.uniqueIdentifier
	}

	/// Remembers which conversation the selected connection was last showing.
	func storeLastSelectedChannel() {
		selectedClient?.lastSelectedChannel = selectedChannel
	}

	func selectionDidChange() {
		let newItem = serverList.selectedItem
		guard selectedItem !== newItem else { return }
		storePreviousSelection()
		selectedItem = newItem
		presentationModel.transcript = newItem?.transcriptController?.ensureBackingView()
		newItem?.transcriptController?.notifyDidBecomeVisible()
		selectionDidChangePostflight()
	}

	func selectionDidChangePostflight() {
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
		   NSWorkspace.shared.isVoiceOverEnabled == false
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

	/** Puts the loading screen into the state the directory is in: waiting for the
	 configuration, offering to add the first server, or out of the way.

	 The answer is whether the window is showing conversations, which is what
	 decides whether the application may start connecting. */
	@discardableResult
	func reloadLoadingScreen() -> Bool {
		guard let clientDirectory else {
			loadingScreen.showProgressView(withReason: String(localized: .MainWindow.loadingConfiguration))
			return false
		}
		/* An import is replacing the clientDirectory underneath: whatever the screen is
		 showing is what it keeps showing until that finishes. */
		guard clientDirectory.isImportingConfiguration == false else { return false }
		guard AppServices.delegate.applicationIsLaunched else {
			loadingScreen.showProgressView(withReason: String(localized: .MainWindow.loadingConfiguration))
			return false
		}
		guard clientDirectory.clientCount > 0 else {
			loadingScreen.showNoServersView()
			return false
		}
		loadingScreen.hide()
		return true
	}
}

// MARK: - Window title

extension MainWindow {
	func updateTitle(for item: ChatItem) {
		/* The topic bar carries the channel's modes as a caption, and the same
		 events that retitle the window are what change them. Nothing in the IRC
		 layer addresses one transcript when a mode lands, so the redraw rides
		 along here. */
		item.transcriptController?.refreshTopicBar()
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
