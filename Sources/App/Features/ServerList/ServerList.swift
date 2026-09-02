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
import Observation

/// Selection, expansion and ordering state for the SwiftUI server sidebar.
///
/// The IRC world remains the source of truth for clients and channels. This
/// model derives `rows` from it — value snapshots the view draws without
/// touching the tree — and owns only presentation state, which keeps the view
/// independent of protocol mutation details.
@MainActor
@Observable
public final class ServerList {
	public private(set) var selectedItemIdentifier: String?
	/// What the view draws. Rebuilt whenever the tree reports a change, so a
	/// row is never asked to notice one on its own.
	private(set) var rows: [ServerRow] = []
	/// What the sidebar's search field holds. While it is non-empty the list
	/// shows every channel whose name contains it, under its server, whether or
	/// not that server is disclosed.
	public var filterText = "" {
		didSet { rebuildRows() }
	}

	@ObservationIgnored weak var mainWindow: MainWindow?

	private var updateDepth = 0
	private var updateIsPending = false

	public init() {}

	/** No rows are built here: the window attaches before the world exists, and
	 the world's first `addItem` is what fills them. */
	func attach(to window: MainWindow) {
		precondition(mainWindow == nil || mainWindow === window)
		mainWindow = window
	}

	// MARK: - Rows

	private func rebuildRows() {
		rows = clients.filter(isVisible).map { client in
			ServerRow(
				id: client.uniqueIdentifier,
				title: client.label,
				isActive: client.isActive,
				isSecured: client.isSecured,
				isExpanded: isFiltering || isExpanded(client),
				showsDisclosure: isFiltering == false,
				channels: visibleChannels(for: client).map(channelRow)
			)
		}
	}

	private func channelRow(_ channel: IRCChannel) -> ChannelRow {
		let kind: ChannelRow.Kind = if channel.isChannel {
			.channel
		} else if channel.isDirectChat {
			.directChat
		} else if channel.isUtility {
			.utility
		} else {
			.privateMessage
		}
		return ChannelRow(
			id: channel.uniqueIdentifier,
			title: channel.label,
			kind: kind,
			isActive: channel.isActive,
			hasJoinError: channel.errorOnLastJoinAttempt,
			unreadCount: channel.treeUnreadCount,
			showsUnreadCount: channel.config.showTreeBadgeCount,
			highlightCount: channel.config.ignoreHighlights ? 0 : channel.nicknameHighlightCount
		)
	}

	public var clients: [IRCClient] {
		mainWindow?.world?.clientList ?? []
	}

	/** The items the list is drawing, in row order.

	 The same projection `rebuildRows()` draws, so the index-based commands —
	 next and previous conversation, the jump to a random unread row — address
	 the rows the reader can see rather than a tree the filter has hidden. */
	private var visibleItems: [IRCTreeItem] {
		clients.filter(isVisible).flatMap { client -> [IRCTreeItem] in
			[client] + visibleChannels(for: client)
		}
	}

	public var numberOfRows: Int {
		visibleItems.count
	}

	public var selectedRow: Int {
		guard let selectedItemIdentifier else { return -1 }
		return visibleItems.firstIndex { $0.uniqueIdentifier == selectedItemIdentifier } ?? -1
	}

	public var selectedItem: IRCTreeItem? {
		guard let selectedItemIdentifier else { return nil }
		return mainWindow?.world?.findItem(withId: selectedItemIdentifier)
	}

	public var groupItems: [IRCTreeItem] {
		clients
	}

	public func item(atRow row: Int) -> Any? {
		visibleItems.indices.contains(row) ? visibleItems[row] : nil
	}

	public func row(forItem item: Any?) -> Int {
		guard let item = item as? IRCTreeItem else { return -1 }
		return visibleItems.firstIndex { $0 === item } ?? -1
	}

	public func selectItem(at row: Int) {
		guard let item = item(atRow: row) as? IRCTreeItem else { return }
		selectedItemIdentifier = item.uniqueIdentifier
	}

	func selectFromSwiftUI(_ identifier: String?) {
		guard selectedItemIdentifier != identifier else { return }
		selectedItemIdentifier = identifier
		mainWindow?.serverListSelectionDidChangeFromSwiftUI()
	}

	public func items(inContainingGroupOf item: Any) -> [IRCTreeItem]? {
		guard let item = item as? IRCTreeItem, let client = item.associatedClient else { return nil }
		return client.channelList
	}

	public func indexesOfItems(inGroup item: Any) -> IndexSet? {
		guard let item = item as? IRCTreeItem, let client = item.associatedClient else { return nil }
		return IndexSet(client.channelList.compactMap { channel in
			let row = row(forItem: channel)
			return row >= 0 ? row : nil
		})
	}

	public func isExpanded(_ client: IRCClient) -> Bool {
		client.sidebarItemIsExpanded
	}

	private var isFiltering: Bool {
		filterQuery.isEmpty == false
	}

