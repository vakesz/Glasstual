/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("World bookkeeping")
struct IRCWorldMigrationTests {
	@Test("A world starts with no clients and no traffic recorded")
	func initialWorldIsEmpty() {
		let world = IRCWorld()

		#expect(world.clientCount == 0)
		#expect(world.clientList.isEmpty)
		#expect(world.messagesSent == 0)
		#expect(world.messagesReceived == 0)
		#expect(world.bandwidthIn == 0)
		#expect(world.bandwidthOut == 0)
	}

	@Test("Traffic counters accumulate the lengths they are told about")
	func trafficCountersAccumulateLengths() {
		let world = IRCWorld()

		world.noteMessageSent(length: 12)
		world.noteMessageSent(length: 7)
		world.noteMessageReceived(length: 31)

		#expect(world.messagesSent == 2)
		#expect(world.messagesReceived == 1)
		#expect(world.bandwidthOut == 19)
		#expect(world.bandwidthIn == 31)
	}

	@Test("Looking up an identifier the world does not hold finds nothing")
	func unknownTreeItemsAreNotFound() {
		let world = IRCWorld()

		#expect(world.findItem(withId: "missing") == nil)
		#expect(world.findClient(withId: "missing") == nil)
		#expect(world.findChannel(withId: "missing", onClientWithId: "missing-client") == nil)
		#expect(world.findItems(withIds: ["missing"]).isEmpty)
	}
}
