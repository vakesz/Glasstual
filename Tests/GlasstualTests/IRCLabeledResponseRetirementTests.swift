/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
struct IRCLabeledResponseRetirementTests {
	private func clientWithLabeledResponse() -> GLTTestClient {
		let client = GLTTestClient()
		client.enableCapability(.messageTags)
		client.enableCapability(.echoMessage)
		client.enableCapability(.labeledResponse)
		return client
	}

	@Test("Resolving a delivery removes it from the pending table")
	func resolvingRemovesPendingEntry() throws {
		let client = clientWithLabeledResponse()
		_ = client.findChannelOrCreate("#chat")
		let label = try #require(client.registerPendingDelivery(for: client.findChannel("#chat")))

		#expect(client.pendingDeliveries.count == 1)

		client.resolveDelivery(withLabel: label, state: .delivered, messageIdentifier: nil, reason: nil)

		#expect(client.pendingDeliveries.count == 0)
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

	@Test("An unknown label is never consumed")
	func unknownLabelIsNotConsumed() throws {
		let client = clientWithLabeledResponse()
		_ = client.findChannelOrCreate("#chat")

		let response = try #require(Message(line: "@label=nope :me!u@h PRIVMSG #chat :hello", on: client))

		#expect(client.resolveLabeledResponse(for: response) == false)
	}
}

@MainActor
struct IRCClientDisconnectCallbackTests {
	@Test("Every registered disconnect action runs, not only the last one")
	func allCallbacksRun() {
		let client = GLTTestClient()
		let recorder = CallbackRecorder()

		client.addDisconnectCallback { recorder.record("first") }
		client.addDisconnectCallback { recorder.record("second") }

		client.invokeDisconnectCallbacks()

		#expect(recorder.calls == ["first", "second"])
	}

	@Test("Callbacks are cleared once invoked")
	func callbacksRunOnlyOnce() {
		let client = GLTTestClient()
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
