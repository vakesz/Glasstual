/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
final class IRCWorldMigrationTests: XCTestCase {
	func testInitialWorldIsEmpty() {
		let world = IRCWorld()

		XCTAssertEqual(world.clientCount, 0)
		XCTAssertTrue(world.clientList.isEmpty)
		XCTAssertEqual(world.messagesSent, 0)
		XCTAssertEqual(world.messagesReceived, 0)
		XCTAssertEqual(world.bandwidthIn, 0)
		XCTAssertEqual(world.bandwidthOut, 0)
	}

	func testTrafficCountersAccumulateLengths() {
		let world = IRCWorld()

		world.noteMessageSent(length: 12)
		world.noteMessageSent(length: 7)
		world.noteMessageReceived(length: 31)

		XCTAssertEqual(world.messagesSent, 2)
		XCTAssertEqual(world.messagesReceived, 1)
		XCTAssertEqual(world.bandwidthOut, 19)
		XCTAssertEqual(world.bandwidthIn, 31)
	}

	func testUnknownTreeItemsAreNotFound() {
		let world = IRCWorld()

		XCTAssertNil(world.findItem(withId: "missing"))
		XCTAssertNil(world.findClient(withId: "missing"))
		XCTAssertNil(world.findChannel(withId: "missing", onClientWithId: "missing-client"))
		XCTAssertTrue(world.findItems(withIds: ["missing"]).isEmpty)
	}
}
