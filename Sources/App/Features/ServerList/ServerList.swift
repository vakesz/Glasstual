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
import SwiftUI

/// Selection, expansion and ordering state for the SwiftUI server sidebar.
///
/// The IRC world remains the source of truth for clients and channels. This
/// model derives `rows` from it — value snapshots the view draws without
/// touching the tree — and owns only presentation state, which keeps the view
/// independent of protocol mutation details.
@MainActor
@Observable
final class ServerList {
	private(set) var selectedItemIdentifier: String?
	/// What the view draws. Rebuilt whenever the tree reports a change, so a
	/// row is never asked to notice one on its own.
	private(set) var rows: [ServerRow] = []
	/// What the sidebar's search field holds. While it is non-empty the list
	/// shows every channel whose name contains it, under its server, whether or
	/// not that server is disclosed.
	var filterText = "" {
		didSet {
			selectableItemsStorage = nil
			rebuildRows()
		}
	}

	@ObservationIgnored weak var mainWindow: MainWindow?
	/** Where the servers come from.

	 The window's world, once one is attached. Holding it as a source rather
	 than reaching through the window on every read is what lets the projections
	 below be exercised against a tree that was built rather than connected to:
	 the world itself is the application's, and a test that filled it would be
	 editing the reader's own conversations. */
	@ObservationIgnored var clientSource: @MainActor () -> [Client] = { [] }
	/// The world those servers live in, held as a source for the same reason:
	/// reordering is answered here rather than reached for through the window.
	@ObservationIgnored var worldSource: @MainActor () -> ClientDirectory? = { nil }

	/** The index space, resolved once per change rather than per question.

	 Selecting an item asks for its row, the replacement search walks every
	 row, and channel navigation rotates the whole list, so one command used to
	 flatten the tree a dozen times. The list is dropped whenever anything it
	 is derived from changes -- and dropped rather than rebuilt, because a
	 change arrives before the rows are rebuilt and the answer has to be
	 current for the selection that follows it in the same turn. */
	@ObservationIgnored private var selectableItemsStorage: [ChatItem]?

	/// Bookkeeping for the coalescing below, and nothing the view draws: observed
	/// it would mark the model changed on every inbound burst -- a list update
	/// per counter write, published from wherever the burst arrived.
	@ObservationIgnored private var updateDepth = 0
	@ObservationIgnored private var updateIsPending = false
	@ObservationIgnored private var refreshTask: Task<Void, Never>?

	init() {}

	/** No rows are built here: the window attaches before the world exists, and
	 the world's first `addItem` is what fills them. */
	func attach(to window: MainWindow) {
		precondition(mainWindow == nil || mainWindow === window)
		mainWindow = window
		clientSource = { [weak window] in window?.world?.clientList ?? [] }
		worldSource = { [weak window] in window?.world }
	}

	// MARK: - Rows

	/** Rebuilds what the list draws.

	 Every rebuild publishes under a transaction of its own naming, and they all
	 name the same one unless the reader worked the chevron. Two rows values
	 published in one turn under *different* transactions are two list updates
	 rather than one, and the outline begins the second while it is still
	 applying the first -- a reentrant operation in its own table delegate,
	 which AppKit warns about on every launch and says it will assert on. That
	 is what happened here: the world published its first rows without
	 animation, and the saved expansion followed in the same turn through a
	 path that left the transaction to whatever was ambient.

	 Without animation, because the sidebar's table applies the selection to a
	 row only once that row materialises, and an animated insert or replace
	 beside the selected row left that row's outgoing copy drawn under the
	 incoming one, a ghost label with a stale highlight. The chevron's own open
	 and close animation is the one the reader expects, so the one rebuild the
	 reader asked for by working it keeps the ambient transaction instead. */
	private func rebuildRows(animated: Bool = false) {
		selectableItemsStorage = builtSelectableItems()
		guard animated == false else {
			rows = builtRows()
			return
		}
		withTransaction(Transaction(animation: nil)) {
			rows = builtRows()
		}
	}

