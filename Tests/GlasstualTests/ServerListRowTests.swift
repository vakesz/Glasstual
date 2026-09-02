/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@Suite("Server-list rows")
struct ServerListRowTests {
	private func channel(
		kind: ChannelRow.Kind = .channel,
		unread: Int = 0,
		highlights: Int = 0,
		showsUnreadCount: Bool = true
	) -> ChannelRow {
		ChannelRow(
			id: "id",
			title: "#glasstual",
			kind: kind,
			isActive: true,
			hasJoinError: false,
			unreadCount: unread,
			showsUnreadCount: showsUnreadCount,
			highlightCount: highlights
		)
	}

	@Test("A channel is emphasised only when the nickname was said")
	func channelEmphasis() {
		#expect(channel(unread: 12).isEmphasized == false)
		#expect(channel(unread: 12, highlights: 1).isEmphasized)
	}

	@Test("A conversation with one person is emphasised by anything unread")
	func directConversationEmphasis() {
		#expect(channel(kind: .privateMessage, unread: 1).isEmphasized)
		#expect(channel(kind: .directChat, unread: 1).isEmphasized)
		#expect(channel(kind: .privateMessage).isEmphasized == false)
		#expect(channel(kind: .utility, unread: 5).isEmphasized == false)
	}

	@Test("The unread badge needs both a count and the channel's consent")
	func unreadBadge() {
		#expect(channel(unread: 3).showsUnreadBadge)
		#expect(channel(unread: 0).showsUnreadBadge == false)
		#expect(channel(unread: 3, showsUnreadCount: false).showsUnreadBadge == false)
	}

	@Test("Rows compare by what they draw, so an unchanged row is skipped")
	func rowEquality() {
		#expect(channel(unread: 1) == channel(unread: 1))
		#expect(channel(unread: 1) != channel(unread: 2))
	}
}
