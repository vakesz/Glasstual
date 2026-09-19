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
		let session = TestServerSession()
		session.enableCapability(.batch)
		try session.receiveBatch(message("BATCH +outer example/outer", on: session))
		let original = try #require(session.batchMessages.queuedEntry(withBatchToken: "outer"))
		try #expect(session.filterBatchCommandIncomingData(message("@batch=outer :a!u@h PRIVMSG #c :one", on: session)))

		try session.receiveBatch(message("@batch=outer BATCH +outer example/replacement", on: session))
		#expect(session.batchMessages.queuedEntry(withBatchToken: "outer") === original)
		#expect(original.parentBatchMessage == nil)
		#expect(original.queuedMessages.count == 1)
		try session.receiveBatch(message("BATCH -outer", on: session))
		#expect(session.processedMessages.count == 1)
		#expect(session.batchMessages.queuedEntries.isEmpty)
	}

	@Test("Teardown releases real nested wire queues, including a child already closed", arguments: [true, false])
	func teardownReleasesNestedWireQueues(_ closeChild: Bool) throws {
		let session = TestServerSession()
		session.enableCapability(.batch)
		try session.receiveBatch(message("BATCH +outer example/outer", on: session))
		try session.receiveBatch(message("@batch=outer BATCH +inner example/inner", on: session))
		weak var outer: MessageBatch?
		weak var inner: MessageBatch?
		outer = session.batchMessages.queuedEntry(withBatchToken: "outer")
		inner = session.batchMessages.queuedEntry(withBatchToken: "inner")
		do {
			let direct = try message("@batch=outer :a!u@h PRIVMSG #c :one", on: session)
			let nested = try message("@batch=inner :a!u@h PRIVMSG #c :two", on: session)
			#expect(session.filterBatchCommandIncomingData(direct))
			#expect(session.filterBatchCommandIncomingData(nested))
		}
		if closeChild {
			try session.receiveBatch(message("BATCH -inner", on: session))
		}
		#expect(outer?.queuedMessages.count == 2)
		#expect(inner != nil)

		session.batchMessages.dequeueEntries()
		#expect(outer == nil)
		/* A batch's parent link is weak, so the only thing keeping the nested
		 batch alive is the queued message that points back at it: the child going
		 away is what says the root's queue was emptied and not merely detached. */
		#expect(inner == nil)
		#expect(session.processedMessages.count == 0)
	}

	private func message(_ line: String, on session: ServerSession) throws -> Message {
		try #require(Message(line: line, on: session))
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
		let session = TestServerSession()
		let batch = closedBatch(token: "full")

		for index in 0 ..< MessageBatch.maximumQueuedEntries {
			try #expect(batch.queueMessage(message(":a!u@h PRIVMSG #c :\(index)", on: session)))
		}

		#expect(batch.queuedMessages.count == MessageBatch.maximumQueuedEntries)
		try #expect(batch.queueMessage(message(":a!u@h PRIVMSG #c :overflow", on: session)) == false)
		#expect(batch.queuedMessages.count == MessageBatch.maximumQueuedEntries)
	}

	/// The per-batch ceiling bounded nothing while a server could open an
	/// unlimited number of batches and leave every one of them open.
	@Test
	func openingMoreBatchesThanTheCeilingIsRefused() throws {
		let session = TestServerSession()

		for index in 0 ..< MessageBatchContainer.maximumOpenBatches {
			try session.receiveBatch(message("BATCH +b\(index) chathistory", on: session))
		}

		#expect(session.batchMessages.queuedEntries.count == MessageBatchContainer.maximumOpenBatches)

		try session.receiveBatch(message("BATCH +overflow chathistory", on: session))

		#expect(session.batchMessages.queuedEntry(withBatchToken: "overflow") == nil)
		#expect(session.batchMessages.queuedEntries.count == MessageBatchContainer.maximumOpenBatches)
	}

	/// Closing a batch frees its slot, so a well-behaved server never hits the
	/// ceiling however many batches it sends in sequence.
	@Test
	func closingABatchFreesItsSlot() throws {
		let session = TestServerSession()

		for index in 0 ..< (MessageBatchContainer.maximumOpenBatches * 2) {
			try session.receiveBatch(message("BATCH +b\(index) chathistory", on: session))
			try session.receiveBatch(message("BATCH -b\(index)", on: session))
		}

		#expect(session.batchMessages.queuedEntries.isEmpty)
	}

	/// A netsplit wider than the queue used to drop the QUITs past the ceiling,
	/// leaving those people listed in every channel they were in.
	@Test("A batch that overflows its queue processes every message, in order, instead of dropping any")
	func overflowingBatchProcessesEveryMessageInOrder() throws {
		let session = TestServerSession()
		session.enableCapability(.batch)
		try session.receiveBatch(message("BATCH +split netsplit a.example b.example", on: session))
		let batch = try #require(session.batchMessages.queuedEntry(withBatchToken: "split"))

		for index in 0 ..< MessageBatch.maximumQueuedEntries {
			try #expect(session.filterBatchCommandIncomingData(message("@batch=split :n\(index)!u@h QUIT :split", on: session)))
		}

		#expect(session.processedMessages.count == 0)

		let overflow = try message("@batch=split :overflow!u@h QUIT :split", on: session)
		#expect(session.filterBatchCommandIncomingData(overflow) == false, "The overflowing message is processed live")
		#expect(session.processedMessages.count == MessageBatch.maximumQueuedEntries)
		#expect(session.processedMessages.first?.senderNickname == "n0")
		#expect(batch.queuedMessages.isEmpty)

		let later = try message("@batch=split :later!u@h QUIT :split", on: session)
		#expect(session.filterBatchCommandIncomingData(later) == false)

		try session.receiveBatch(message("BATCH -split", on: session))
		#expect(session.batchMessages.queuedEntries.isEmpty)
		#expect(session.processedMessages.count == MessageBatch.maximumQueuedEntries)
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
struct ServerSessionOfferedCapabilityLimitTests {
	/// Only a final, non-`*` `CAP LS` cleared the table, so a server sending
	/// nothing but continuations grew it for as long as it stayed connected.
	@Test
	func continuedCapabilityListsPastTheLimitEndNegotiation() throws {
		let session = TestServerSession()
		let perLine = 32
		let lines = (CapabilityNegotiationState.maximumOfferedCapabilities / perLine) + 1

		for line in 0 ..< lines {
			let names = (0 ..< perLine).map { "cap-\(line)-\($0)" }.joined(separator: " ")
			let message = try #require(Message(line: "CAP * LS * :\(names)", on: session))

			session.handleCapabilityOrAuthenticationRequest(message)
		}

		#expect(session.capabilityNegotiation.offeredCapabilities.isEmpty)
		#expect(session.sentCapabilityCommands.contains("END"))
	}
}

@MainActor
struct ServerSessionSASLPayloadLimitTests {
	/// `sasl.incomingPayload` grew 400 characters per AUTHENTICATE with no
	/// ceiling, so a server could grow it until the process died.
	@Test
	func oversizedSASLPayloadsAbortNegotiation() throws {
		let session = TestServerSession()
		session.enableCapability(.isInSASLNegotiation)

		let chunk = String(repeating: "A", count: 400)
		let chunksBeforeOverflow = SASLPolicy.maximumPayloadLength / 400

		for _ in 0 ..< chunksBeforeOverflow {
			let message = try #require(Message(line: "AUTHENTICATE \(chunk)", on: session))
			session.handleCapabilityOrAuthenticationRequest(message)
		}

		#expect(session.sasl.incomingPayload?.count == chunksBeforeOverflow * 400)

		let overflow = try #require(Message(line: "AUTHENTICATE \(chunk)", on: session))
		session.handleCapabilityOrAuthenticationRequest(overflow)

		#expect(session.sasl.incomingPayload == nil)
	}
}
