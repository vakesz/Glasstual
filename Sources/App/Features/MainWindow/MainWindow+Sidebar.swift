// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import SwiftUI

/** The sidebar's own duties: what it is set up with, what it is told to redraw,
 and what it reports back. Which row is selected, and what happens when that
 changes, is ``MainWindow`` selection work and lives beside the rest of it. */
extension MainWindow {
	func saveSelection() {
		stateStore.saveSelection(itemIdentifier: selectedItem?.uniqueIdentifier)
	}

	private func restoreExpandedSessions() {
		for session in chatSession?.sessions ?? []
			where session.config.sidebarItemExpanded
		{
			expandSession(session)
		}
	}

	private func restoreSelectionDuringSetup() {
		guard let identifier = stateStore.loadSelectionItemIdentifier(),
		      let item = chatSession?.findItem(withId: identifier)
		else {
			selectBestChoiceDuringSetup()
			return
		}
		select(item)
	}

	/// The first connection that comes up on its own, opened at its first
	/// conversation; failing that, whatever the sidebar's first row is.
	private func selectBestChoiceDuringSetup() {
		guard let first = chatSession?.sessions
			.first(where: { $0.config.autoConnect && $0.config.sidebarItemExpanded })
		else {
			sidebar.select(sidebar.selectableItems.first)
			return
		}
		sidebar.select(first.conversationList.first ?? first)
	}

	func setupSidebar() {
		restoreExpandedSessions()
		restoreSelectionDuringSetup()
		sidebarSelectionDidChange()
		menuController.populateNavigationConversationList()
	}

	/** The sidebar's rows are values derived from the chat session, so every one of
	 these is the same instruction: rebuild them. The three names are
	 `ServerSessionPresenting` requirements that the IRC layer calls at different
	 granularities; the sidebar has only one. */
	func reloadChatItem(_: ChatItem) {
		sidebar.setNeedsRefresh()
	}

	func reloadChatItemGroup(_: ChatItem) {
		sidebar.setNeedsRefresh()
	}

	func reloadSidebar() {
		sidebar.setNeedsRefresh()
	}

	func expandSession(_ session: ServerSession) {
		sidebar.expandItem(session)
	}
}

// MARK: - What the sidebar reports back

extension MainWindow {
	func sidebarItemDoubleClicked() {
		guard let session = selectedSession else { return }
		if let conversation = selectedConversation {
			guard session.isLoggedIn else { return }
			if conversation.isActive {
				if SettingsKeys.Appearance.leaveOnDoubleClick.value {
					session.part(conversation)
				}
			} else if SettingsKeys.Appearance.joinOnDoubleClick.value {
				session.join(conversation)
			}
		} else {
			let policy = MenuServerActionRules(session: session)
			if policy.canDisconnect {
				if SettingsKeys.Appearance.disconnectOnDoubleClick.value {
					session.quit()
				}
			} else if policy.canConnect, SettingsKeys.Appearance.connectOnDoubleClick.value {
				session.connect()
			}
			expandSession(session)
		}
	}

	func sidebarSelectionDidChangeFromSwiftUI() {
		sidebarSelectionDidChange()
	}

	private func sidebarSelectionDidChange() {
		guard ignoreSidebarSelectionChanges == false else { return }
		selectionDidChange()
	}
}
