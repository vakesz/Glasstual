/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@Suite("Inbound connection delivery")
@MainActor
struct IRCConnectionInboundDeliveryTests {
	private func connectedClient() -> (GLTTestClient, Connection) {
		let client = GLTTestClient()
		client.setValue(true, forKey: "isConnected")
		let connection = Connection(config: IRCConnectionConfig(), onClient: client)
		client.socket = connection
		return (client, connection)
	}

	/// The connection drains the host's callbacks through one ordered stream, so
	/// the client answers the lines in the order the server sent them.
	@Test("Lines are answered in the order the connection delivered them")
	func answersInWireOrder() {
		let (client, connection) = connectedClient()

		for token in ["one", "two", "three"] {
			client.ircConnection(connection, didReceiveData: "PING :\(token)")
		}

		#expect(client.sentLines as? [String] == ["PONG one", "PONG two", "PONG three"])
	}

	/// A reconnect replaces the socket. Lines that were already in flight on the
	/// retired connection must not act on the new session.
	@Test("A line from a connection the client no longer owns is dropped")
	func ignoresRetiredConnection() {
		let (client, _) = connectedClient()
		let retired = Connection(config: IRCConnectionConfig(), onClient: client)

		client.ircConnection(retired, didReceiveData: "PING :stale")

		#expect(client.sentLines.count == 0)
	}

	@Test("Empty data is not treated as a line")
	func ignoresEmptyData() {
		let (client, connection) = connectedClient()

		client.ircConnection(connection, didReceiveData: "")

		#expect(client.sentLines.count == 0)
	}
}

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

@Suite("Typing state")
@MainActor
struct TypingStateTests {
	/// The states go on the wire as the `+typing` tag value, so their spellings
	/// are part of the protocol.
	@Test("Each state keeps the spelling IRCv3 gives it")
	func matchesTheWireSpelling() {
		#expect(TypingState.active.rawValue == "active")
		#expect(TypingState.paused.rawValue == "paused")
		#expect(TypingState.done.rawValue == "done")
		#expect(TypingState(rawValue: "typing") == nil)
	}

	@Test("An active notification is sent again only once the interval is up")
	func rateLimitsTheActiveNotification() {
		let now = Date(timeIntervalSince1970: 100)

		#expect(OutboundTypingPolicy.shouldSendActive(previousState: nil, lastSentAt: nil, now: now))
		#expect(OutboundTypingPolicy.shouldSendActive(previousState: .paused, lastSentAt: now, now: now))
		#expect(OutboundTypingPolicy.shouldSendActive(
			previousState: .active,
			lastSentAt: now.addingTimeInterval(-OutboundTypingPolicy.activeInterval),
			now: now
		))
		#expect(OutboundTypingPolicy.shouldSendActive(
			previousState: .active,
			lastSentAt: now,
			now: now
		) == false)
	}
}

@Suite("Client timer")
@MainActor
struct ClientTimerTests {
	@Test("A timer that has not been started is not active")
	func startsInactive() {
		let timer = ClientTimer { _ in }

		#expect(timer.isActive == false)
	}

	@Test("Stopping a timer keeps it from firing")
	func cancellationPreventsTheAction() async {
		var fired = 0
		let timer = ClientTimer { _ in fired += 1 }

		timer.start(0.05, repeats: true)
		#expect(timer.isActive)

		timer.stop()
		#expect(timer.isActive == false)

		try? await Task.sleep(for: .milliseconds(200))

		#expect(fired == 0)
	}

	@Test("A one-shot timer fires once and then reports itself inactive")
	func oneShotStopsAfterFiring() async {
		var fired = 0
		let timer = ClientTimer { _ in fired += 1 }

		timer.start(0.02)

		try? await Task.sleep(for: .milliseconds(200))

		#expect(fired == 1)
		#expect(timer.isActive == false)
	}

	@Test("Restarting a timer replaces the pending run rather than adding one")
	func restartingReplacesThePendingRun() async {
		var fired = 0
		let timer = ClientTimer { _ in fired += 1 }

		timer.start(0.02)
		timer.start(0.02)

		try? await Task.sleep(for: .milliseconds(200))

		#expect(fired == 1)
	}

	@Test("A repeating timer stops itself once it has run its iterations")
	func boundedRepeatStopsItself() async {
		var fired = 0
		let timer = ClientTimer { _ in fired += 1 }

		timer.start(0.02, repeats: true, iterations: 2)

		try? await Task.sleep(for: .milliseconds(400))

		#expect(fired == 2)
		#expect(timer.isActive == false)
	}
}