	private func builtRows() -> [ServerRow] {
		let tint = unreadBadgeTint
		return clients.filter(isVisible).map { client in
			let channels = listedChannels(for: client)
			return ServerRow(
				id: client.uniqueIdentifier,
				title: client.label,
				isActive: client.isActive,
				isSecured: client.isSecured,
				isExpanded: isFiltering || isExpanded(client),
				/* An outline offers disclosure where there is something to
					disclose. A server with no conversations under it gets a plain
					row rather than a chevron that would open onto nothing. */
				showsDisclosure: channels.isEmpty == false,
				channels: channels.map { channelRow($0, unreadBadgeTint: tint) }
			)
		}
	}

	/** The unread badge's colour, resolved while the rows are built.

	 A row draws what its value says and is compared by it, so a colour the row
	 read out of the defaults for itself was invisible to that comparison: the
	 preference changed, every row's value was unchanged, and nothing redrew. */
	private var unreadBadgeTint: NSColor? {
		guard let color = GlasstualUserDefaults.container
			.storedColor(for: Preferences.Badges.serverListUnreadHighlight),
			color.alphaComponent > 0
		else {
			return nil
		}

		return color
	}

	private func channelRow(_ channel: Channel, unreadBadgeTint: NSColor?) -> ChannelRow {
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
			highlightCount: channel.config.ignoreHighlights ? 0 : channel.nicknameHighlightCount,
			unreadBadgeTint: unreadBadgeTint
		)
	}

	var clients: [Client] {
		clientSource()
	}

	private var world: ClientDirectory? {
		worldSource()
	}

	/** The index space every selection command addresses.

	 Not what the filter leaves on screen. The filter is a way of looking at the
	 sidebar, not a way of closing conversations: a world that asks for a
	 channel to be selected, and `adjustSelection` checking that the open one
	 still exists, both have to find an item the reader has typed out of sight,
	 or typing in the search field switches the transcript. What does narrow it
	 is disclosure, because a channel under a collapsed server has no row to
	 arrow onto — and `select(_:)` discloses the server before it asks.

	 A filter overrides the disclosure it draws with: `rebuildRows` opens every
	 matching server whether the reader left it open or not, so those channels
	 do have rows. Leaving them out meant clicking one answered `selectedRow`
	 with -1, and ⌥↑/⌥↓ walked from a row that was not in the list. Whatever is
	 drawn is selectable; nothing that is drawn is left out. */
	var selectableItems: [ChatItem] {
		if let selectableItemsStorage {
			return selectableItemsStorage
		}
		let items = builtSelectableItems()
		selectableItemsStorage = items
		return items
	}

	private func builtSelectableItems() -> [ChatItem] {
		clients.flatMap { client -> [ChatItem] in
			if isExpanded(client) {
				return [client] + client.channelList
			}
			return [client] + (isFiltering ? listedChannels(for: client) : [])
		}
	}

	var numberOfRows: Int {
		selectableItems.count
	}

	var selectedRow: Int {
		guard let selectedItemIdentifier else { return -1 }
		return selectableItems.firstIndex { $0.uniqueIdentifier == selectedItemIdentifier } ?? -1
	}

	var selectedItem: ChatItem? {
		guard let selectedItemIdentifier else { return nil }
		return world?.findItem(withId: selectedItemIdentifier)
	}

	var groupItems: [ChatItem] {
		clients
	}

	func item(atRow row: Int) -> Any? {
		selectableItems.indices.contains(row) ? selectableItems[row] : nil
	}

	func row(forItem item: Any?) -> Int {
		guard let item = item as? ChatItem else { return -1 }
		return selectableItems.firstIndex { $0 === item } ?? -1
	}

	/// Selects `item`, if it is one of the rows the sidebar is showing.
	func select(_ item: ChatItem?) {
		guard let item, row(forItem: item) >= 0 else { return }
		selectedItemIdentifier = item.uniqueIdentifier
	}

	func selectFromSwiftUI(_ identifier: String?) {
		guard selectedItemIdentifier != identifier else { return }
		selectedItemIdentifier = identifier
		mainWindow?.serverListSelectionDidChangeFromSwiftUI()
	}

	func items(inContainingGroupOf item: Any) -> [ChatItem]? {
		guard let item = item as? ChatItem, let client = item.associatedClient else { return nil }
		return client.channelList
	}

	/// Whether the server's conversations are disclosed. `setExpanded` is the
	/// only writer: the cached index space is dropped there, and a flag set
	/// behind the list's back would leave it holding the old rows.
	func isExpanded(_ client: Client) -> Bool {
		client.sidebarItemIsExpanded
	}

	var isFiltering: Bool {
		filterQuery.isEmpty == false
	}

	/// A filter that matches nobody, which the list answers with a no-results
	/// view rather than an empty sidebar that looks like a lost account.
	var hasNoFilterMatches: Bool {
		isFiltering && rows.isEmpty
	}

	private var filterQuery: String {
		filterText.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/** The channels listed under a server, disclosed or not.

	 Disclosure is the outline's to apply: the rows carry the whole tree so that
	 a server keeps its chevron while it is closed, and only the filter takes
	 conversations out of them. */
	private func listedChannels(for client: Client) -> [Channel] {
		guard isFiltering else { return client.channelList }
		return client.channelList.filter { $0.label.localizedStandardContains(filterQuery) }
	}

	/// A server row stays while it, or a channel under it, matches the filter.
	private func isVisible(_ client: Client) -> Bool {
		guard isFiltering else { return true }
		return client.label.localizedStandardContains(filterQuery)
			|| listedChannels(for: client).isEmpty == false
	}

	/** Discloses a server's conversations, or closes them.

	 Not animated: this is the application's own call -- the saved expansion
	 restored at launch, and the server a selection had to be disclosed to reach
	 -- and those arrive in the same turn as the rows the world has just
	 published. ``setExpanded(_:forServerID:)`` is the reader's chevron and is
	 the one that animates. */
	func setExpanded(_ expanded: Bool, for client: Client) {
		setExpanded(expanded, for: client, animated: false)
	}

	private func setExpanded(_ expanded: Bool, for client: Client, animated: Bool) {
		guard client.sidebarItemIsExpanded != expanded else { return }
		client.sidebarItemIsExpanded = expanded
		selectableItemsStorage = nil
		rebuildRows(animated: animated)

		if expanded == false, selectedItem?.associatedClient === client, selectedItem !== client {
			selectedItemIdentifier = client.uniqueIdentifier
			mainWindow?.serverListSelectionDidChangeFromSwiftUI()
		}
	}

	/// The disclosure toggle, from a row that only knows the server's identity.
	/// The reader worked the chevron, so this is the rebuild that animates.
	func setExpanded(_ expanded: Bool, forServerID serverID: String) {
		/* A filter draws every match, disclosed or not, so the chevron it leaves
		 open is not describing the server's own state and closing it would only
		 fight the filter. The state the reader set stands once the field is
		 cleared. */
		guard isFiltering == false,
		      let client = clients.first(where: { $0.uniqueIdentifier == serverID })
		else { return }
		setExpanded(expanded, for: client, animated: true)
	}

	func expandItem(_ item: Any?) {
		guard let client = (item as? ChatItem)?.associatedClient else { return }
		setExpanded(true, for: client)
	}

	func beginUpdates() {
		updateDepth += 1
	}

	func endUpdates() {
		guard updateDepth > 0 else { return }
		updateDepth -= 1
		if updateDepth == 0, updateIsPending {
			updateIsPending = false
			rebuildRows()
		}
	}

	private func contentsChanged() {
		selectableItemsStorage = nil
		updateIsPending = true
		guard updateDepth == 0, refreshTask == nil else { return }
		// Inbound bursts can invalidate the same rows several times before the
		// next actor turn. Publish one snapshot of their final state.
		refreshTask = Task { [weak self] in
			guard let self else { return }
			refreshTask = nil
			guard updateDepth == 0, updateIsPending else { return }
			updateIsPending = false
			rebuildRows()
		}
	}

	/** Something about the tree changed: rebuild the rows from it.

	 The rows are values derived from the world, so what changed does not
	 matter -- there is one answer and it is recomputed whole. This used to be
	 seven entry points carrying insertion indices, parents and occlusion
	 flags from the outline view the sidebar no longer is, every one of them
	 ignoring its arguments while the callers still computed them. */
	func setNeedsRefresh() {
		contentsChanged()
	}

	/// The same, for an item that is going away: it cannot stay selected.
	func itemWasRemoved(_ item: ChatItem) {
		if item.uniqueIdentifier == selectedItemIdentifier {
			selectedItemIdentifier = nil
		}
		contentsChanged()
	}

	/// A new appearance changes what the rows draw, so they are rebuilt at
	/// once rather than coalesced with the next inbound burst.
	func applicationAppearanceChanged() {
		selectableItemsStorage = nil
		rebuildRows()
	}

	func menu(for identifiers: Set<String>) -> (menu: NSMenu, context: AppMenuContext)? {
		guard let controller = AppServices.delegate.menuController else { return nil }
		let item = identifiers.first.flatMap { world?.findItem(withId: $0) }
		let menu: NSMenu? = if let item {
			if item.isClient {
				controller.mainMenuServerMenuItem?.submenu
			} else {
				item.isChannel ? controller.mainMenuChannelMenu : controller.mainMenuQueryMenu
			}
		} else {
			controller.serverListNoSelectionMenu
		}
		guard let menu else { return nil }
		return (menu, AppMenuContext(coordinator: controller.actionCoordinator, item: item))
	}

	/** Reorders the servers.

	 Not while the sidebar is filtered: the rows on screen are then a different
	 list from the one the world holds, and an index into them means nothing to
	 it. The order the reader set stands once the field is cleared. */
	@discardableResult
	func moveServers(fromOffsets offsets: IndexSet, toOffset destination: Int) -> Bool {
		guard isFiltering == false,
		      let world,
		      let move = ServerListReorderPolicy.move(fromOffsets: offsets, toOffset: destination),
		      world.clientList.indices.contains(move.from)
		else { return false }

		world.moveClient(from: move.from, to: move.to)
		return true
	}

	/// Reorders one server's conversations. Channels and one-to-one
	/// conversations are two lists drawn as one, and neither moves into the
	/// other.
	@discardableResult
	func moveChannels(onServerWithID serverID: String, fromOffsets offsets: IndexSet, toOffset destination: Int)
		-> Bool
	{
		guard isFiltering == false,
		      let world,
		      let client = clients.first(where: { $0.uniqueIdentifier == serverID }),
		      let move = ServerListReorderPolicy.move(fromOffsets: offsets, toOffset: destination),
		      client.channelList.indices.contains(move.from),
		      client.channelList.indices.contains(move.to)
		else { return false }

		guard ServerListReorderPolicy.permitsChannelMove(
			draggedIsChannel: client.channelList[move.from].isChannel,
			destinationIsChannel: client.channelList[move.to].isChannel
		) else { return false }

		world.moveChannel(on: client, from: move.from, to: move.to)
		return true
	}
}