	private var filterQuery: String {
		filterText.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// The channels drawn under a server: all of them while it is disclosed,
	/// only the matching ones while a filter is in effect.
	private func visibleChannels(for client: IRCClient) -> [IRCChannel] {
		guard isFiltering else {
			return isExpanded(client) ? client.channelList : []
		}
		return client.channelList.filter { $0.label.localizedStandardContains(filterQuery) }
	}

	/// A server row stays while it, or a channel under it, matches the filter.
	private func isVisible(_ client: IRCClient) -> Bool {
		guard isFiltering else { return true }
		return client.label.localizedStandardContains(filterQuery)
			|| visibleChannels(for: client).isEmpty == false
	}

	public func setExpanded(_ expanded: Bool, for client: IRCClient) {
		guard client.sidebarItemIsExpanded != expanded else { return }
		client.sidebarItemIsExpanded = expanded
		rebuildRows()

		if expanded == false, selectedItem?.associatedClient === client, selectedItem !== client {
			selectedItemIdentifier = client.uniqueIdentifier
			mainWindow?.serverListSelectionDidChangeFromSwiftUI()
		}
	}

	/// The disclosure toggle, from a row that only knows the server's identity.
	func toggleExpanded(serverID: String) {
		guard let client = clients.first(where: { $0.uniqueIdentifier == serverID }) else { return }
		setExpanded(isExpanded(client) == false, for: client)
	}

	public func expandItem(_ item: Any?) {
		guard let client = (item as? IRCTreeItem)?.associatedClient else { return }
		setExpanded(true, for: client)
	}

	public func beginUpdates() {
		updateDepth += 1
	}

	public func endUpdates() {
		guard updateDepth > 0 else { return }
		updateDepth -= 1
		if updateDepth == 0, updateIsPending {
			updateIsPending = false
			rebuildRows()
		}
	}

	private func contentsChanged() {
		guard updateDepth == 0 else {
			updateIsPending = true
			return
		}
		rebuildRows()
	}

	public func addItem(toList _: UInt, inParent _: Any?) {
		contentsChanged()
	}

	public func removeItem(fromList item: Any) {
		if let item = item as? IRCTreeItem, item.uniqueIdentifier == selectedItemIdentifier {
			selectedItemIdentifier = nil
		}
		contentsChanged()
	}

	public func moveItem(at _: Int, inParent _: Any?, to _: Int, inParent _: Any?) {
		contentsChanged()
	}

	public func reloadItem(_: Any?, reloadChildren _: Bool = false) {
		contentsChanged()
	}

	public func refreshAllDrawings() {
		rebuildRows()
	}

	public func refreshDrawing(forItem _: IRCTreeItem, skipOcclusionCheck _: Bool = false) {
		rebuildRows()
	}

	public func refreshMessageCount(forItem _: IRCTreeItem, skipOcclusionCheck _: Bool = false) {
		rebuildRows()
	}

	public func applicationAppearanceChanged() {
		rebuildRows()
	}

	public func systemAppearanceChanged() {
		rebuildRows()
	}

	func menu(for identifiers: Set<String>) -> NSMenu? {
		guard let controller = AppController.shared.menuController else { return nil }
		guard let identifier = identifiers.first,
		      let item = mainWindow?.world?.findItem(withId: identifier)
		else {
			return controller.serverListNoSelectionMenu
		}

		if item.isClient {
			return controller.mainMenuServerMenuItem?.submenu
		}
		if item.isChannel {
			return controller.mainMenuChannelMenu
		}
		return controller.mainMenuQueryMenu
	}

	func move(draggedIdentifier: String, beforeIdentifier destinationIdentifier: String) -> Bool {
		guard let world = mainWindow?.world,
		      let draggedItem = world.findItem(withId: draggedIdentifier),
		      let destination = world.findItem(withId: destinationIdentifier),
		      draggedItem !== destination
		else { return false }

		if let draggedClient = draggedItem as? IRCClient,
		   let destinationClient = destination as? IRCClient,
		   let original = world.clientList.firstIndex(where: { $0 === draggedClient }),
		   let proposed = world.clientList.firstIndex(where: { $0 === destinationClient })
		{
			world.moveClient(
				from: original,
				to: ServerListReorderPolicy.destinationIndex(proposed: proposed, movingFrom: original)
			)
			return true
		}

		guard let draggedChannel = draggedItem as? IRCChannel,
		      let destinationChannel = destination as? IRCChannel,
		      let client = draggedChannel.associatedClient
		else { return false }

		let moveIsPermitted = ServerListReorderPolicy.permitsChannelMove(
			sharesClient: destinationChannel.associatedClient === client,
			draggedIsChannel: draggedChannel.isChannel,
			destinationIsChannel: destinationChannel.isChannel
		)
		guard moveIsPermitted,
		      let original = client.channelList.firstIndex(where: { $0 === draggedChannel }),
		      let proposed = client.channelList.firstIndex(where: { $0 === destinationChannel })
		else { return false }

		world.moveChannel(
			on: client,
			from: original,
			to: ServerListReorderPolicy.destinationIndex(proposed: proposed, movingFrom: original)
		)
		return true
	}
}

enum ServerListReorderPolicy {
	static func destinationIndex(proposed: Int, movingFrom original: Int) -> Int {
		proposed > original ? proposed - 1 : proposed
	}

	static func permitsChannelMove(
		sharesClient: Bool,
		draggedIsChannel: Bool,
		destinationIsChannel: Bool
	) -> Bool {
		sharesClient && draggedIsChannel == destinationIsChannel
	}
}
