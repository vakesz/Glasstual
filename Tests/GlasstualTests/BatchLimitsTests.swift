// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct BatchLimitsTests {
	@Test("A duplicate active wire token cannot replace its batch or create a parent cycle")
	func duplicateActiveTokenIsRejected() throws {
		let client = TestClient()
		client.enableCapability(.batch)
		try client.receiveBatch(message("BATCH +outer example/outer", on: client))
		let original = try #require(client.batchMessages.queuedEntry(withBatchToken: "outer"))
		try #expect(client.filterBatchCommandIncomingData(message("@batch=outer :a!u@h PRIVMSG #c :one", on: client)))

		try client.receiveBatch(message("@batch=outer BATCH +outer example/replacement", on: client))
		#expect(client.batchMessages.queuedEntry(withBatchToken: "outer") === original)
		#expect(original.parentBatchMessage == nil)
		#expect(original.queuedMessages.count == 1)
		try client.receiveBatch(message("BATCH -outer", on: client))
		#expect(client.processedMessages.count == 1)
		#expect(client.batchMessages.queuedEntries.isEmpty)
	}

	@Test("Teardown releases real nested wire queues, including a child already closed", arguments: [true, false])
	func teardownReleasesNestedWireQueues(_ closeChild: Bool) throws {
		let client = TestClient()
		client.enableCapability(.batch)
		try client.receiveBatch(message("BATCH +outer example/outer", on: client))
		try client.receiveBatch(message("@batch=outer BATCH +inner example/inner", on: client))
		weak var outer: MessageBatch?
		weak var inner: MessageBatch?
		outer = client.batchMessages.queuedEntry(withBatchToken: "outer")
		inner = client.batchMessages.queuedEntry(withBatchToken: "inner")
		weak var queuedMessage: Message?
		do {
			let direct = try message("@batch=outer :a!u@h PRIVMSG #c :one", on: client)
			let nested = try message("@batch=inner :a!u@h PRIVMSG #c :two", on: client)
			queuedMessage = nested
			#expect(client.filterBatchCommandIncomingData(direct))
			#expect(client.filterBatchCommandIncomingData(nested))
		}
		if closeChild {
			try client.receiveBatch(message("BATCH -inner", on: client))
		}
		#expect(outer?.queuedMessages.count == 2)
		#expect(inner != nil)
		#expect(queuedMessage != nil)

		client.batchMessages.dequeueEntries()
		#expect(outer == nil)
		#expect(inner == nil)
		#expect(queuedMessage == nil)
		#expect(client.processedMessages.count == 0)
	}

	private func message(_ line: String, on client: Client) throws -> Message {
		try #require(Message(line: line, on: client))
	}

	private func closedBatch(token: String) -> MessageBatch {
		let batch = MessageBatch()
		batch.batchToken = token
		batch.batchIsOpen = false
		return batch
	}

	/// A batch the server never closes used to queue messages without limit.
	@Test
	func batchQueueRejectsEntriesPastItsCeiling() throws {
		let client = TestClient()
		let batch = closedBatch(token: "full")

		for index in 0 ..< MessageBatch.maximumQueuedEntries {
			try #expect(batch.queueMessage(message(":a!u@h PRIVMSG #c :\(index)", on: client)))
		}

		#expect(batch.queuedMessages.count == MessageBatch.maximumQueuedEntries)
		try #expect(batch.queueMessage(message(":a!u@h PRIVMSG #c :overflow", on: client)) == false)
		#expect(batch.queuedMessages.count == MessageBatch.maximumQueuedEntries)
	}

	/// The per-batch ceiling bounded nothing while a server could open an
	/// unlimited number of batches and leave every one of them open.
	@Test
	func openingMoreBatchesThanTheCeilingIsRefused() throws {
		let client = TestClient()

		for index in 0 ..< MessageBatchContainer.maximumOpenBatches {
			try client.receiveBatch(message("BATCH +b\(index) chathistory", on: client))
		}

		#expect(client.batchMessages.queuedEntries.count == MessageBatchContainer.maximumOpenBatches)

		try client.receiveBatch(message("BATCH +overflow chathistory", on: client))

		#expect(client.batchMessages.queuedEntry(withBatchToken: "overflow") == nil)
		#expect(client.batchMessages.queuedEntries.count == MessageBatchContainer.maximumOpenBatches)
	}

	/// Closing a batch frees its slot, so a well-behaved server never hits the
	/// ceiling however many batches it sends in sequence.
	@Test
	func closingABatchFreesItsSlot() throws {
		let client = TestClient()

		for index in 0 ..< (MessageBatchContainer.maximumOpenBatches * 2) {
			try client.receiveBatch(message("BATCH +b\(index) chathistory", on: client))
			try client.receiveBatch(message("BATCH -b\(index)", on: client))
		}

		#expect(client.batchMessages.queuedEntries.isEmpty)
	}

	/// A netsplit wider than the queue used to drop the QUITs past the ceiling,
	/// leaving those people listed in every channel they were in.
	@Test("A batch that overflows its queue processes every message, in order, instead of dropping any")
	func overflowingBatchProcessesEveryMessageInOrder() throws {
		let client = TestClient()
		client.enableCapability(.batch)
		try client.receiveBatch(message("BATCH +split netsplit a.example b.example", on: client))
		let batch = try #require(client.batchMessages.queuedEntry(withBatchToken: "split"))

		for index in 0 ..< MessageBatch.maximumQueuedEntries {
			try #expect(client.filterBatchCommandIncomingData(message("@batch=split :n\(index)!u@h QUIT :split", on: client)))
		}

		#expect(client.processedMessages.count == 0)

		let overflow = try message("@batch=split :overflow!u@h QUIT :split", on: client)
		#expect(client.filterBatchCommandIncomingData(overflow) == false, "The overflowing message is processed live")
		#expect(client.processedMessages.count == MessageBatch.maximumQueuedEntries)
		#expect((client.processedMessages.firstObject as? Message)?.senderNickname == "n0")
		#expect(batch.queuedMessages.isEmpty)

		let later = try message("@batch=split :later!u@h QUIT :split", on: client)
		#expect(client.filterBatchCommandIncomingData(later) == false)

		try client.receiveBatch(message("BATCH -split", on: client))
		#expect(client.batchMessages.queuedEntries.isEmpty)
		#expect(client.processedMessages.count == MessageBatch.maximumQueuedEntries)
	}
}