/// Where a dragged row came from and where it is to end up, as indices into the
/// list it moves within.
nonisolated struct ServerListRowMove: Equatable { // nonisolated: value
	let from: Int
	let to: Int
}

nonisolated enum ServerListReorderPolicy { // nonisolated: value
	/** The move a drag asks for, as `ClientDirectory` performs it.

	 A list names the place a row is being inserted *before*, counted in the
	 order the rows are in now. `ClientDirectory` takes the row out before putting it
	 back, so a destination past the row's own place has already shifted up by
	 one; not correcting for that left the last position unreachable.

	 The sidebar carries one selected row at a time, so one row is what a drag
	 can be carrying. */
	static func move(fromOffsets offsets: IndexSet, toOffset destination: Int) -> ServerListRowMove? {
		guard offsets.count == 1, let from = offsets.first else { return nil }

		let to = destination > from ? destination - 1 : destination
		guard to != from, to >= 0 else { return nil }
		return ServerListRowMove(from: from, to: to)
	}

	/// Channels and one-to-one conversations are two lists drawn as one, and a
	/// row does not move out of the one it belongs to.
	static func permitsChannelMove(draggedIsChannel: Bool, destinationIsChannel: Bool) -> Bool {
		draggedIsChannel == destinationIsChannel
	}
}
