/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Server-list reordering")
struct ServerListReorderPolicyTests {
	/** The drop as the sidebar performs it, end to end.

	 The indices the policy hands back go to `IRCWorld`, which takes the dragged
	 item out of the list before putting it back and clamps what it was given to
	 what is left. Checking the arithmetic on its own said nothing about where a
	 row landed, which is how "drop A on the row below it" stayed a no-op -- and
	 a copy of the move written out here would have said just as little, because
	 it could agree with the policy while `IRCWorld` disagreed with both. The
	 world does the moving; only the order it ends up in is asserted. */
	private func dropping(_ dragged: String, onto destination: String, in order: [String]) -> [String] {
		let world = IRCWorld()
		var identifiersByName: [String: String] = [:]
		world.clientList = order.map { name in
			let client = GLTTestClient()
			client.config.connectionName = name
			identifiersByName[name] = client.uniqueIdentifier
			return client
		}
		guard let move = ServerListReorderPolicy.move(
			in: world.clientList.map(\.uniqueIdentifier),
			dragging: identifiersByName[dragged] ?? dragged,
			onto: identifiersByName[destination] ?? destination
		) else {
			return order
		}
		world.moveClient(from: move.from, to: move.to)
		return world.clientList.map(\.config.connectionName)
	}

	@Test("A row dropped on another takes that row's place")
	func dropTakesTheRowsPlace() {
		let order = ["a", "b", "c", "d"]

		#expect(dropping("a", onto: "b", in: order) == ["b", "a", "c", "d"])
		#expect(dropping("a", onto: "c", in: order) == ["b", "c", "a", "d"])
		#expect(dropping("d", onto: "b", in: order) == ["a", "d", "b", "c"])
		#expect(dropping("c", onto: "a", in: order) == ["c", "a", "b", "d"])
	}

	@Test("The last place in the list is reachable")
	func lastPlaceIsReachable() {
		#expect(dropping("a", onto: "d", in: ["a", "b", "c", "d"]) == ["b", "c", "d", "a"])
		#expect(dropping("a", onto: "b", in: ["a", "b"]) == ["b", "a"])
	}

	@Test("A drop that names no other row is not a move")
	func nonMovesAreRefused() {
		#expect(ServerListReorderPolicy.move(in: ["a", "b"], dragging: "a", onto: "a") == nil)
		#expect(ServerListReorderPolicy.move(in: ["a", "b"], dragging: "a", onto: "z") == nil)
		#expect(ServerListReorderPolicy.move(in: ["a", "b"], dragging: "z", onto: "a") == nil)
	}

	@Test("Channels cannot cross server or channel-query boundaries")
	func channelMoveBoundaries() {
		#expect(
			ServerListReorderPolicy.permitsChannelMove(
				sharesClient: true,
				draggedIsChannel: true,
				destinationIsChannel: true
			)
		)
		#expect(
			ServerListReorderPolicy.permitsChannelMove(
				sharesClient: false,
				draggedIsChannel: true,
				destinationIsChannel: true
			) == false
		)
		#expect(
			ServerListReorderPolicy.permitsChannelMove(
				sharesClient: true,
				draggedIsChannel: true,
				destinationIsChannel: false
			) == false
		)
	}
}
