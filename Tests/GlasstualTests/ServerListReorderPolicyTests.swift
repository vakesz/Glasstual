/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Server-list reordering")
struct ServerListReorderPolicyTests {
	/** The drag as the sidebar performs it, end to end.

	 The indices the policy hands back go to `World`, which takes the dragged
	 item out of the list before putting it back and clamps what it was given to
	 what is left. Checking the arithmetic on its own said nothing about where a
	 row landed, which is how "drop A below itself" stayed a no-op — and a copy
	 of the move written out here would have said just as little, because it
	 could agree with the policy while `World` disagreed with both. The world
	 does the moving; only the order it ends up in is asserted. */
	private func moving(_ from: Int, before destination: Int, in order: [String]) -> [String] {
		let world = World()
		world.clientList = order.map { name in
			let client = TestClient()
			client.config.connectionName = name
			return client
		}
		let list = ServerList()
		list.clientSource = { world.clientList }
		list.worldSource = { world }

		list.moveServers(fromOffsets: IndexSet(integer: from), toOffset: destination)
		return world.clientList.map(\.config.connectionName)
	}

	@Test("A row lands where the insertion line was drawn")
	func rowLandsAtTheInsertionPoint() {
		let order = ["a", "b", "c", "d"]

		#expect(moving(0, before: 2, in: order) == ["b", "a", "c", "d"])
		#expect(moving(0, before: 3, in: order) == ["b", "c", "a", "d"])
		#expect(moving(3, before: 1, in: order) == ["a", "d", "b", "c"])
		#expect(moving(2, before: 0, in: order) == ["c", "a", "b", "d"])
	}

	/// A list names the place a row is being inserted *before*, so the end of
	/// the list is one past its last index.
	@Test("The last place in the list is reachable")
	func lastPlaceIsReachable() {
		#expect(moving(0, before: 4, in: ["a", "b", "c", "d"]) == ["b", "c", "d", "a"])
		#expect(moving(0, before: 2, in: ["a", "b"]) == ["b", "a"])
	}

	@Test("A drag that puts a row back where it was is not a move")
	func nonMovesAreRefused() {
		#expect(ServerListReorderPolicy.move(fromOffsets: IndexSet(integer: 1), toOffset: 1) == nil)
		#expect(ServerListReorderPolicy.move(fromOffsets: IndexSet(integer: 1), toOffset: 2) == nil)
		/* The sidebar carries one selected row at a time, so a drag of several
		 is not something it can mean. */
		#expect(ServerListReorderPolicy.move(fromOffsets: IndexSet([0, 1]), toOffset: 3) == nil)
		#expect(ServerListReorderPolicy.move(fromOffsets: IndexSet(), toOffset: 1) == nil)
	}

	@Test("Channels and one-to-one conversations do not move into each other")
	func channelMoveBoundaries() {
		#expect(
			ServerListReorderPolicy.permitsChannelMove(draggedIsChannel: true, destinationIsChannel: true)
		)
		#expect(
			ServerListReorderPolicy.permitsChannelMove(draggedIsChannel: true, destinationIsChannel: false)
				== false
		)
		#expect(
			ServerListReorderPolicy.permitsChannelMove(draggedIsChannel: false, destinationIsChannel: false)
		)
	}

	/// A filter draws a list the world is not in the order of, so an index into
	/// the rows on screen means nothing to it.
	@Test("A filtered sidebar cannot be reordered")
	func filteredSidebarRefusesMoves() {
		let world = World()
		world.clientList = ["alpha", "beta"].map { name in
			let client = TestClient()
			client.config.connectionName = name
			return client
		}
		let list = ServerList()
		list.clientSource = { world.clientList }
		list.worldSource = { world }
		list.filterText = "beta"

		#expect(list.moveServers(fromOffsets: IndexSet(integer: 0), toOffset: 2) == false)
		#expect(world.clientList.map(\.config.connectionName) == ["alpha", "beta"])
	}
}
