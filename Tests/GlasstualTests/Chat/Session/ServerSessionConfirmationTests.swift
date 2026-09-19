// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Pending session confirmations", .timeLimit(.minutes(1)))
struct ServerSessionConfirmationTests {
	@Test("Approving a large message cannot send it to a query renamed during confirmation")
	func queryRenameInvalidatesLargeMessageConfirmation() async throws {
		let session = TestServerSession()
		let channel = try #require(session.findConversationOrCreate("alice", isDirect: true))
		channel.activate()
		let (answers, answer) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingOldest(1))
		defer { session.cancelPendingSessionTasks(); answer.finish() }
		session.recordedOutput.confirmation = { _ in
			for await accepted in answers {
				return accepted
			}
			return false
		}
		session.inputText(String(repeating: "private ", count: 300), destination: channel)
		let pending = try #require(session.pendingConfirmationTasks.values.first)
		channel.name = "bob"
		try #require(channel.name == "bob")
		answer.yield(true)
		answer.finish()
		await pending.value
		#expect(session.sentLines.count == 0)
		#expect(session.pendingConfirmationTasks.isEmpty)
	}

	@Test("An answer only acts on its original session and destination", arguments: ["accept", "cancel", "session", "channel"])
	func confirmationLifetime(_ change: String) async throws {
		let session = TestServerSession()
		let channel = try #require(session.findConversationOrCreate("#confirmation"))
		let (answers, answer) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingOldest(1))
		session.recordedOutput.confirmation = { _ in
			for await accepted in answers {
				return accepted
			}
			return false
		}
		var acted = false
		session.requestConfirmation(
			AlertRequest(title: "Confirm", body: "Pending operation", defaultButton: "Continue", alternateButton: "Cancel"),
			isCurrent: { session in
				session.conversationList.contains { $0 === channel }
			},
			perform: { _ in acted = true }
		)
		let pending = try #require(session.pendingConfirmationTasks.values.first)
		switch change {
		case "session": session.cancelPendingSessionTasks()
		case "channel": session.conversationList = []
		default: break
		}
		answer.yield(change != "cancel")
		answer.finish()
		await pending.value
		#expect(acted == (change == "accept"))
		#expect(session.pendingConfirmationTasks.isEmpty)
	}
}
