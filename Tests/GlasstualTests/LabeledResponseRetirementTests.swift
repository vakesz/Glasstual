/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
private final class DeliveryPresentation: ChatItemPresentation {
	struct Update: Equatable {
		let lineNumber: String
		let state: LogLineDeliveryState
		let messageIdentifier: String?
		let reason: String?
	}

	let presentationIdentifier = "delivery-presentation"
	var updates: [Update] = []
	func print(_: LogLine, completionBlock _: PrintedLineCompletion?) {}
	func lastPrintedLine() -> LogLine? {
		nil
	}

	func setTopic(_: String?) {}
	func mark() {}
	func mark(at _: Date) {}
	func noteReaction(_: String, fromNickname _: String, toMessageIdentifier _: String) {}
	func updateDeliveryState(
		forLineNumber lineNumber: String,
		state: LogLineDeliveryState,
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

	func prependHistoricLogLines(_: [LogLine]) {}
	func tearDown(_: ChatItemTeardown) {}
}

@MainActor
struct LabeledResponseRetirementTests {
	@Test("Unanswered deliveries stop allocating labels at the ceiling")
	func pendingDeliveriesAreBounded() throws {
		let client = clientWithLabeledResponse()
		defer {
			for label in Array(client.pendingDeliveries.keys) {
				client.timeoutDelivery(withLabel: label)
			}
		}
		for _ in 0 ..< LabeledResponsePolicy.maximumPendingDeliveries {
			#expect(client.registerPendingDelivery(for: nil) != nil)
		}
		#expect(client.registerPendingDelivery(for: nil) == nil)
		let label = try #require(client.pendingDeliveries.keys.first)
		client.timeoutDelivery(withLabel: label)
		#expect(client.registerPendingDelivery(for: nil) != nil)
	}

	@Test("Labeled batch associations are bounded and retire with their delivery")
	func batchLabelsAreBoundedAndRetired() throws {
		let client = clientWithLabeledResponse()
		let label = try #require(client.registerPendingDelivery(for: nil))
		client.enableCapability(.batch)
		for index in 0 ... MessageBatchContainer.maximumOpenBatches {
			let message = try #require(Message(line: "@label=\(label) BATCH +b\(index) labeled-response", on: client))
			#expect(client.resolveLabeledResponse(for: message) == false)
			client.receiveBatch(message)
		}
		#expect(client.batchMessages.queuedEntries.values.compactMap(\.responseLabel).count == MessageBatchContainer
			.maximumOpenBatches)
		#expect(client.batchMessages.queuedEntry(withBatchToken: "b\(MessageBatchContainer.maximumOpenBatches)") == nil)

		client.timeoutDelivery(withLabel: label)
		#expect(client.batchMessages.queuedEntries.values.compactMap(\.responseLabel).isEmpty)
		let stale = try #require(Message(line: "@label=\(label) BATCH +stale labeled-response", on: client))
		#expect(client.resolveLabeledResponse(for: stale) == false)
		client.receiveBatch(stale)
		#expect(client.batchMessages.queuedEntries.values.compactMap(\.responseLabel).isEmpty)
	}

	@Test("A duplicate wire batch cannot replace the original delivery label")
	func duplicateBatchLabelIsRejected() throws {
		let client = clientWithLabeledResponse()
		client.enableCapability(.batch)
		let first = try #require(client.registerPendingDelivery(for: nil))
		let second = try #require(client.registerPendingDelivery(for: nil))
		for label in [first, second] {
			let message = try #require(Message(line: "@label=\(label) BATCH +reply labeled-response", on: client))
			#expect(client.resolveLabeledResponse(for: message) == false)
			client.receiveBatch(message)
		}
		#expect(client.batchMessages.queuedEntry(withBatchToken: "reply")?.responseLabel == first)
		let close = try #require(Message(line: "BATCH -reply", on: client))
		#expect(client.resolveLabeledResponse(for: close) == false)
		client.receiveBatch(close)
		#expect(client.pendingDeliveries[first] == nil)
		#expect(client.deliveryState(forLabel: second) == .pending)
		client.timeoutDelivery(withLabel: second)
	}

	private func clientWithLabeledResponse() -> TestClient {
		let client = TestClient()
		client.enableCapability(.messageTags)
		client.enableCapability(.echoMessage)
		client.enableCapability(.labeledResponse)
		return client
	}

