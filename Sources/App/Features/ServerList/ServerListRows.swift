/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

/// One server in the sidebar, with the conversations drawn beneath it.
///
/// A snapshot: the tree it describes lives on `NSObject`s that change under
/// SwiftUI's feet, so the list publishes values instead and rebuilds them when
/// the tree says something changed. A row is a plain function of its value.
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
	let channels: [ChannelRow]
}

/// One conversation in the sidebar.
struct ChannelRow: Identifiable, Equatable {
	enum Kind: Equatable {
		case channel
		case privateMessage
		case directChat
		case utility
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
	let unreadBadgeTint: Color?

	/// Asks for attention: a channel where the nickname was said, or a
	/// conversation with one person that has anything unread — every line of a
	/// direct message is addressed to the reader.
	var isEmphasized: Bool {
		if highlightCount > 0 {
			return true
		}
		return (kind == .privateMessage || kind == .directChat) && unreadCount > 0
	}

	var showsUnreadBadge: Bool {
		showsUnreadCount && unreadCount > 0
	}
}
