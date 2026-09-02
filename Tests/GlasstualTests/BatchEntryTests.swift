/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@Suite("Batch entries")
@MainActor
struct BatchEntryTests {
	private func batch(token: String) -> MessageBatch {
		let batch = MessageBatch()
		batch.batchToken = token
		return batch
	}

	@Test("A batch keeps messages and nested batches apart without a cast")
	func distinguishesItsTwoCases() throws {
		let parent = batch(token: "parent")
		let child = batch(token: "child")
		let message = try #require(Message(line: "PING :first"))

		parent.queueEntry(message)
		parent.queueEntry(child)

		let entries = parent.queuedEntries
		#expect(entries.count == 2)

		guard case let .message(queuedMessage) = entries[0] else {
			Issue.record("Expected the first entry to be a message")
			return
		}
		guard case let .batch(queuedBatch) = entries[1] else {
			Issue.record("Expected the second entry to be a batch")
			return
		}

		#expect(queuedMessage === message)
		#expect(queuedBatch === child)
	}

	@Test("Dequeuing an entry removes every copy of that same object")
	func dequeuesByIdentity() throws {
		let parent = batch(token: "parent")
		let first = try #require(Message(line: "PING :first"))
		let second = try #require(Message(line: "PING :second"))

		parent.queueEntry(first)
		parent.queueEntry(first)
		parent.queueEntry(second)

		parent.dequeueEntry(first)

		#expect(parent.queuedEntries.count == 1)
		#expect(parent.queuedEntries.first?.object === second)
	}

	@Test("The queue refuses entries past its ceiling")
	func stopsAtTheCeiling() throws {
		let full = batch(token: "full")

		for index in 0 ..< MessageBatch.maximumQueuedEntries {
			let message = try #require(Message(line: "PING :\(index)"))
			#expect(full.queueEntry(message))
		}

		let overflow = try #require(Message(line: "PING :overflow"))
		#expect(full.queueEntry(overflow) == false)
		#expect(full.queuedEntries.count == MessageBatch.maximumQueuedEntries)
	}
}
