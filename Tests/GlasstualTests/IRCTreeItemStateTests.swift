/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

/** The sidebar draws a snapshot of each item's counts, so a count that changes
 has to ask for a redraw. Raising one already did; clearing one did not, which
 left the badge on a channel the user had just opened until something else
 happened to redraw the row. */
@MainActor
@Suite("Tree item unread state")
struct IRCTreeItemStateTests {
	@Test("Resetting an item's state redraws its badge")
	func resettingStateRedrawsTheBadge() throws {
		let client = GLTTestClient()
		let channel = try #require(client.findChannelOrCreate("#chat"))
		channel.treeUnreadCount = 3
		channel.nicknameHighlightCount = 1
		let redrawsBefore = client.recordedOutput.reloadedItems.count

		channel.resetState()

		#expect(channel.treeUnreadCount == 0)
		#expect(channel.nicknameHighlightCount == 0)
		#expect(channel.dockUnreadCount == 0)
		#expect(client.recordedOutput.reloadedItems.dropFirst(redrawsBefore).contains { $0 === channel })
	}
}
