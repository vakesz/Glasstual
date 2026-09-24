// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

/// Selection, expansion and ordering state for the server sidebar.
///
/// The chat session remains the source of truth for servers and conversations.
/// This model derives `rows` from it — value snapshots the view draws without
/// touching the live objects — and owns only presentation state, which keeps the
/// view independent of protocol mutation details.
@MainActor
@Observable
final class Sidebar {
	private(set) var selectedItemIdentifier: String?
	/// One value projection supplies drawing, navigation and native-node identity.
	/// Publishing it once keeps those answers on the same chat-session snapshot.
	private(set) var projection = SidebarProjection.empty
	var rows: [ServerRow] {
		projection.rows
	}

	var favoriteRows: [ConversationRow] {
		projection.favoriteRows
	}

	var favoritesExpanded = true {
		didSet { rebuildRows() }
	}

	var filter: SidebarFilter = .all {
		didSet { rebuildRows() }
	}

	/// What the sidebar's search field holds. While it is non-empty the list
	/// shows every conversation whose name contains it, under its server, whether
	/// or not that server is disclosed.
	var filterText = "" {
		didSet { rebuildRows() }
	}

	@ObservationIgnored weak var mainWindow: MainWindow?
	/** Where the servers come from.

	 The window's chat session, once one is attached. Holding it as a source rather
	 than reaching through the window on every read is what lets the projections
	 below be exercised against a chat session that was built rather than connected
	 to: the live one is the application's, and a test that filled it would be
	 editing the reader's own conversations. One source, because the list of
	 servers is the chat session's own: a second closure handing back a list could
	 disagree with the session the moves are performed against. */
	@ObservationIgnored var chatSessionSource: @MainActor () -> ChatSession? = { nil }

	/// Inbound changes publish on the next actor turn. Commands in the current
	/// turn still need a fresh index space, so they may build this unpublished
	/// projection once. The next published rebuild uses the latest source state.
	@ObservationIgnored private var pendingProjection: SidebarProjection?

	/// Bookkeeping for the coalescing below, and nothing the view draws: observed
	/// it would mark the model changed on every inbound burst -- a list update
	/// per counter write, published from wherever the burst arrived.
	@ObservationIgnored private var updateDepth = 0
	@ObservationIgnored private var updateIsPending = false
	@ObservationIgnored private var refreshTask: Task<Void, Never>?

	init() {}

	/** No rows are built here: the window attaches before the chat session
	 exists, and its first conversation is what fills them. */
	func attach(to window: MainWindow) {
		precondition(mainWindow == nil || mainWindow === window)
		mainWindow = window
		chatSessionSource = { [weak window] in window?.chatSession }
	}

	// MARK: - Rows

	/// Publishes the latest value projection; the native outline coalesces its
	/// own rendering and never writes presentation transactions into this model.
	private func rebuildRows() {
		pendingProjection = nil
		updateIsPending = false
		projection = SidebarProjection(
			sessions: sessions, selectedItemIdentifier: selectedItemIdentifier,
			filter: filter, filterText: filterText
		)
	}

	func toggleFavorite(_ conversation: Conversation) {
		guard conversation.isChannel || conversation.isDirect,
		      item(withID: conversation.uniqueIdentifier) === conversation else { return }
		var config = conversation.config
		config.isFavorite.toggle()
		conversation.updateConfig(config)
		rebuildRows()
	}

	var sessions: [ServerSession] {
		chatSession?.sessions ?? []
	}

	private var chatSession: ChatSession? {
		chatSessionSource()
	}

	/// The row one identifier names, for a view that has an identifier and needs
	/// the item behind it.
	func item(withID identifier: String) -> ChatItem? {
		chatSession?.findItem(withId: identifier)
	}

	/** The index space every selection command addresses.

	 Not what the filter leaves on screen. The filter is a way of looking at the
	 sidebar, not a way of closing conversations: a chat session that asks for a
	 conversation to be selected, and `adjustSelection` checking that the open one
	 still exists, both have to find an item the reader has typed out of sight,
	 or typing in the search field switches the transcript. What does narrow it
	 is disclosure, because a conversation under a collapsed server has no row to
	 arrow onto — and `select(_:)` discloses the server before it asks.

	 A filter overrides the disclosure it draws with: `rebuildRows` opens every
	 matching server whether the reader left it open or not, so those
	 conversations do have rows. Leaving them out meant clicking one answered `selectedRow`
	 with -1, and ⌥↑/⌥↓ walked from a row that was not in the list. Whatever is
	 drawn is selectable; nothing that is drawn is left out. */
	var selectableItems: [ChatItem] {
		currentProjection.selectableItems
	}

	private var currentProjection: SidebarProjection {
		guard updateIsPending else { return projection }
		if let pendingProjection {
			return pendingProjection
		}
		let current = SidebarProjection(
			sessions: sessions, selectedItemIdentifier: selectedItemIdentifier,
			filter: filter, filterText: filterText
		)
		pendingProjection = current
		return current
	}

	var selectedRow: Int {
		guard let selectedItemIdentifier else { return -1 }
		return currentProjection.itemIndexes[selectedItemIdentifier] ?? -1
	}

	var selectedItem: ChatItem? {
		guard let selectedItemIdentifier else { return nil }
		return chatSession?.findItem(withId: selectedItemIdentifier)
	}

	var groupItems: [ChatItem] {
		sessions
	}

	func row(forItem item: ChatItem?) -> Int {
		guard let item else { return -1 }
		let current = currentProjection
		guard let index = current.itemIndexes[item.uniqueIdentifier], current.selectableItems[index] === item
		else { return -1 }
		return index
	}

