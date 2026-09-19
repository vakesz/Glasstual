// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@Suite("Server-list rows")
struct SidebarRowTests {
	private func channel(
		kind: ConversationRow.Kind = .channel,
		unread: Int = 0,
		highlights: Int = 0,
		showsUnreadCount: Bool = true,
		badgeTint: NSColor? = nil
	) -> ConversationRow {
		ConversationRow(
			id: "id",
			title: "#glasstual",
			kind: kind,
			isActive: true,
			hasJoinError: false,
			unreadCount: unread,
			showsUnreadCount: showsUnreadCount,
			highlightCount: highlights,
			unreadBadgeTint: badgeTint
		)
	}

	@Test("A channel is emphasised only when the nickname was said")
	func channelEmphasis() {
		#expect(channel(unread: 12).isEmphasized == false)
		#expect(channel(unread: 12, highlights: 1).isEmphasized)
	}

	@Test("A conversation with one person is emphasised by anything unread")
	func directConversationEmphasis() {
		#expect(channel(kind: .direct, unread: 1).isEmphasized)
		#expect(channel(kind: .directChat, unread: 1).isEmphasized)
		#expect(channel(kind: .direct).isEmphasized == false)
		#expect(channel(kind: .console, unread: 5).isEmphasized == false)
	}

	@Test("The unread badge needs both a count and the channel's consent")
	func unreadBadge() {
		#expect(channel(unread: 3).showsUnreadBadge)
		#expect(channel(unread: 0).showsUnreadBadge == false)
		#expect(channel(unread: 3, showsUnreadCount: false).showsUnreadBadge == false)
	}
}
