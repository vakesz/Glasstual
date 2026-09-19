// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

/** The sidebar draws a snapshot of each item's counts, so a count that changes
 has to ask for a redraw. Raising one already did; clearing one did not, which
 left the badge on a channel the user had just opened until something else
 happened to redraw the row. */
@MainActor
@Suite("Sidebar item unread state")
struct ChatItemStateTests {
	@Test("Resetting an item's state redraws its badge")
	func resettingStateRedrawsTheBadge() throws {
		let session = TestServerSession()
		let channel = try #require(session.findConversationOrCreate("#chat"))
		channel.unreadCount = 3
		channel.nicknameHighlightCount = 1
		let redrawsBefore = session.recordedOutput.reloadedItems.count

		channel.resetState()

		#expect(channel.unreadCount == 0)
		#expect(channel.nicknameHighlightCount == 0)
		#expect(channel.dockUnreadCount == 0)
		#expect(session.recordedOutput.reloadedItems.dropFirst(redrawsBefore).contains { $0 === channel })
	}
}
