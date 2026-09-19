// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import SwiftUI

/** What the window has selected, and everything that moves the selection.

 One file for the whole of it: which row is selected, what that row means to
 the rest of the window, and what happens when a row is chosen, closed or taken
 away. Reading and writing the selection used to be two files, so following a
 closed conversation to the row that replaced it meant reading both. */
extension MainWindow {
	var previouslySelectedItem: ChatItem? {
		guard let previousSelectedItemId else { return nil }
		return chatSession?.findItem(withId: previousSelectedItemId)
	}

	var selectedSession: ServerSession? {
		selectedItem?.associatedSession
	}

	var selectedConversation: Conversation? {
		guard let selectedItem, selectedItem.isSession == false else { return nil }
		return selectedItem as? Conversation
	}

	var selectedViewController: TranscriptController? {
		if let controller = selectedConversation?.transcriptController {
			return controller
		}
		return selectedSession?.transcriptController
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
	func storeLastSelectedConversation() {
		selectedSession?.lastSelectedConversation = selectedConversation
	}

	// MARK: - Moving the selection

	func adjustSelection() {
		guard let selectedItem, sidebar.row(forItem: selectedItem) >= 0 else {
			selectReplacement(excluding: [])
			return
		}
		select(selectedItem)
	}

	func selectPreviousItem() {
		guard let previous = previouslySelectedItem else { return }
		select(previous)
	}

	func select(_ item: ChatItem?) {
		guard let item else {
			selectReplacement(excluding: [])
			return
		}
		if item.isSession == false {
			sidebar.expandItem(item.associatedSession)
		}
		guard sidebar.row(forItem: item) >= 0 else { return }
		sidebar.select(item)
		selectionDidChange()
	}

	func deselect(_ item: ChatItem) {
		guard selectedItem === item else { return }
		selectReplacement(excluding: [ObjectIdentifier(item)])
	}

	func deselectGroup(_ item: ChatItem) {
		guard item.isSession, let session = item.associatedSession,
		      selectedItem?.associatedSession === session
		else { return }
		selectReplacement(excluding: Set(([session] as [ChatItem] + session.conversationList).map(ObjectIdentifier.init)))
	}

	/** Moves the selection off the rows that are going away.

	 The nearest row at or after the one that was selected, or the last row
	 before it; the rows are compared by identity rather than by index, so a
	 group that is being closed takes its own conversations out of the running
	 without the caller having to turn them into row numbers first. */
	private func selectReplacement(excluding excluded: Set<ObjectIdentifier>) {
		let currentRow = max(sidebar.selectedRow, 0)
		let candidates = sidebar.selectableItems.enumerated()
			.filter { excluded.contains(ObjectIdentifier($0.element)) == false }
		guard let replacement = candidates.first(where: { $0.offset >= currentRow })?.element
			?? candidates.last?.element
		else {
			storePreviousSelection()
			selectedItem = nil
			columnModel.transcript = nil
			selectionDidChangePostflight()
			return
		}
		sidebar.select(replacement)
		selectionDidChange()
	}

	// MARK: - What a changed selection changes

	func selectionDidChange() {
		let newItem = sidebar.selectedItem
		guard selectedItem !== newItem else { return }
		storePreviousSelection()
		selectedItem = newItem
		columnModel.transcript = newItem?.transcriptController?.ensureBackingView()
		newItem?.transcriptController?.notifyDidBecomeVisible()
		selectionDidChangePostflight()
	}

	func selectionDidChangePostflight() {
		/* The old conversation hears that typing stopped before the field is
		 refilled for the new one, in the same turn. A later notification found
		 the new conversation already recorded as the one being typed in. */
		inputTextField.typingNotice.finish(unlessIn: selectedConversation)
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

		memberList.assign(to: changedTo.isChannel ? changedTo as? Conversation : nil)
		if SettingsKeys.Input.focusTextViewOnSelectionChange.value,
		   NSWorkspace.shared.isVoiceOverEnabled == false
		{
			inputTextField.focus()
		}
		inputHistory.moveFocus(to: changedTo)
		inputTextField.resetSpellingIgnores()
		updateMemberListVisibilityForSelection()
		storeLastSelectedConversation()
		NotificationCenter.default.post(name: .mainWindowSelectionChanged, object: self)
		DockIcon.updateDockIcon()
		updateTitle()
	}
}
