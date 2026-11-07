// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// One server in the sidebar, with the conversations drawn beneath it.
///
/// A snapshot: what it describes lives on `NSObject`s that change while
/// the outline draws them, so the list publishes values instead and rebuilds them when
/// the chat session says something changed. A row is a plain function of its
/// value.
struct ServerRow: Identifiable, Equatable {
	let id: String
	let title: String
	let isActive: Bool
	let isSecured: Bool
	/// What is drawn beneath the row, not what the user disclosed: a filter
	/// shows matching conversations under a collapsed server too.
	let isExpanded: Bool
	/// Whether the row is an outline group at all. A server with nothing under
	/// it is a plain row: a chevron that opened onto an empty list would be
	/// offering something the sidebar does not have.
	let showsDisclosure: Bool
	/// Every conversation under the server, disclosed or not — the outline hides
	/// what is closed. A filter is the one thing that takes rows out of this.
	let conversations: [ConversationRow]
	var isFavoritesGroup = false
	/// The bouncer networks nested under this connection, each a row of its own.
	var networks: [ServerRow] = []
	/// What the bouncer says of a network connection, when it is not simply up.
	var bouncerStatus: BouncerNetworkStatus?
	var identityStyle = ServerIdentityStyle()
	/// The icon the network advertises, drawn in place of the identity glyph
	/// once it has been fetched. Decorative: the row's label is its name.
	var networkIcon: NSImage?
}

/// How a bouncer network is doing when that is worth a line under its name.
enum BouncerNetworkStatus: Equatable {
	case connecting
	case disconnected
	/// The bouncer could not reach the upstream server; the reason is its own text.
	case failed(String)
	/// The bouncer no longer lists the network; its history is still readable.
	case removed
}

/// One conversation in the sidebar.
struct ConversationRow: Identifiable, Equatable {
	enum Kind: Equatable {
		case channel
		case direct
		case directChat
		case console
	}

	let id: String
	let title: String
	let kind: Kind
	let isActive: Bool
	let hasJoinError: Bool
	let unreadCount: Int
	let showsUnreadCount: Bool
	let highlightCount: Int
	/// The colour the user chose for a badge that asks for attention, resolved
	/// where the rows are built. A row is compared by what it draws, so a
	/// colour it went and read for itself would change nothing here and the
	/// list would keep the badges it already had.
	let unreadBadgeTint: NSColor?
	var isFavorite = false
	/// Present only in Favorites, where conversations from several networks share one group.
	var networkTitle: String?
	var networkIdentityStyle: ServerIdentityStyle?

	/// Asks for attention: a channel where the nickname was said, or a
	/// conversation with one person that has anything unread — every line of a
	/// direct message is addressed to the reader.
	var isEmphasized: Bool {
		if highlightCount > 0 {
			return true
		}
		return (kind == .direct || kind == .directChat) && unreadCount > 0
	}

	var showsUnreadBadge: Bool {
		showsUnreadCount && unreadCount > 0
	}
}

extension ConversationRow.Kind {
	/** The glyph that names this kind of conversation, wherever one is listed.

	 The sidebar leaves a channel's glyph out, because a channel is what most
	 rows are and the pin already marks the ones that matter; a list that holds
	 channels beside people, as the switcher does, needs it drawn. */
	var glyphSymbolName: String {
		switch self {
		case .channel: "number"
		case .directChat: "bubble.left.and.bubble.right.fill"
		case .direct, .console: "person.fill"
		}
	}

	init(_ conversation: Conversation) {
		self = if conversation.isChannel {
			.channel
		} else if conversation.isDirectChat {
			.directChat
		} else if conversation.isConsole {
			.console
		} else {
			.direct
		}
	}
}
