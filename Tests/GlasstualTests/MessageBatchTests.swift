// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("IRC message batches")
struct MessageBatchTests {
	@Test("A batch is found by its token until it is dequeued")
	func containerQueuesAndDequeuesBatchesByToken() throws {
		let container = MessageBatchContainer()
		let batch = batchWithToken("history-1")
		let message = try #require(Message(line: ":nick!user@host PRIVMSG #channel :hello"))

		batch.queueMessage(message)

		container.queueEntry(batch)

		#expect(container.queuedEntry(withBatchToken: "history-1") === batch)

		#expect(container.queuedEntries["history-1"] === batch)
		#expect(batch.queuedMessages.first === message)

		container.dequeueEntry(withBatchToken: "history-1")

		#expect(container.queuedEntry(withBatchToken: "history-1") == nil)

		#expect(batch.queuedMessages.isEmpty)
	}

	@Test("A batch keeps its messages in the order they arrived, repeats included")
	func batchKeepsMessagesInOrder() throws {
		let batch = batchWithToken("parent")
		let first = try #require(Message(line: "PING :first"))
		let second = try #require(Message(line: "PING :second"))

		batch.queueMessage(first)
		batch.queueMessage(first)
		batch.queueMessage(second)

		#expect(batch.queuedMessages.map(ObjectIdentifier.init) == [first, first, second].map(ObjectIdentifier.init))

		batch.dequeueMessages()

		#expect(batch.queuedMessages.isEmpty)
	}

	@Test("Discarding every batch releases queued messages instead of retaining retired replay")
	func dequeuingEveryBatchDiscardsTheirContents() throws {
		let container = MessageBatchContainer()
		let batch = batchWithToken("batch")
		let message = try #require(Message(line: "PING :token"))

		batch.queueMessage(message)

		container.queueEntry(batch)
		container.dequeueEntries()

		#expect(container.queuedEntries.count == 0)

		#expect(batch.queuedMessages.isEmpty)
	}

	private func batchWithToken(_ token: String) -> MessageBatch {
		let batch = MessageBatch()

		batch.batchToken = token

		return batch
	}
}