	@Test(
		"Nested labeled wire replies commit their final result only after root replay",
		arguments: [true, false],
		[true, false]
	)
	func nestedFailureWinsOverEcho(_ labelOnRoot: Bool, _ failure: Bool) throws {
		let client = clientWithLabeledResponse()
		client.enableCapability(.batch)
		client.isConnected = true
		client.forwardsProcessedMessages = true
		let socket = Connection(config: ConnectionConfig(), onClient: client)
		client.socket = socket
		let channel = try #require(client.findChannelOrCreate("#chat"))
		let presentation = DeliveryPresentation()
		channel.presentation = presentation
		let label = try #require(client.registerPendingDelivery(for: channel))
		client.attachLineNumber("42", toDeliveryWithLabel: label)
		let delivery = try #require(client.pendingDeliveries[label])
		func receive(_ line: String) {
			client.ircConnection(socket, didReceiveData: line)
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
		#expect(client.printedLines.count == 0)
		receive("BATCH -root")
		#expect(delivery.state == (failure ? .failed : .delivered))
		#expect(presentation.updates == [
			.init(lineNumber: "42", state: failure ? .failed : .delivered,
			      messageIdentifier: failure ? nil : "echo", reason: failure ? "Not delivered" : nil),
		])
		#expect(client.pendingDeliveries[label] == nil)
		#expect(client.batchMessages.queuedEntries.isEmpty)
		#expect(client.printedLines.count == 0, "The correlated echo must not print a duplicate outgoing line")
	}

	@Test("A nested replay keeps its ancestry through child close and prints in wire order")
	func nestedReplayPrintsInOrder() {
		let client = clientWithLabeledResponse()
		client.enableCapability(.batch)
		client.enableCapability(.serverTime)
		client.isConnected = true
		client.forwardsProcessedMessages = true
		let socket = Connection(config: ConnectionConfig(), onClient: client)
		client.socket = socket
		_ = client.findChannelOrCreate("#chat")
		for line in [
			"BATCH +root playback",
			"@batch=root BATCH +child example/nested",
			"@batch=child :alice!u@h PRIVMSG #chat :first",
			"BATCH -child",
			"@batch=root :alice!u@h PRIVMSG #chat :second",
			"BATCH -root",
		] {
			client.ircConnection(socket, didReceiveData: line)
		}
		let messages = client.processedMessages.compactMap { $0 as? Message }
		#expect(messages.map { $0.params.last ?? "" } == ["first", "second"])
		#expect(messages.allSatisfy { $0.parentBatchMessage?.isReplay == true })
		let bodies = client.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(bodies == ["first", "second"])
		#expect(client.batchMessages.queuedEntries.isEmpty)
	}

	@Test("A disconnect fails every delivery still waiting instead of leaving it pending")
	func disconnectFailsPendingDeliveries() throws {
		let client = clientWithLabeledResponse()
		let channel = try #require(client.findChannelOrCreate("#chat"))
		let presentation = DeliveryPresentation()
		channel.presentation = presentation
		let label = try #require(client.registerPendingDelivery(for: channel))
		client.attachLineNumber("7", toDeliveryWithLabel: label)
		let delivery = try #require(client.pendingDeliveries[label])

		#expect(client.labeledDeliveryDeadlineTask != nil)

		client.resetCapabilityNegotiation()

		#expect(delivery.state == .failed)
		#expect(presentation.updates == [
			.init(lineNumber: "7", state: .failed, messageIdentifier: nil, reason: "Disconnected"),
		])
		#expect(client.pendingDeliveries.isEmpty)
		#expect(client.labeledDeliveryDeadlineTask == nil)
	}

	@Test("A deadline sweep fails only the deliveries that have come due")
	func deadlineSweepFailsOnlyDueDeliveries() throws {
		let client = clientWithLabeledResponse()
		let overdue = try #require(client.registerPendingDelivery(for: nil))
		let waiting = try #require(client.registerPendingDelivery(for: nil))
		try #require(client.pendingDeliveries[overdue]).deadline = .now - .seconds(1)

		client.failDeliveries(dueBy: .now)

		#expect(client.pendingDeliveries[overdue] == nil)
		#expect(client.deliveryState(forLabel: waiting) == .pending)
		#expect(client.labeledDeliveryDeadlineTask != nil)

		client.resolveDelivery(withLabel: waiting, state: .delivered, messageIdentifier: nil, reason: nil)

		#expect(client.labeledDeliveryDeadlineTask == nil, "Nothing left to wait for")
	}

	@Test("The deadline sweep fails a delivery nobody answered once its deadline passes", .timeLimit(.minutes(1)))
	func deadlineSweepRunsOnItsOwn() async throws {
		let client = clientWithLabeledResponse()
		let delivery = LabeledDelivery()
		delivery.label = "due"
		delivery.state = .pending
		delivery.deadline = .now
		client.pendingDeliveries["due"] = delivery
		_ = try #require(client.registerPendingDelivery(for: nil))

		let sweep = try #require(client.labeledDeliveryDeadlineTask)
		await sweep.value

		#expect(delivery.state == .failed)
		#expect(client.pendingDeliveries["due"] == nil)
		#expect(client.pendingDeliveries.count == 1)
		client.failPendingDeliveriesForDisconnect()
	}

	@Test("Every resolved label is retired rather than accumulating")
	func repeatedDeliveriesDoNotAccumulate() throws {
		let client = clientWithLabeledResponse()
		_ = client.findChannelOrCreate("#chat")

		for _ in 0 ..< 10 {
			let label = try #require(client.registerPendingDelivery(for: client.findChannel("#chat")))
			client.resolveDelivery(withLabel: label, state: .delivered, messageIdentifier: nil, reason: nil)
		}

		#expect(client.pendingDeliveries.count == 0)
	}

	@Test("A label the server reuses after resolution does not swallow the message")
	func reusedLabelIsNotConsumedTwice() throws {
		let client = clientWithLabeledResponse()
		_ = client.findChannelOrCreate("#chat")
		let label = try #require(client.registerPendingDelivery(for: client.findChannel("#chat")))

		let first = try #require(Message(line: "@label=\(label) :me!u@h PRIVMSG #chat :hello", on: client))
		#expect(client.resolveLabeledResponse(for: first))

		let second = try #require(Message(line: "@label=\(label) :me!u@h PRIVMSG #chat :hello", on: client))
		#expect(client.resolveLabeledResponse(for: second) == false)
	}
}

@MainActor
struct ClientDisconnectCallbackTests {
	@Test("Every registered disconnect action runs, not only the last one")
	func allCallbacksRun() {
		let client = TestClient()
		let recorder = CallbackRecorder()

		client.addDisconnectCallback { recorder.record("first") }
		client.addDisconnectCallback { recorder.record("second") }

		client.invokeDisconnectCallbacks()

		#expect(recorder.calls == ["first", "second"])
	}

	@Test("Callbacks are cleared once invoked")
	func callbacksRunOnlyOnce() {
		let client = TestClient()
		let recorder = CallbackRecorder()

		client.addDisconnectCallback { recorder.record("only") }

		client.invokeDisconnectCallbacks()
		client.invokeDisconnectCallbacks()

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