	/// Selects `item`, if it is one of the rows the sidebar is showing.
	func select(_ item: ChatItem?) {
		guard let item, row(forItem: item) >= 0 else { return }
		selectedItemIdentifier = item.uniqueIdentifier
	}

	func selectFromView(_ identifier: String?) {
		guard selectedItemIdentifier != identifier else { return }
		selectedItemIdentifier = identifier
		mainWindow?.sidebarSelectionDidChangeFromView()
	}

	func items(inContainingGroupOf item: ChatItem) -> [ChatItem]? {
		guard let session = item.associatedSession else { return nil }
		return session.conversationList
	}

	/// Whether the server's conversations are disclosed. `setExpanded` is the
	/// only writer and publishes a new projection with the changed disclosure.
	func isExpanded(_ session: ServerSession) -> Bool {
		session.sidebarItemIsExpanded
	}

	var isFiltering: Bool {
		filter != .all || filterQuery.isEmpty == false
	}

	/// A filter that matches nobody, which the list answers with a no-results
	/// view rather than an empty sidebar that looks like a lost account.
	var hasNoFilterMatches: Bool {
		isFiltering && rows.isEmpty
	}

	private var filterQuery: String {
		filterText.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// Expansion belongs to the chat session so it survives relaunch. Collapsing
	/// the selected conversation's parent selects that server's console.
	func setExpanded(_ expanded: Bool, for session: ServerSession) {
		guard session.sidebarItemIsExpanded != expanded else { return }
		session.sidebarItemIsExpanded = expanded
		let selectServer = expanded == false && selectedItem?.associatedSession === session && selectedItem !== session
			&& (selectedItem as? Conversation)?.config.isFavorite != true
		if selectServer {
			selectedItemIdentifier = session.uniqueIdentifier
		}
		rebuildRows()
		if selectServer {
			mainWindow?.sidebarSelectionDidChangeFromView()
		}
	}

	/// The disclosure toggle, from a row that only knows the server's identity.
	/// Filtering temporarily owns disclosure and leaves the saved choice intact.
	func setExpanded(_ expanded: Bool, forServerID serverID: String) {
		/* A filter draws every match, disclosed or not, so the chevron it leaves
		 open is not describing the server's own state and closing it would only
		 fight the filter. The state the reader set stands once the field is
		 cleared. */
		guard isFiltering == false,
		      let session = sessions.first(where: { $0.uniqueIdentifier == serverID })
		else { return }
		setExpanded(expanded, for: session)
	}

	func expandItem(_ item: ChatItem?) {
		guard let session = item?.associatedSession else { return }
		setExpanded(true, for: session)
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
		pendingProjection = nil
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

	/** Something in the chat session changed: rebuild the rows from it.

	 The rows are values derived from the chat session, so what changed does not
	 matter -- there is one answer and it is recomputed whole. This replaced
	 seven entry points that carried insertion indices, parents and occlusion
	 flags between them, every one of them ignoring its arguments while the
	 callers still computed them. */
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
		rebuildRows()
	}

	/** Reorders the servers.

	 Not while the sidebar is filtered: the rows on screen are then a different
	 list from the one the chat session holds, and an index into them means nothing to
	 it. The order the reader set stands once the field is cleared. */
	@discardableResult
	func moveServers(fromOffsets offsets: IndexSet, toOffset destination: Int) -> Bool {
		guard isFiltering == false,
		      let chatSession,
		      let move = SidebarReorderPolicy.move(fromOffsets: offsets, toOffset: destination),
		      chatSession.sessions.indices.contains(move.from)
		else { return false }

		chatSession.moveSession(from: move.from, to: move.to)
		return true
	}

	/// Reorders one server's conversations. Channels and one-to-one
	/// conversations are two lists drawn as one, and neither moves into the
	/// other.
	@discardableResult
	func moveConversations(onServerWithID serverID: String, fromOffsets offsets: IndexSet, toOffset destination: Int)
		-> Bool
	{
		guard isFiltering == false,
		      let chatSession,
		      let session = sessions.first(where: { $0.uniqueIdentifier == serverID }),
		      let move = SidebarReorderPolicy.move(fromOffsets: offsets, toOffset: destination),
		      session.conversationList.indices.contains(move.from),
		      session.conversationList.indices.contains(move.to)
		else { return false }

		guard SidebarReorderPolicy.permitsMove(
			draggedIsChannel: session.conversationList[move.from].isChannel,
			destinationIsChannel: session.conversationList[move.to].isChannel
		) else { return false }

		chatSession.moveConversation(on: session, from: move.from, to: move.to)
		return true
	}
}

// MARK: - Reordering

/// Where a dragged row came from and where it is to end up, as indices into the
/// list it moves within.
nonisolated struct SidebarRowMove: Equatable {
	let from: Int
	let to: Int
}

nonisolated enum SidebarReorderPolicy {
	/** The move a drag asks for, as `ChatSession` performs it.

	 A list names the place a row is being inserted *before*, counted in the
	 order the rows are in now. `ChatSession` takes the row out before putting it
	 back, so a destination past the row's own place has already shifted up by
	 one; not correcting for that left the last position unreachable.

	 The sidebar carries one selected row at a time, so one row is what a drag
	 can be carrying. */
	static func move(fromOffsets offsets: IndexSet, toOffset destination: Int) -> SidebarRowMove? {
		guard offsets.count == 1, let from = offsets.first else { return nil }

		let to = destination > from ? destination - 1 : destination
		guard to != from, to >= 0 else { return nil }
		return SidebarRowMove(from: from, to: to)
	}

	/// Channels and one-to-one conversations are two lists drawn as one, and a
	/// row does not move out of the one it belongs to.
	static func permitsMove(draggedIsChannel: Bool, destinationIsChannel: Bool) -> Bool {
		draggedIsChannel == destinationIsChannel
	}
}
