// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// One walk of the chat session answers the sidebar's drawing, navigation and
/// native-node identity questions. Hidden items stay known so a filter does
/// not replace their AppKit nodes when it is cleared.
struct SidebarProjection {
	let rows: [ServerRow]
	let favoriteRows: [ConversationRow]
	let selectableItems: [ChatItem]
	let itemIndexes: [String: Int]
	let knownIdentifiers: Set<SidebarNodeID>

	static let empty = SidebarProjection(
		rows: [], favoriteRows: [], selectableItems: [], itemIndexes: [:], knownIdentifiers: [.favorites]
	)

	private init(
		rows: [ServerRow], favoriteRows: [ConversationRow], selectableItems: [ChatItem],
		itemIndexes: [String: Int], knownIdentifiers: Set<SidebarNodeID>
	) {
		self.rows = rows
		self.favoriteRows = favoriteRows
		self.selectableItems = selectableItems
		self.itemIndexes = itemIndexes
		self.knownIdentifiers = knownIdentifiers
	}

	init(
		sessions: [ServerSession], selectedItemIdentifier: String?, filter: SidebarFilter, filterText: String,
		networkIcon: (URL) -> NSImage? = { _ in nil }
	) {
		let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
		let filtering = filter != .all || query.isEmpty == false
		let tint = Self.unreadBadgeTint
		var rows: [ServerRow] = []
		var favoriteRows: [ConversationRow] = []
		var selectableItems: [ChatItem] = []
		var itemIndexes: [String: Int] = [:]
		var knownIdentifiers: Set<SidebarNodeID> = [.favorites]

		func appendSelectable(_ item: ChatItem) {
			itemIndexes[item.uniqueIdentifier] = selectableItems.count
			selectableItems.append(item)
		}

		let hierarchy = BouncerHierarchy(sessions: sessions)

		/*  One connection's rows, with its networks nested inside. A connection
		 whose bouncer row is hidden gives its networks to the level it was on. */
		func rowsFor(_ session: ServerSession, isDisclosed: Bool) -> [ServerRow] {
			let networks = hierarchy.children(of: session)
			let isHidden = session.config.bouncerHidesParent && networks.isEmpty == false
			let isShown = isDisclosed || filtering || session.uniqueIdentifier == selectedItemIdentifier
			knownIdentifiers.insert(.server(session.uniqueIdentifier))
			if isShown, isHidden == false {
				appendSelectable(session)
			}
			var listed: [ConversationRow] = []
			for conversation in session.conversationList {
				knownIdentifiers.insert(.conversation(conversation.uniqueIdentifier))
				if conversation.config.isFavorite {
					knownIdentifiers.insert(.favorite(conversation.uniqueIdentifier))
				}
				let matches = !filtering || (
					(query.isEmpty || conversation.label.localizedStandardContains(query))
						&& filter.matches(conversation)
				)
				let isDrawn = isHidden == false
					&& ((session.sidebarItemIsExpanded && isShown) || (filtering && matches))
				if isDrawn || conversation.config.isFavorite
					|| conversation.uniqueIdentifier == selectedItemIdentifier
				{
					appendSelectable(conversation)
				}
				guard matches, isHidden == false || conversation.config.isFavorite else { continue }
				let row = Self.conversationRow(conversation, unreadBadgeTint: tint)
				if isHidden == false {
					listed.append(row)
				}
				if conversation.config.isFavorite {
					var favorite = row
					favorite.networkTitle = session.label
					favorite.networkIdentityStyle = session.config.sidebarIdentity
					favoriteRows.append(favorite)
				}
			}
			let networkRows = networks.flatMap {
				rowsFor($0, isDisclosed: isHidden || (isShown && session.sidebarItemIsExpanded))
			}
			guard isHidden == false else { return networkRows }
			let visible = !filtering
				|| (filter == .all && session.label.localizedStandardContains(query))
				|| listed.isEmpty == false || networkRows.isEmpty == false
			guard visible else { return [] }
			return [ServerRow(
				id: session.uniqueIdentifier,
				title: session.label,
				isActive: session.isActive,
				isSecured: session.isSecured,
				isExpanded: filtering || session.sidebarItemIsExpanded,
				showsDisclosure: listed.isEmpty == false || networkRows.isEmpty == false,
				conversations: listed,
				networks: networkRows,
				bouncerStatus: Self.bouncerStatus(of: session),
				identityStyle: session.config.sidebarIdentity,
				networkIcon: session.supportInfo.networkIconURL.flatMap(networkIcon)
			)]
		}

		for root in hierarchy.roots {
			rows.append(contentsOf: rowsFor(root, isDisclosed: true))
		}
		self.rows = rows
		self.favoriteRows = favoriteRows
		self.selectableItems = selectableItems
		self.itemIndexes = itemIndexes
		self.knownIdentifiers = knownIdentifiers
	}

	/// What a network connection shows under its name: nothing while it is up.
	private static func bouncerStatus(of session: ServerSession) -> BouncerNetworkStatus? {
		guard let binding = session.config.bouncerNetwork else { return nil }
		if binding.isRemoved {
			return .removed
		}
		if let error = session.bouncer.networkError {
			return .failed(error)
		}
		switch session.bouncer.networkState {
		case .connecting: return .connecting
		case .disconnected: return .disconnected
		case .connected, nil: return nil
		}
	}

	private static var unreadBadgeTint: NSColor? {
		guard let color = GlasstualUserDefaults.container
			.storedColor(for: SettingsKeys.Badges.sidebarUnreadHighlight), color.alphaComponent > 0
		else { return nil }
		return color
	}

	private static func conversationRow(_ conversation: Conversation, unreadBadgeTint: NSColor?) -> ConversationRow {
		let kind = ConversationRow.Kind(conversation)
		return ConversationRow(
			id: conversation.uniqueIdentifier,
			title: conversation.label,
			kind: kind,
			isActive: conversation.isActive,
			hasJoinError: conversation.errorOnLastJoinAttempt,
			unreadCount: conversation.unreadCount,
			showsUnreadCount: conversation.config.showsUnreadCount,
			highlightCount: conversation.config.ignoreHighlights ? 0 : conversation.nicknameHighlightCount,
			unreadBadgeTint: unreadBadgeTint,
			isFavorite: conversation.config.isFavorite
		)
	}
}
