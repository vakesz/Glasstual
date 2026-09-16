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

// MARK: - Server list model and selection

extension MainWindow {
	func saveSelection() {
		MainWindowStateStore().saveSelection(itemIdentifier: selectedItem?.uniqueIdentifier)
	}

	private func restoreExpandedClients() {
		for client in clientDirectory?.clientList ?? []
			where client.config.sidebarItemExpanded
		{
			expandClient(client)
		}
	}

	private func restoreSelectionDuringSetup() {
		guard let identifier = MainWindowStateStore().loadSelectionItemIdentifier(),
		      let item = clientDirectory?.findItem(withId: identifier)
		else {
			selectBestChoiceDuringSetup()
			return
		}
		select(item)
	}

	/// The first connection that comes up on its own, opened at its first
	/// conversation; failing that, whatever the sidebar's first row is.
	private func selectBestChoiceDuringSetup() {
		guard let first = clientDirectory?.clientList
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
		menuController.populateNavigationChannelList()
	}

	func selectedChannel(on client: Client) -> Channel? {
		selectedClient === client ?
			selectedChannel : nil
	}

	/** The sidebar's rows are values derived from the tree, so every one of
	 these is the same instruction: rebuild them. The three names are
	 `ClientOutput` requirements that the IRC layer calls at different
	 granularities; the sidebar has only one. */
	func reloadChatItem(_: ChatItem) {
		serverList.setNeedsRefresh()
	}

	func reloadChatItemGroup(_: ChatItem) {
		serverList.setNeedsRefresh()
	}

	func reloadTree() {
		serverList.setNeedsRefresh()
	}

	func expandClient(_ client: Client) {
		serverList.expandItem(client)
	}

	func adjustSelection() {
		guard let selectedItem, serverList.row(forItem: selectedItem) >= 0 else {
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
		if item.isClient == false {
			serverList.expandItem(item.associatedClient)
		}
		guard serverList.row(forItem: item) >= 0 else { return }
		serverList.select(item)
		selectionDidChange()
	}

	func deselect(_ item: ChatItem) {
		guard selectedItem === item else { return }
		selectReplacement(excluding: [ObjectIdentifier(item)])
	}

	func deselectGroup(_ item: ChatItem) {
		guard item.isClient, let client = item.associatedClient,
		      selectedItem?.associatedClient === client
		else { return }
		selectReplacement(excluding: Set(([client] as [ChatItem] + client.channelList).map(ObjectIdentifier.init)))
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

// MARK: - What the server list reports back

extension MainWindow {
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
