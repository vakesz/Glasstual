// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Pending client confirmations", .timeLimit(.minutes(1)))
struct ClientConfirmationTests {
	@Test("Approving a large message cannot send it to a query renamed during confirmation")
	func queryRenameInvalidatesLargeMessageConfirmation() async throws {
		let client = TestClient()
		let channel = try #require(client.findChannelOrCreate("alice", isPrivateMessage: true))
		channel.activate()
		let (answers, answer) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingOldest(1))
		defer { client.cancelPendingSessionTasks(); answer.finish() }
		client.recordedOutput.confirmation = { _ in
			for await accepted in answers {
				return accepted
			}
			return false
		}
		client.inputText(String(repeating: "private ", count: 300), destination: channel)
		let pending = try #require(client.pendingConfirmationTasks.values.first)
		channel.name = "bob"
		try #require(channel.name == "bob")
		answer.yield(true)
		answer.finish()
		await pending.value
		#expect(client.sentLines.count == 0)
		#expect(client.pendingConfirmationTasks.isEmpty)
	}

	@Test("An answer only acts on its original session and destination", arguments: ["accept", "cancel", "session", "channel"])
	func confirmationLifetime(_ change: String) async throws {
		let client = TestClient()
		let channel = try #require(client.findChannelOrCreate("#confirmation"))
		let (answers, answer) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingOldest(1))
		client.recordedOutput.confirmation = { _ in
			for await accepted in answers {
				return accepted
			}
			return false
		}
		var acted = false
		client.requestConfirmation(
			AlertRequest(title: "Confirm", body: "Pending operation", defaultButton: "Continue", alternateButton: "Cancel"),
			isCurrent: { client in
				client.channelList.contains { $0 === channel }
			},
			perform: { _ in acted = true }
		)
		let pending = try #require(client.pendingConfirmationTasks.values.first)
		switch change {
		case "session": client.cancelPendingSessionTasks()
		case "channel": client.channelList = []
		default: break
		}
		answer.yield(change != "cancel")
		answer.finish()
		await pending.value
		#expect(acted == (change == "accept"))
		#expect(client.pendingConfirmationTasks.isEmpty)
	}
}
