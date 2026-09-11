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
	/// Set for the length of a disclosure toggle, the one rebuild that animates.
	@ObservationIgnored private var isTogglingDisclosure = false
	/** Where the servers come from.

	 The window's world, once one is attached. Holding it as a source rather
	 than reaching through the window on every read is what lets the projections
	 below be exercised against a tree that was built rather than connected to:
	 the world itself is the application's, and a test that filled it would be
	 editing the reader's own conversations. */
	@ObservationIgnored var clientSource: @MainActor () -> [IRCClient] = { [] }

	private var updateDepth = 0
	private var updateIsPending = false
	@ObservationIgnored private var refreshTask: Task<Void, Never>?

	public init() {}

	/** No rows are built here: the window attaches before the world exists, and
	 the world's first `addItem` is what fills them. */
	func attach(to window: MainWindow) {
		precondition(mainWindow == nil || mainWindow === window)
		mainWindow = window
		clientSource = { [weak window] in window?.world?.clientList ?? [] }
	}

	// MARK: - Rows

	/** Rebuilds what the list draws.

	 Without animation, unless a disclosure toggle asked for it: the sidebar's
	 table applies the selection to a row only once that row materialises, and
	 an animated insert or replace beside the selected row left that row's
	 outgoing copy drawn under the incoming one, a ghost label with a stale
	 highlight. The chevron's own open and close animation is the one the
	 reader expects, so a disclosure toggle keeps it. */
	private func rebuildRows() {
		guard isTogglingDisclosure == false else {
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
	private var unreadBadgeTint: Color? {
		guard let color = TextualUserDefaults.container
			.storedColor(for: Preferences.Badges.serverListUnreadHighlight),
			color.alphaComponent > 0
		else {
			return nil
		}

		return Color(nsColor: color)
	}

	private func channelRow(_ channel: IRCChannel, unreadBadgeTint: Color?) -> ChannelRow {
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

	public var clients: [IRCClient] {
		clientSource()
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
	private var selectableItems: [IRCTreeItem] {
		clients.flatMap { client -> [IRCTreeItem] in
			if isExpanded(client) {
				return [client] + client.channelList
			}
			return [client] + (isFiltering ? listedChannels(for: client) : [])
		}
	}

	public var numberOfRows: Int {
		selectableItems.count
	}

	public var selectedRow: Int {
		guard let selectedItemIdentifier else { return -1 }
		return selectableItems.firstIndex { $0.uniqueIdentifier == selectedItemIdentifier } ?? -1
	}

	public var selectedItem: IRCTreeItem? {
		guard let selectedItemIdentifier else { return nil }
		return mainWindow?.world?.findItem(withId: selectedItemIdentifier)
	}

	public var groupItems: [IRCTreeItem] {
		clients
	}

	public func item(atRow row: Int) -> Any? {
		selectableItems.indices.contains(row) ? selectableItems[row] : nil
	}

	public func row(forItem item: Any?) -> Int {
		guard let item = item as? IRCTreeItem else { return -1 }
		return selectableItems.firstIndex { $0 === item } ?? -1
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
	private func listedChannels(for client: IRCClient) -> [IRCChannel] {
		guard isFiltering else { return client.channelList }
		return client.channelList.filter { $0.label.localizedStandardContains(filterQuery) }
	}

	/// A server row stays while it, or a channel under it, matches the filter.
	private func isVisible(_ client: IRCClient) -> Bool {
		guard isFiltering else { return true }
		return client.label.localizedStandardContains(filterQuery)
			|| listedChannels(for: client).isEmpty == false
	}

	public func setExpanded(_ expanded: Bool, for client: IRCClient) {
		guard client.sidebarItemIsExpanded != expanded else { return }
		client.sidebarItemIsExpanded = expanded
		isTogglingDisclosure = true
		defer { isTogglingDisclosure = false }
		rebuildRows()

		if expanded == false, selectedItem?.associatedClient === client, selectedItem !== client {
			selectedItemIdentifier = client.uniqueIdentifier
			mainWindow?.serverListSelectionDidChangeFromSwiftUI()
		}
	}

	/// The disclosure toggle, from a row that only knows the server's identity.
	func setExpanded(_ expanded: Bool, forServerID serverID: String) {
		/* A filter draws every match, disclosed or not, so the chevron it leaves
		 open is not describing the server's own state and closing it would only
		 fight the filter. The state the reader set stands once the field is
		 cleared. */
		guard isFiltering == false,
		      let client = clients.first(where: { $0.uniqueIdentifier == serverID })
		else { return }
		setExpanded(expanded, for: client)
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
		contentsChanged()
	}

	public func refreshDrawing(forItem _: IRCTreeItem, skipOcclusionCheck _: Bool = false) {
		contentsChanged()
	}

	public func refreshMessageCount(forItem _: IRCTreeItem, skipOcclusionCheck _: Bool = false) {
		contentsChanged()
	}

	public func applicationAppearanceChanged() {
		rebuildRows()
	}

	public func systemAppearanceChanged() {
		rebuildRows()
	}

	func menu(for identifiers: Set<String>) -> (menu: NSMenu, context: AppMenuContext)? {
		guard let controller = AppController.shared.menuController else { return nil }
		let item = identifiers.first.flatMap { mainWindow?.world?.findItem(withId: $0) }
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

	/// A row was dropped on `destinationIdentifier`, which means the dragged
	/// conversation is to take that row's place.
	func move(draggedIdentifier: String, ontoIdentifier destinationIdentifier: String) -> Bool {
		guard let world = mainWindow?.world,
		      let draggedItem = world.findItem(withId: draggedIdentifier),
		      let destination = world.findItem(withId: destinationIdentifier),
		      draggedItem !== destination
		else { return false }

		if draggedItem is IRCClient, destination is IRCClient {
			guard let move = ServerListReorderPolicy.move(
				in: world.clientList.map(\.uniqueIdentifier),
				dragging: draggedIdentifier,
				onto: destinationIdentifier
			) else { return false }
			world.moveClient(from: move.from, to: move.to)
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
		      let move = ServerListReorderPolicy.move(
		      	in: client.channelList.map(\.uniqueIdentifier),
		      	dragging: draggedIdentifier,
		      	onto: destinationIdentifier
		      )
		else { return false }

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
	/** The move a drop asks for.

	 The whole row is the target — there is no insertion line between rows to
	 aim at — so a drop means "put this where that one is", and the row that was
	 there gives way. `IRCWorld` takes the dragged item out before putting it
	 back, which has already shifted a destination below it up by one; correcting
	 for that as well was what made dragging onto the row below a no-op and left
	 the last position in the list unreachable. */
	static func move(in identifiers: [String], dragging draggedID: String, onto destinationID: String)
		-> ServerListRowMove?
	{
		guard let from = identifiers.firstIndex(of: draggedID),
		      let to = identifiers.firstIndex(of: destinationID),
		      from != to
		else { return nil }
		return ServerListRowMove(from: from, to: to)
	}

	static func permitsChannelMove(
		sharesClient: Bool,
		draggedIsChannel: Bool,
		destinationIsChannel: Bool
	) -> Bool {
		sharesClient && draggedIsChannel == destinationIsChannel
	}
}
