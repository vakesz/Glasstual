// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
private final class DeliveryPresentation: ChatItemPresenting {
	struct Update: Equatable {
		let lineNumber: String
		let state: ChatLineDeliveryState
		let messageIdentifier: String?
		let reason: String?
	}

	let presentationIdentifier = "delivery-presentation"
	var updates: [Update] = []
	func print(_: ChatLine, completionBlock _: PrintedLineCompletion?) {}
	func lastPrintedLine() -> ChatLine? {
		nil
	}

	func setTopic(_: String?) {}
	func mark() {}
	func mark(at _: Date) {}
	func noteReaction(_: String, fromNickname _: String, toMessageIdentifier _: String) {}
	func updateDeliveryState(
		forLineNumber lineNumber: String,
		state: ChatLineDeliveryState,
		messageIdentifier: String?,
		reason: String?
	) {
		updates.append(Update(
			lineNumber: lineNumber,
			state: state,
			messageIdentifier: messageIdentifier,
			reason: reason
		))
	}

	func prependEarlierChatLines(_: [ChatLine]) {}
	func tearDown(_: ChatItemTeardown) {}
}

@MainActor
struct LabeledResponseRetirementTests {
	@Test("Unanswered deliveries stop allocating labels at the ceiling")
	func pendingDeliveriesAreBounded() throws {
		let session = sessionWithLabeledResponse()
		defer {
			for label in Array(session.labeledResponses.pending.keys) {
				session.timeoutDelivery(withLabel: label)
			}
		}
		for _ in 0 ..< LabeledResponsePolicy.maximumPendingDeliveries {
			#expect(session.registerPendingDelivery(for: nil) != nil)
		}
		#expect(session.registerPendingDelivery(for: nil) == nil)
		let label = try #require(session.labeledResponses.pending.keys.first)
		session.timeoutDelivery(withLabel: label)
		#expect(session.registerPendingDelivery(for: nil) != nil)
	}

	@Test("Labeled batch associations are bounded and retire with their delivery")
	func batchLabelsAreBoundedAndRetired() throws {
		let session = sessionWithLabeledResponse()
		let label = try #require(session.registerPendingDelivery(for: nil))
		session.enableCapability(.batch)
		for index in 0 ... MessageBatchContainer.maximumOpenBatches {
			let message = try #require(Message(line: "@label=\(label) BATCH +b\(index) labeled-response", on: session))
			#expect(session.resolveLabeledResponse(for: message) == false)
			session.receiveBatch(message)
		}
		#expect(session.batchMessages.queuedEntries.values.compactMap(\.labeledDelivery.label).count == MessageBatchContainer
			.maximumOpenBatches)
		#expect(session.batchMessages.queuedEntry(withBatchToken: "b\(MessageBatchContainer.maximumOpenBatches)") == nil)

