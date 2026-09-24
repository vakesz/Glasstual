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
		sessions: [ServerSession], selectedItemIdentifier: String?, filter: SidebarFilter, filterText: String
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

		for session in sessions {
			knownIdentifiers.insert(.server(session.uniqueIdentifier))
			appendSelectable(session)
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
				if session.sidebarItemIsExpanded || conversation.config.isFavorite
					|| conversation.uniqueIdentifier == selectedItemIdentifier || (filtering && matches)
				{
					appendSelectable(conversation)
				}
				guard matches else { continue }
				let row = Self.conversationRow(conversation, unreadBadgeTint: tint)
				listed.append(row)
				if conversation.config.isFavorite {
					var favorite = row
					favorite.networkTitle = session.label
					favorite.networkIdentityStyle = session.config.sidebarIdentity
					favoriteRows.append(favorite)
				}
			}
			let visible = !filtering
				|| (filter == .all && session.label.localizedStandardContains(query))
				|| listed.isEmpty == false
			guard visible else { continue }
			rows.append(ServerRow(
				id: session.uniqueIdentifier,
				title: session.label,
				isActive: session.isActive,
				isSecured: session.isSecured,
				isExpanded: filtering || session.sidebarItemIsExpanded,
				showsDisclosure: listed.isEmpty == false,
				conversations: listed,
				identityStyle: session.config.sidebarIdentity
			))
		}
		self.rows = rows
		self.favoriteRows = favoriteRows
		self.selectableItems = selectableItems
		self.itemIndexes = itemIndexes
		self.knownIdentifiers = knownIdentifiers
	}

	private static var unreadBadgeTint: NSColor? {
		guard let color = GlasstualUserDefaults.container
			.storedColor(for: SettingsKeys.Badges.sidebarUnreadHighlight), color.alphaComponent > 0
		else { return nil }
		return color
	}

	private static func conversationRow(_ conversation: Conversation, unreadBadgeTint: NSColor?) -> ConversationRow {
		let kind: ConversationRow.Kind = if conversation.isChannel {
			.channel
		} else if conversation.isDirectChat {
			.directChat
		} else if conversation.isConsole {
			.console
		} else {
			.direct
		}
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