@MainActor
struct MessageTagLimitTests {
	/// IRCv3 caps the tag section at 8191 bytes.
	@Test
	func oversizedTagSectionsAreDropped() {
		let oversized = "a=" + String(repeating: "b", count: 8191)

		#expect(MessageTagParser.parsedTags(fromSection: oversized).tags.isEmpty)
	}

	/// The cap counts the `@` and the trailing space the parser never sees.
	@Test
	func tagSectionsAtTheLimitAreStillParsed() {
		let value = String(repeating: "b", count: MessageTagParser.maximumSectionLength - 4)
		let section = "a=" + value

		#expect(("@" + section + " ").utf8.count == MessageTagParser.maximumSectionLength)
		#expect(MessageTagParser.parsedTags(fromSection: section).tags == ["a": value])
		#expect(MessageTagParser.parsedTags(fromSection: section + "b").tags.isEmpty)
	}
}

@MainActor
struct ClientOfferedCapabilityLimitTests {
	/// Only a final, non-`*` `CAP LS` cleared the table, so a server sending
	/// nothing but continuations grew it for as long as it stayed connected.
	@Test
	func continuedCapabilityListsPastTheLimitEndNegotiation() throws {
		let client = TestClient()
		let perLine = 32
		let lines = (ClientNegotiationUtilities.maximumOfferedCapabilities / perLine) + 1

		for line in 0 ..< lines {
			let names = (0 ..< perLine).map { "cap-\(line)-\($0)" }.joined(separator: " ")
			let message = try #require(Message(line: "CAP * LS * :\(names)", on: client))

			client.handleCapabilityOrAuthenticationRequest(message)
		}

		#expect(client.capabilityNegotiation.offeredCapabilities.isEmpty)
		#expect(client.sentCapabilityCommands.contains("END"))
	}
}

@MainActor
struct ClientSASLPayloadLimitTests {
	/// `sasl.incomingPayload` grew 400 characters per AUTHENTICATE with no
	/// ceiling, so a server could grow it until the process died.
	@Test
	func oversizedSASLPayloadsAbortNegotiation() throws {
		let client = TestClient()
		client.enableCapability(.isInSASLNegotiation)

		let chunk = String(repeating: "A", count: 400)
		let chunksBeforeOverflow = ClientNegotiationUtilities.maximumSASLPayloadLength / 400

		for _ in 0 ..< chunksBeforeOverflow {
			let message = try #require(Message(line: "AUTHENTICATE \(chunk)", on: client))
			client.handleCapabilityOrAuthenticationRequest(message)
		}

		#expect(client.sasl.incomingPayload?.count == chunksBeforeOverflow * 400)

		let overflow = try #require(Message(line: "AUTHENTICATE \(chunk)", on: client))
		client.handleCapabilityOrAuthenticationRequest(overflow)

		#expect(client.sasl.incomingPayload == nil)
	}
}