		session.timeoutDelivery(withLabel: label)
		#expect(session.batchMessages.queuedEntries.values.compactMap(\.labeledDelivery.label).isEmpty)
		let stale = try #require(Message(line: "@label=\(label) BATCH +stale labeled-response", on: session))
		#expect(session.resolveLabeledResponse(for: stale) == false)
		session.receiveBatch(stale)
		#expect(session.batchMessages.queuedEntries.values.compactMap(\.labeledDelivery.label).isEmpty)
	}

	@Test("A duplicate wire batch cannot replace the original delivery label")
	func duplicateBatchLabelIsRejected() throws {
		let session = sessionWithLabeledResponse()
		session.enableCapability(.batch)
		let first = try #require(session.registerPendingDelivery(for: nil))
		let second = try #require(session.registerPendingDelivery(for: nil))
		for label in [first, second] {
			let message = try #require(Message(line: "@label=\(label) BATCH +reply labeled-response", on: session))
			#expect(session.resolveLabeledResponse(for: message) == false)
			session.receiveBatch(message)
		}
		#expect(session.batchMessages.queuedEntry(withBatchToken: "reply")?.labeledDelivery.label == first)
		let close = try #require(Message(line: "BATCH -reply", on: session))
		#expect(session.resolveLabeledResponse(for: close) == false)
		session.receiveBatch(close)
		#expect(session.labeledResponses.pending[first] == nil)
		#expect(session.deliveryState(forLabel: second) == .pending)
		session.timeoutDelivery(withLabel: second)
	}

	private func sessionWithLabeledResponse() -> TestServerSession {
		let session = TestServerSession()
		session.enableCapability(.messageTags)
		session.enableCapability(.echoMessage)
		session.enableCapability(.labeledResponse)
		return session
	}

	@Test(
		"Nested labeled wire replies commit their final result only after root replay",
		arguments: [true, false],
		[true, false]
	)
	func nestedFailureWinsOverEcho(_ labelOnRoot: Bool, _ failure: Bool) throws {
		let session = sessionWithLabeledResponse()
		session.enableCapability(.batch)
		session.isConnected = true
		session.forwardsProcessedMessages = true
		let socket = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = socket
		let channel = try #require(session.findConversationOrCreate("#chat"))
		let presentation = DeliveryPresentation()
		channel.presentation = presentation
		let label = try #require(session.registerPendingDelivery(for: channel))
		session.attachLineNumber("42", toDeliveryWithLabel: label)
		let delivery = try #require(session.labeledResponses.pending[label])
		func receive(_ line: String) {
			session.connectionDidReceive(line)
		}
		receive("\(labelOnRoot ? "@label=\(label) " : "")BATCH +root labeled-response")
		receive("@batch=root\(labelOnRoot ? "" : ";label=\(label)") BATCH +child labeled-response")
		receive("@batch=child;msgid=echo :me!u@h PRIVMSG #chat :sent")
		if failure {
			receive("@batch=child FAIL PRIVMSG DENIED #chat :Not delivered")
		}
		receive("BATCH -child")
		#expect(delivery.state == .pending)
		#expect(presentation.updates.isEmpty)
		#expect(session.printedLines.count == 0)
		receive("BATCH -root")
		#expect(delivery.state == (failure ? .failed : .delivered))
		#expect(presentation.updates == [
			.init(lineNumber: "42", state: failure ? .failed : .delivered,
			      messageIdentifier: failure ? nil : "echo", reason: failure ? "Not delivered" : nil),
		])
		#expect(session.labeledResponses.pending[label] == nil)
		#expect(session.batchMessages.queuedEntries.isEmpty)
		#expect(session.printedLines.count == 0, "The correlated echo must not print a duplicate outgoing line")
	}

	@Test("A nested replay keeps its ancestry through child close and prints in wire order")
	func nestedReplayPrintsInOrder() {
		let session = sessionWithLabeledResponse()
		session.enableCapability(.batch)
		session.enableCapability(.serverTime)
		session.isConnected = true
		session.forwardsProcessedMessages = true
		let socket = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = socket
		_ = session.findConversationOrCreate("#chat")
		for line in [
			"BATCH +root playback",
			"@batch=root BATCH +child example/nested",
			"@batch=child :alice!u@h PRIVMSG #chat :first",
			"BATCH -child",
			"@batch=root :alice!u@h PRIVMSG #chat :second",
			"BATCH -root",
		] {
			session.connectionDidReceive(line)
		}
		let messages = session.processedMessages
		#expect(messages.map { $0.params.last ?? "" } == ["first", "second"])
		#expect(messages.allSatisfy { $0.parentBatchMessage?.isReplay == true })
		let bodies = session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(bodies == ["first", "second"])
		#expect(session.batchMessages.queuedEntries.isEmpty)
	}

	@Test("A disconnect fails every delivery still waiting instead of leaving it pending")
	func disconnectFailsPendingDeliveries() throws {
		let session = sessionWithLabeledResponse()
		let channel = try #require(session.findConversationOrCreate("#chat"))
		let presentation = DeliveryPresentation()
		channel.presentation = presentation
		let label = try #require(session.registerPendingDelivery(for: channel))
		session.attachLineNumber("7", toDeliveryWithLabel: label)
		let delivery = try #require(session.labeledResponses.pending[label])

		#expect(session.labeledResponses.deadlineTask != nil)

		session.resetCapabilityNegotiation()

		#expect(delivery.state == .failed)
		#expect(presentation.updates == [
			.init(lineNumber: "7", state: .failed, messageIdentifier: nil, reason: "Disconnected"),
		])
		#expect(session.labeledResponses.pending.isEmpty)
		#expect(session.labeledResponses.deadlineTask == nil)
	}

	@Test("A deadline sweep fails only the deliveries that have come due")
	func deadlineSweepFailsOnlyDueDeliveries() throws {
		let session = sessionWithLabeledResponse()
		let overdue = try #require(session.registerPendingDelivery(for: nil))
		let waiting = try #require(session.registerPendingDelivery(for: nil))
		try #require(session.labeledResponses.pending[overdue]).deadline = .now - .seconds(1)

		session.failDeliveries(dueBy: .now)

		#expect(session.labeledResponses.pending[overdue] == nil)
		#expect(session.deliveryState(forLabel: waiting) == .pending)
		#expect(session.labeledResponses.deadlineTask != nil)

		session.resolveDelivery(withLabel: waiting, state: .delivered, messageIdentifier: nil, reason: nil)

		#expect(session.labeledResponses.deadlineTask == nil, "Nothing left to wait for")
	}

	@Test("The deadline sweep fails a delivery nobody answered once its deadline passes", .timeLimit(.minutes(1)))
	func deadlineSweepRunsOnItsOwn() async throws {
		let session = sessionWithLabeledResponse()
		let delivery = LabeledDelivery()
		delivery.label = "due"
		delivery.state = .pending
		delivery.deadline = .now
		session.labeledResponses.pending["due"] = delivery
		_ = try #require(session.registerPendingDelivery(for: nil))

		let sweep = try #require(session.labeledResponses.deadlineTask)
		await sweep.value

		#expect(delivery.state == .failed)
		#expect(session.labeledResponses.pending["due"] == nil)
		#expect(session.labeledResponses.pending.count == 1)
		session.failPendingDeliveriesForDisconnect()
	}

	@Test("Every resolved label is retired rather than accumulating")
	func repeatedDeliveriesDoNotAccumulate() throws {
		let session = sessionWithLabeledResponse()
		_ = session.findConversationOrCreate("#chat")

		for _ in 0 ..< 10 {
			let label = try #require(session.registerPendingDelivery(for: session.findConversation("#chat")))
			session.resolveDelivery(withLabel: label, state: .delivered, messageIdentifier: nil, reason: nil)
		}

		#expect(session.labeledResponses.pending.count == 0)
	}

	@Test("A label the server reuses after resolution does not swallow the message")
	func reusedLabelIsNotConsumedTwice() throws {
		let session = sessionWithLabeledResponse()
		_ = session.findConversationOrCreate("#chat")
		let label = try #require(session.registerPendingDelivery(for: session.findConversation("#chat")))

		let first = try #require(Message(line: "@label=\(label) :me!u@h PRIVMSG #chat :hello", on: session))
		#expect(session.resolveLabeledResponse(for: first))

		let second = try #require(Message(line: "@label=\(label) :me!u@h PRIVMSG #chat :hello", on: session))
		#expect(session.resolveLabeledResponse(for: second) == false)
	}
}

@MainActor
struct ServerSessionDisconnectCallbackTests {
	@Test("Every registered disconnect action runs, not only the last one")
	func allCallbacksRun() {
		let session = TestServerSession()
		let recorder = CallbackRecorder()

		session.addDisconnectCallback { recorder.record("first") }
		session.addDisconnectCallback { recorder.record("second") }

		session.invokeDisconnectCallbacks()

		#expect(recorder.calls == ["first", "second"])
	}

	@Test("Callbacks are cleared once invoked")
	func callbacksRunOnlyOnce() {
		let session = TestServerSession()
		let recorder = CallbackRecorder()

		session.addDisconnectCallback { recorder.record("only") }

		session.invokeDisconnectCallbacks()
		session.invokeDisconnectCallbacks()

		#expect(recorder.calls == ["only"])
	}
}

@MainActor
private final class CallbackRecorder {
	private(set) var calls: [String] = []

	func record(_ value: String) {
		calls.append(value)
	}
}
